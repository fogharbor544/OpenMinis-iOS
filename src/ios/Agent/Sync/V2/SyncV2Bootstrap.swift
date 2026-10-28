import Foundation

private let logger = AppLogger(category: "SyncCore")

/// The only sync engine; fresh installations opt in explicitly.
enum SyncV2Bootstrap {

    /// [T-ios-icloud-ckrecordid-nilname-crash] Per-step guard for the
    /// deferred startup chain. Catches Swift errors thrown from `body` and
    /// logs them under a step label so one failing step doesn't take the
    /// rest of startup down with it. ObjC NSException raised inside an
    /// awaited Apple-framework call cannot be caught here (the await
    /// boundary discards the sync stack frame holding the @try); for that
    /// path we validate inputs at the call site (see
    /// `ICloudSharedZoneTransport.isValidCKRecordName`).
    @MainActor
    private static func runGuarded(_ step: String, _ body: @MainActor () async throws -> Void) async {
        do {
            try await body()
        } catch {
            logger.error("[SyncCore] v2 startup step=\(step) FAILED with Swift error: \(error) — continuing")
        }
    }


    /// Fresh installs opt in to the current sync engine.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "cloudSync.v2.enabled")
    }

    static func setEnabled(_ enabled: Bool) {
        let prev = UserDefaults.standard.object(forKey: "cloudSync.v2.enabled") as? Bool ?? false
        UserDefaults.standard.set(enabled, forKey: "cloudSync.v2.enabled")
        logger.info("[SyncCore] v2 enabled flag set to \(enabled) (was \(prev))")
        // When the user disables iCloud Sync, stop the active SyncCore +
        // transports immediately so dirty queue drains pause and no more
        // fetch/push fires until they opt back in. Without this, the
        // engine keeps running with stale credentials for the rest of
        // the launch — the indicator hides via @AppStorage observation,
        // but background CKQuery traffic continues. Re-enabling still
        // requires a relaunch because boot wiring is non-idempotent.
        if prev == true && enabled == false {
            if #available(iOS 17.0, *) {
                Task { await SyncCore.shared.stop() }
            }
        }
        // T-v2-hot-enable: user flipped the toggle ON after launch. Older
        // builds required a relaunch because boot only ran from MinisApp
        // launch path — leaving the engine in 'Starting…' with
        // transports=0, isRunning=false, and sendNow warnings forever.
        // Bootstrap is now idempotent (SyncCore.register dedups by name,
        // type/hydrator registries overwrite-as-self, SyncCore.start
        // guards on isRunning), so it is safe to invoke from here.
        if prev == false && enabled == true {
            if #available(iOS 17.0, *) {
                Task { @MainActor in
                    await SyncV2Bootstrap.startIfEnabled()
                }
            }
        }
    }

    private static var provisionalRetryTask: Task<Void, Never>?

    /// Called once from MinisApp launch (or on flag flip in debug builds).
    /// Idempotent — running twice is harmless.
    @MainActor
    static func startIfEnabled() async {
        guard isEnabled else {
            logger.debug("[SyncCore] v2 disabled (flag off) — sync remains off")
            return
        }
        guard #available(iOS 17.0, *) else {
            logger.warning("[SyncCore] v2 requires iOS 17+ — disabling")
            return
        }

        guard !DeviceIdentity.isProvisional else {
            // [T-icloud-device-provisional-retry] On iOS a later scenePhase →
            // .active retries this. On an iPad app running on macOS Apple does
            // not document which scene-phase transitions fire on window close
            // vs quit, so the retry is not guaranteed — and a device that never
            // registers is invisible to peers AND blind to them. Arm a timed
            // retry as well; idempotent (one pending at a time).
            logger.warning("[SyncCore] v2 startup deferred — device identity is provisional (keychain locked after reboot); retrying in 30s and on next activation")
            if provisionalRetryTask == nil {
                provisionalRetryTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                    provisionalRetryTask = nil
                    if !DeviceIdentity.isProvisional {
                        logger.info("[SyncCore] device identity now available — starting v2 (timed retry)")
                        await startIfEnabled()
                    } else {
                        logger.warning("[SyncCore] device identity still provisional after 30s; will retry again")
                        // re-enter to re-arm
                        await startIfEnabled()
                    }
                }
            }
            return
        }

        logger.info("[SyncCore] v2 startup STEP=begin")

        // 1. Register all Syncable types.
        SyncedTypesBootstrap.registerAll()
        logger.info("[SyncCore] v2 startup STEP=typesRegistered count=\(SyncableTypeRegistry.shared.count)")

        await ChatStore.shared.setSyncZoneName(DeviceIdentity.zoneName)
        logger.info("[SyncCore] v2 startup STEP=zoneNameSet")

        // 2. Register hydrators (builders + mergers + deletion appliers)
        //    for the types whose stores are owned by ChatStore. Only
        //    Session and Message are real first-class merge paths in
        //    this initial wiring; the rest get builder-only hooks so
        //    pushes work but inbound is logged + skipped (to be filled
        //    in subsequent patches).
        await ChatStoreSyncHydrators.registerAll()
        logger.info("[SyncCore] v2 startup STEP=hydratorsRegistered")

        // 3. Wire transports (cheap — no network yet).
        let transport = ICloudSharedZoneTransport()
        SyncCore.shared.register(transport)
        // LAN skeleton stays unregistered (LANTransport.isImplemented = false).
        logger.info("[SyncCore] v2 startup STEP=transportRegistered")

        // 4. Defer the network-touching part of startup so the app's
        //    cold-launch (UI hydration, ChatStore SQLite warmup, web
        //    view boots) doesn't compete with CloudKit fetchChanges /
        //    initial sendChanges for CPU + main thread time. We've
        //    observed 30%+ CPU spikes during the first minute when v2
        //    boots in parallel with the chat list rendering.
        let bootDelay: TimeInterval = 15
        let bootDeadline = Date().addingTimeInterval(bootDelay)
        SyncCore.shared.bootDelayUntil = bootDeadline
        logger.info("[SyncCore] v2 startup STEP=deferring network boot by \(Int(bootDelay))s")
        Task { @MainActor in
            do {
                try? await Task.sleep(nanoseconds: UInt64(bootDelay * 1_000_000_000))
                logger.info("[SyncCore] v2 startup STEP=coreStart begin (post-delay)")
                await runGuarded("coreStart") {
                    await SyncCore.shared.start()
                }
                // Keep the indicator on the wakeup timer until start() actually
                // returns isRunning=true, otherwise the few seconds spent in
                // ensureZonesExist / initialSendChanges show as 'Stopped'.
                SyncCore.shared.bootDelayUntil = nil
                logger.info("[SyncCore] v2 startup STEP=coreStart done")
                // Self-register this device into minis-devices zone so peers
                // can list us (and we'll fetch their records back). Re-runs
                // on every launch — markDirty is idempotent (INSERT OR
                // REPLACE in sync_dirty_records); the record's lastSeen
                // field updates each time so peers see freshness.
                await runGuarded("deviceRegister") {
                    await ChatStore.shared.markDirty(
                        recordType: "SyncDeviceV2",
                        recordId: DeviceIdentity.deviceId
                    )
                    // [T-icloud-device-retire-old-id] If this install just
                    // re-minted its id, retire the previous one: tombstone it
                    // locally (so a stale echo cannot resurrect it) and queue
                    // op=delete so peers drop the ghost row. Older peers ignore
                    // a delete for a type they never delete — harmless.
                    if let old = DeviceIdentity.takeRetiredDeviceId() {
                        await ChatStore.shared.recordDeletedRecordTombstone(type: "SyncDeviceV2", id: old)
                        await ChatStore.shared.markDirty(recordType: "SyncDeviceV2", recordId: old, operation: "delete")
                        logger.info("[SyncCore] retiring previous device id \(old.prefix(8)) (op=delete queued)")
                    }
                }
                logger.info("[SyncCore] v2 startup STEP=device registered (deviceId=\(DeviceIdentity.deviceId.prefix(8)))")
                SyncDirtyScanner.shared.start()
                logger.info("[SyncCore] v2 startup STEP=dirtyScanner started")
                await runGuarded("initialFlush") {
                    await SyncCore.shared.sendNow(trigger: .manual)
                }
                logger.info("[SyncCore] v2 startup STEP=initialFlush done")
                logger.info("[SyncCore] v2 startup complete")
            } catch {
                logger.error("[SyncCore] v2 startup aborted with Swift error: \(error)")
            }
        }
    }
}

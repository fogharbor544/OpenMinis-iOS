import Foundation

private let logger = AppLogger(category: "ProviderRestore")

@MainActor
enum ProviderBackupMerger {
    static func restore(_ remote: ProviderConfig) async {
        // Read the authoritative current state from the store's in-memory config,
        // NOT from disk. Reading from disk would lose any changes still in-flight
        // between a UI edit and the debounced disk write (tiny but real window),
        // and would silently overwrite per-device-only fields (sessionBindings,
        // sessionInferenceConfigs, default pointers) if the disk was stale.
        let store = ProviderConfigStore.shared
        var local = store.config

        let localInstanceIds = Set(local.instances.map { $0.id })
        let localGroupIds = Set(local.modelGroups.map { $0.id })

        // Merge strategy: genuine remote change (not our own echo).
        // Remote wins for same-ID items (propagates edits, renames, member changes).
        // Local-only items (not in remote) are kept (they haven't been synced yet).
        //
        // Tombstones drive deletion semantics. Union by id of local + remote
        // tombstones survives the merge (so the next device that sees this
        // record also sees the delete intent). An item whose id is in the
        // tombstone union with `deletedAt > the would-be-resurrected entry's
        // updatedAt-ish stamp` is suppressed. ProviderInstance has no per-row
        // updatedAt, so we apply tombstones unconditionally to instances —
        // a same-id "re-add" would have to happen on the device that holds
        // the tombstone (where removeInstance has already wiped it).
        //
        // [T-backup-restore-tombstone] Except on RESTORE. Deleting a group
        // records its id in `deletedModelGroups`, and the filters below drop
        // every package item in the tombstone union, so "delete a group, then
        // restore the backup" returned the group to nobody: the merge removed
        // it, reported success, and the user saw it gone. On restore the
        // package is the user's explicit intent, so its ids clear their local
        // tombstones, and its own tombstones are not applied (a restore never
        // deletes). Same rule for instances and entries: same code, same bug.
        let preRestoreConfig = local
        let mergedInstanceTombstones: [ProviderConfigTombstone]
        let mergedEntryTombstones: [ProviderConfigTombstone]
        let mergedGroupTombstones: [ProviderConfigTombstone]
        do {
            mergedInstanceTombstones = ProviderConfigTombstone.survivingRestore(
                local.deletedInstances, restoring: Set(remote.instances.map(\.id)))
            mergedEntryTombstones = ProviderConfigTombstone.survivingRestore(
                local.deletedModelEntries, restoring: Set(remote.modelEntries.map(\.id)))
            mergedGroupTombstones = ProviderConfigTombstone.survivingRestore(
                local.deletedModelGroups, restoring: Set(remote.modelGroups.map(\.id)))
            let revived = local.deletedModelGroups.count - mergedGroupTombstones.count
            if revived > 0 {
                logger.info("[Restore] provider merge: \(revived) deleted model group(s) restored from the backup (local tombstones cleared)")
            }
        }
        let tombstonedInstanceIds = Set(mergedInstanceTombstones.map(\.id))
        let tombstonedEntryIds    = Set(mergedEntryTombstones.map(\.id))
        let tombstonedGroupIds    = Set(mergedGroupTombstones.map(\.id))

        // 1. Merge instances — remote wins for same-id, keep local-only,
        //    suppress anything in the tombstone union.
        var instanceMap = Dictionary(local.instances.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for ri in remote.instances where !tombstonedInstanceIds.contains(ri.id) {
            instanceMap[ri.id] = ri  // remote wins for existing; adds new
        }
        for tid in tombstonedInstanceIds {
            instanceMap.removeValue(forKey: tid)
        }
        // [T-backup-restore-order] Ordering is USER DATA here: the provider
        // list is drag-reorderable, and `config.instances`'s array order is
        // what carries it (ProviderConfigDB writes the array index into
        // `sort_order` and reads back `ORDER BY sort_order`).
        //
        // Sorting by `createdAt` is right for SYNC — two devices must converge
        // on the same order from the same set, and neither one's arrangement is
        // authoritative. It is wrong for RESTORE: the package records the order
        // the user arranged, and rebuilding by creation date discards it, which
        // is the reported "恢复会把服务商、分组的排序全部打乱".
        //
        // On restore: take the backup's order first, then append local-only
        // instances (which the backup could not know about) after it, keeping
        // their relative order. That makes the restored device match the
        // backup for everything the backup contained, and leaves anything
        // added since at the end rather than interleaved by date.
        do {
            var ordered: [ProviderInstance] = []
            var placed = Set<String>()
            for ri in remote.instances {
                if let merged = instanceMap[ri.id] {
                    ordered.append(merged)
                    placed.insert(ri.id)
                }
            }
            for li in local.instances where !placed.contains(li.id) {
                if let merged = instanceMap[li.id] {
                    ordered.append(merged)
                    placed.insert(li.id)
                }
            }
            // Anything only reachable through the map (defensive; should be
            // covered above) keeps the previous deterministic ordering.
            for inst in instanceMap.values where !placed.contains(inst.id) {
                ordered.append(inst)
            }
            local.instances = ordered
        }
        // Drop modelEntries whose providerInstanceId was tombstoned. The
        // remote snapshot may still carry orphaned entries pointing at the
        // tombstoned instance; the local snapshot was already pruned by
        // removeInstance. Either way, after this merge no instance =>
        // no entries that belong to it.
        local.modelEntries.removeAll { tombstonedInstanceIds.contains($0.providerInstanceId) }

        // 2. Restore every missing model, including API-discovered entries.
        // Existing models retain local API metadata and newer user overrides.
        // Stable (instance, model) IDs keep restored group references intact.
        let localEntriesSnapshot = local.modelEntries

        // Index local entries for lookup by (instanceId, baseModelId).
        struct EntryKey: Hashable { let instanceId: String; let modelId: String }
        var localIndex: [EntryKey: Int] = [:]
        for (idx, e) in local.modelEntries.enumerated() {
            localIndex[EntryKey(instanceId: e.providerInstanceId, modelId: e.baseModel.id)] = idx
        }

        var accepted = 0
        var skipped = 0
        var appliedOverrides = 0
        var appliedHidden = 0
        var insertedMissing = 0
        var skippedLegacyOverlay = 0   // remote had no userModifiedAt → overrides/isHidden not applied
        var skippedOlderRemote = 0     // remote userModifiedAt <= local userModifiedAt

        // Drop locally-known entries the union of tombstones marks as deleted.
        // Done before the remote loop so localIndex (built above) stays
        // consistent with the post-merge state. modelEntries that belong
        // to a tombstoned instance were already removed above.
        if !tombstonedEntryIds.isEmpty {
            local.modelEntries.removeAll { tombstonedEntryIds.contains($0.id) }
            // Rebuild localIndex so the per-key lookup below still works.
            localIndex.removeAll(keepingCapacity: true)
            for (idx, e) in local.modelEntries.enumerated() {
                localIndex[EntryKey(instanceId: e.providerInstanceId, modelId: e.baseModel.id)] = idx
            }
        }

        for re in remote.modelEntries {
            // Suppress entries the union of tombstones marks as deleted,
            // including any entries that hung off an instance the user
            // deleted on this device.
            if tombstonedEntryIds.contains(re.id) { continue }
            if tombstonedInstanceIds.contains(re.providerInstanceId) { continue }
            let key = EntryKey(instanceId: re.providerInstanceId, modelId: re.baseModel.id)
            if let idx = localIndex[key] {
                guard re.isUserModified else { skipped += 1; continue }
                accepted += 1
                // Local already has this model id under this instance.
                //
                // Timestamp-based conflict resolution for overlay (overrides + isHidden):
                //   - Remote has no userModifiedAt → LEGACY data (pre-upgrade or not
                //     stamped by the uploader). Skip the overlay entirely to prevent
                //     stale override names from quietly re-appearing on newer devices.
                //   - Local has userModifiedAt but remote is older-or-equal → local wins.
                //   - Otherwise → remote wins, apply.
                //
                // We never touch baseModel (API truth) or isCustom (local Refresh owns it).
                let localEntry = local.modelEntries[idx]

                let remoteIsApplicable: Bool
                if re.userModifiedAt == nil {
                    remoteIsApplicable = false
                    skippedLegacyOverlay += 1
                } else if let localStamp = localEntry.userModifiedAt,
                          let remoteStamp = re.userModifiedAt,
                          remoteStamp <= localStamp {
                    remoteIsApplicable = false
                    skippedOlderRemote += 1
                } else {
                    remoteIsApplicable = true
                }

                guard remoteIsApplicable else { continue }

                var updated = localEntry
                var didChange = false
                if updated.overrides != re.overrides {
                    updated.overrides = re.overrides
                    appliedOverrides += 1
                    didChange = true
                }
                if updated.isHidden != re.isHidden {
                    updated.isHidden = re.isHidden
                    appliedHidden += 1
                    didChange = true
                }
                if didChange {
                    // Carry remote's userModifiedAt forward so subsequent merges on
                    // this device compare against the winning timestamp.
                    updated.userModifiedAt = re.userModifiedAt
                    local.modelEntries[idx] = updated
                }
            } else {
                local.modelEntries.append(re)
                localIndex[key] = local.modelEntries.count - 1
                insertedMissing += 1
            }
        }

        // Per-instance before/after diff (unchanged structure — but now should be
        // mostly empty in the steady state, which is the whole point of the rewrite).
        let beforeByInstance = Dictionary(grouping: localEntriesSnapshot, by: { $0.providerInstanceId })
        let afterByInstance = Dictionary(grouping: local.modelEntries, by: { $0.providerInstanceId })
        let allInstanceIds = Set(beforeByInstance.keys).union(afterByInstance.keys)
        for iid in allInstanceIds {
            let beforeIds = Set((beforeByInstance[iid] ?? []).map { $0.baseModel.id })
            let afterIds = Set((afterByInstance[iid] ?? []).map { $0.baseModel.id })
            guard beforeIds != afterIds else { continue }
            let added = afterIds.subtracting(beforeIds).sorted()
            let removed = beforeIds.subtracting(afterIds).sorted()
            let instanceLabel = local.instances.first(where: { $0.id == iid })?.label ?? "?"
            logger.info("[ModelList] mergeProviderConfig: instance=\(instanceLabel)(\(iid.prefix(8))) before=\(beforeIds.count) after=\(afterIds.count) added=\(added.count)[\(added.prefix(10).joined(separator: ","))] removed=\(removed.count)[\(removed.prefix(10).joined(separator: ","))]")
        }
        logger.info("[ModelList] mergeProviderConfig: remoteEntries=\(remote.modelEntries.count) accepted=\(accepted) skipped=\(skipped) appliedOverrides=\(appliedOverrides) appliedHidden=\(appliedHidden) insertedMissing=\(insertedMissing) skippedLegacyOverlay=\(skippedLegacyOverlay) skippedOlderRemote=\(skippedOlderRemote) totalAfter=\(local.modelEntries.count)")

        // 3. Merge modelGroups — same-id: remote wins. Same-name different-id:
        // collapse (both devices independently created a group with the same
        // name; converge them onto a single id — prefer the smaller id string
        // as the stable winner so both devices deterministically agree).
        //
        // This replaces the old "(device name) suffix on name collision" logic
        // that produced permanent forks: two devices with a "Coding" group ended
        // up showing BOTH "Coding" and "Coding (iPhone...)" on both sides forever.
        // Pre-filter locally-known groups by the tombstone union (the local
        // side already pruned them in removeGroup; this guard handles
        // an incoming remote that still has them, plus same-id resurrection).
        if !tombstonedGroupIds.isEmpty {
            local.modelGroups.removeAll { tombstonedGroupIds.contains($0.id) }
        }
        var groupMap = Dictionary(local.modelGroups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let orderLogReason = "restore-merge"
        var groupIdRewrites: [String: String] = [:]  // oldRemoteId -> canonicalLocalId
        // Build a local name index for collision detection.
        var localGroupByName: [String: String] = [:]  // name -> id
        for g in local.modelGroups { localGroupByName[g.name] = g.id }
        for rg in remote.modelGroups {
            if tombstonedGroupIds.contains(rg.id) { continue }
            // Strip out member references to tombstoned entries so a stale
            // remote member list doesn't carry deleted ids forward.
            var rg = rg
            if !tombstonedEntryIds.isEmpty {
                rg.memberEntryIds.removeAll { tombstonedEntryIds.contains($0) }
            }
            if let localGroup = groupMap[rg.id] {
                // Same id — use REMOTE member order as primary. This function
                // is only reached when the remote is NOT our own echo (own-echo
                // skip above) AND local has no pending dirty upload (dirty-skip
                // above), so the remote represents a peer's latest edit whose
                // order should be respected. Local-only members (concurrent adds
                // the peer hasn't seen) are appended at the end so no member is
                // lost. This aligns with the V3 DB-level upsertGroupFromInbound
                // which uses updatedAt LWW — the two converge because the remote
                // arriving here is the newer-or-equal side (local is clean).
                var merged = rg  // start from remote for scalar fields + order
                var order = rg.memberEntryIds
                let remoteSet = Set(order)
                for mid in localGroup.memberEntryIds where !remoteSet.contains(mid) {
                    order.append(mid)
                }
                merged.memberEntryIds = order
                GroupOrderLog.note(reason: orderLogReason, groupId: rg.id, name: rg.name,
                                   before: localGroup.memberEntryIds, after: order, warnOnReorder: true,
                                   detail: "path=same-id winner=remote remote=\(GroupOrderDiff.describe(rg.memberEntryIds))")
                groupMap[rg.id] = merged
            } else if let collidingLocalId = localGroupByName[rg.name], collidingLocalId != rg.id {
                // Same name, different id → collapse onto the lexicographically
                // smaller id so both devices deterministically pick the same winner.
                let canonicalId = min(collidingLocalId, rg.id)
                let otherId = max(collidingLocalId, rg.id)
                groupIdRewrites[otherId] = canonicalId

                if canonicalId == collidingLocalId {
                    // Local id wins: merge remote's memberEntryIds union into local, prefer local's other fields.
                    if var winner = groupMap[canonicalId] {
                        let orderBefore = winner.memberEntryIds   // [T-group-order-log]
                        var seen = Set(winner.memberEntryIds)
                        for mid in rg.memberEntryIds where !seen.contains(mid) {
                            winner.memberEntryIds.append(mid)
                            seen.insert(mid)
                        }
                        GroupOrderLog.note(reason: orderLogReason, groupId: canonicalId, name: winner.name,
                                           before: orderBefore, after: winner.memberEntryIds, warnOnReorder: true,
                                           detail: "path=same-name winner=local collapsed=\(otherId.prefix(8)) remote=\(GroupOrderDiff.describe(rg.memberEntryIds))")
                        groupMap[canonicalId] = winner
                    }
                } else {
                    // Remote id wins: install remote, but merge in the old local memberEntryIds
                    // so nothing is lost. Drop the old local entry under collidingLocalId.
                    var winner = rg
                    if let oldLocal = groupMap[collidingLocalId] {
                        var seen = Set(winner.memberEntryIds)
                        for mid in oldLocal.memberEntryIds where !seen.contains(mid) {
                            winner.memberEntryIds.append(mid)
                            seen.insert(mid)
                        }
                        // [T-group-order-log] The local group of that name is
                        // replaced by the remote one: its order is the remote's.
                        GroupOrderLog.note(reason: orderLogReason, groupId: canonicalId, name: winner.name,
                                           before: oldLocal.memberEntryIds, after: winner.memberEntryIds, warnOnReorder: true,
                                           detail: "path=same-name winner=remote collapsed=\(otherId.prefix(8)) remote=\(GroupOrderDiff.describe(rg.memberEntryIds))")
                    }
                    groupMap.removeValue(forKey: collidingLocalId)
                    groupMap[canonicalId] = winner
                    localGroupByName[winner.name] = canonicalId
                }
                logger.info("[ModelList] mergeProviderConfig: group name collision '\(rg.name)' collapsed: \(otherId.prefix(8)) -> \(canonicalId.prefix(8))")
            } else {
                // Brand new group — no id clash, no name clash. Just add it.
                groupMap[rg.id] = rg
                localGroupByName[rg.name] = rg.id
            }
        }
        // [T-backup-restore-order] `Dictionary.values` has NO defined order, so
        // this line alone could reshuffle the group list on every merge —
        // worse than the instances case, which at least sorted by date.
        // Rebuild deterministically: the backup's order first on a restore,
        // then whatever is local-only; for sync, keep the local arrangement
        // and append newly-arrived groups, so a pull does not rearrange a list
        // the user dragged into place.
        do {
            var orderedGroups: [ModelGroup] = []
            var placedGroups = Set<String>()
            for rg in remote.modelGroups {
                // The id may have been rewritten by the name-collision pass
                // above, so resolve through the map rather than trusting `rg`.
                if let merged = groupMap[rg.id] {
                    orderedGroups.append(merged)
                    placedGroups.insert(merged.id)
                }
            }
            for lg in local.modelGroups where !placedGroups.contains(lg.id) {
                if let merged = groupMap[lg.id] {
                    orderedGroups.append(merged)
                    placedGroups.insert(merged.id)
                }
            }
            for g in groupMap.values where !placedGroups.contains(g.id) {
                orderedGroups.append(g)
                placedGroups.insert(g.id)
            }
            local.modelGroups = orderedGroups
        }

        // Fix up dangling references to group ids we rewrote. Defaults / agent
        // loop lists live outside the group array itself but point at group ids.
        if !groupIdRewrites.isEmpty {
            if let def = local.defaultPrimaryGroupId, let replacement = groupIdRewrites[def] {
                local.defaultPrimaryGroupId = replacement
            }
            if let def = local.defaultSubGroupId, let replacement = groupIdRewrites[def] {
                local.defaultSubGroupId = replacement
            }
            local.agentLoopGroupIds = local.agentLoopGroupIds.map { groupIdRewrites[$0] ?? $0 }
        }

        // 4. Don't touch: defaultPrimaryGroupId, defaultSubGroupId, agentLoopModelEntryIds,
        //    agentLoopModelGroupIds, sessionBindings, sessionInferenceConfigs.
        //    These stay per-device independent (reading from store.config above
        //    ensures we're preserving the latest in-memory values, not stale disk).

        // L1 — "localHasUnique" is now computed over *user intent*, not UUID sets.
        // Under the new model, modelEntries on the wire carry the full list but
        // only `isUserModified` entries are semantically meaningful. A UUID-diff
        // falsely reported "unique" for API-truth entries that differ purely
        // because each device fetched the list independently, triggering an
        // infinite ping-pong re-upload loop throttled only by 60s.
        //
        // Real uniqueness signal: local has a user-modified entry (by instance +
        // model.id) that isn't present in remote as user-modified, OR local has
        // an instance/group id remote doesn't. Anything else is noise.
        let remoteInstanceIds = Set(remote.instances.map { $0.id })
        let remoteGroupIds = Set(remote.modelGroups.map { $0.id })
        struct EntryIntentKey: Hashable { let instanceId: String; let modelId: String }
        let remoteUserIntentKeys: Set<EntryIntentKey> = Set(
            remote.modelEntries.filter(\.isUserModified).map {
                EntryIntentKey(instanceId: $0.providerInstanceId, modelId: $0.baseModel.id)
            }
        )
        let localUserIntentKeys: Set<EntryIntentKey> = Set(
            local.modelEntries.filter(\.isUserModified).map {
                EntryIntentKey(instanceId: $0.providerInstanceId, modelId: $0.baseModel.id)
            }
        )
        // Tombstones the local side knows about but remote doesn't — these
        // need to be re-uploaded so the remote learns of the delete.
        let remoteTombstoneIds = Set(remote.deletedInstances.map(\.id))
            .union(remote.deletedModelEntries.map(\.id))
            .union(remote.deletedModelGroups.map(\.id))
        let localTombstoneIds = Set(local.deletedInstances.map(\.id))
            .union(local.deletedModelEntries.map(\.id))
            .union(local.deletedModelGroups.map(\.id))
        let localHasUniqueTombstones = !localTombstoneIds.subtracting(remoteTombstoneIds).isEmpty
        let localHasUnique = !localInstanceIds.subtracting(remoteInstanceIds).isEmpty
            || !localUserIntentKeys.subtracting(remoteUserIntentKeys).isEmpty
            || !localGroupIds.subtracting(remoteGroupIds).isEmpty
            || localHasUniqueTombstones

        // Write back the union of tombstones so a third device pulling this
        // record also learns of the delete. Without this the delete intent
        // would only live on the device that issued it.
        local.deletedInstances    = mergedInstanceTombstones
        local.deletedModelEntries = mergedEntryTombstones
        local.deletedModelGroups  = mergedGroupTombstones


        // Commit: push merged config into store (in-memory + disk) WITHOUT
        // triggering a markDirty upload. We control the re-upload decision
        // explicitly below via localHasUnique.
        store.applyMergedConfigFromSync(local, source: "restore")
        logger.info("[iCloud] mergeProviderConfig: merged \(instanceMap.count) instances, \(local.modelEntries.count) entries, \(local.modelGroups.count) groups")

        // A restore is user-initiated local authorship, not an inbound echo:
        // mark dirty unconditionally so the restored providers propagate, and
        // skip the anti-ping-pong throttle (which exists to damp device-to-
        // device loops that a manual restore is not part of). §8.3 wants
        // restored rows re-uploaded under this device's identity.
        do {
            // [T-backup-restore-tombstone] The "ProviderConfig" row above is
            // dual-written as the whole-file ProviderConfigV2 record, which
            // every v3 device drops on receipt, and applyMergedConfigFromSync
            // deliberately emits no v3 records (it is built for INBOUND data).
            // So a restore never reached the user's other devices: a restored
            // group existed here only, and a peer that had applied the delete
            // kept it deleted. Emit the per-record v3 upserts for what the
            // restore changed, exactly as a local edit would.
            let prior = preRestoreConfig
            Task { await store.markRestoredRecordsDirty(prior: prior) }
            logger.info("[iCloud] mergeProviderConfigForRestore: merged and marked dirty")
            return
        }

    }
}

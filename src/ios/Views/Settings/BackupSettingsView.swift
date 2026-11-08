import SwiftUI

private let logger = AppLogger(category: "Backup")

/// Minimal user-facing entry point for creating a backup package
/// (docs/backup-restore-design.md §6.2 path 1).
///
/// Pick categories, optionally set a passphrase, and save in Minis / Backups.
/// Sharing a copy is optional. Restore reads the same folder.
struct BackupSettingsView: View {
    /// True when hosted inside `BackupAndRestoreView`, which owns the
    /// navigation title. Without this the child would overwrite the
    /// container's "Backup & Restore" with its own "Backup".
    var embedded = false

    @State private var selected: Set<BackupCategory> = BackupCategory.defaultSelection
    /// The Include toggles are styled like the iCloud settings rows, and rows
    /// that look like settings are expected to SURVIVE leaving the screen —
    /// a fresh launch used to silently reset a trimmed selection back to
    /// everything, so the next backup was much bigger than the user chose.
    /// Stored as raw values joined by comma; unknown values from a future
    /// build are dropped on load.
    @AppStorage("backup.selectedCategories") private var selectedStore: String = ""
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""

    /// §3.4 per-file cap, in MB. Persisted so the choice survives leaving the
    /// screen — it is a preference, not a per-run decision.
    ///
    /// Default 100 MB rather than §3.4's "unlimited": an unlimited backup of a
    /// chat history with large attachments can run to many GB, which is slow to
    /// produce and awkward to move around. A file over the cap is NOT silently
    /// dropped — it leaves a tombstone the restore surfaces — so the trade-off
    /// is visible rather than lossy-and-quiet.
    @AppStorage("backup.maxFileSizeMB") private var maxFileSizeMB: Int = 100

    /// Sentinel for "no cap" (§3.4's `maxFileBytes == nil`).
    static let unlimitedTag = 0

    /// Sentinel for "skip file contents entirely" — messages and metadata only.
    ///
    /// Negative rather than 0 because 0 already means unlimited, and the stored
    /// value is a plain MB Int in AppStorage that predates this option.
    ///
    /// Maps to `maxFileBytes = 0`, so it rides the EXISTING cap logic rather
    /// than adding a second way to skip a file: every file is over the cap, so
    /// each one is counted and gets a §3.4 tombstone. That matters — the
    /// package still records which files existed, so a restore reports them as
    /// deliberately excluded instead of silently missing.
    static let noFilesTag = -1

    /// [T-backup-credentials-without-encryption] Categories whose export puts
    /// real credentials in the package, and therefore the ones whose selection
    /// makes the unencrypted warning worth showing.
    ///
    /// `.mcpServers` belongs here for a reason that is easy to miss:
    /// `mcp_servers.json` is copied verbatim, so any custom header the user
    /// authored — an `Authorization: Bearer …` among them — travels in the
    /// clear whether or not `.providers` was selected.
    static let credentialCarryingCategories: Set<BackupCategory> = [
        .providers, .environmentVariables, .mcpServers,
    ]

    /// Whether to encrypt. Defaults OFF, so the common case — back up, keep the
    /// file — takes no passphrase and nothing to forget.
    ///
    /// Browser passwords and cookies always require encryption; other credential categories
    /// keep their existing policy.
    @AppStorage("backup.encrypt") private var encryptBackup: Bool = false

    @State private var isExporting = false
    @State private var errorText: String?
    @State private var result: BackupExporter.Summary?
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showSaveToFiles = false
    @ObservedObject private var history = BackupHistory.shared
    @ObservedObject private var runController = BackupRunController.shared

    /// [T-backup-device-name-setting] Working copy of the user's device name.
    ///
    /// Held in @State and committed on change rather than bound straight to
    /// `DeviceIdentity.customName`: the field must be able to be empty WHILE
    /// being edited (the user clears it to retype), and writing an empty
    /// string through immediately would clear the override and make the
    /// placeholder jump to the automatic name mid-keystroke.
    @State private var deviceNameDraft = ""

    var body: some View {
        Form {
            deviceNameSection
            Section {
                // Row styling mirrors the iCloud Sync category list
                // (CloudSyncSettingsV2View): a 28pt rounded-square badge with a
                // white glyph. Same kind of choice, so it should look the same
                // rather than inventing a second visual language for it.
                ForEach(BackupCategory.backupable, id: \.self) { category in
                    Toggle(isOn: binding(for: category)) {
                        HStack(spacing: 12) {
                            BackupCategoryIcon(category: category)
                            Text(displayName(category))
                        }
                    }
                }

                // §3.4's cap, surfaced. Only meaningful when a category that
                // actually carries files is selected — with only DB-backed
                // categories on, nothing would ever hit it.
                if selected.contains(where: \.carriesFileTree) {
                    // Ordered smallest to largest, with "no files at all" at
                    // the top as the extreme of the same axis.
                    Picker(selection: $maxFileSizeMB) {
                        Text("Don't back up files").tag(BackupSettingsView.noFilesTag)
                        Text("1 MB").tag(1)
                        Text("2 MB").tag(2)
                        Text("5 MB").tag(5)
                        Text("10 MB").tag(10)
                        Text("50 MB").tag(50)
                        Text("100 MB").tag(100)
                        Text("500 MB").tag(500)
                        Text("Unlimited").tag(BackupSettingsView.unlimitedTag)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.zipper")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.gray, in: Circle())
                            Text("Max Per-File Size")
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Include")
            } footer: {
                Text("Agent definitions and memory are included with chats, providers or environment variables. Select all categories for a device migration.")
                Text("Browser passwords and cookies require an encrypted backup.")
                if selected.contains(.sharedFiles) && !selected.contains(.browserPasswords) {
                    Text("Select Browser Passwords to include the shared password vault.")
                }
                if selected.contains(.browserCookies) {
                    Text("Cookies can restore website sign-ins. Some websites may still require you to sign in again.")
                }
                // The cap's consequence is stated, because §3.4's whole point is
                // that a skipped file leaves a tombstone rather than silently
                // vanishing — the user should know that before it happens, not
                // discover it at restore time.
                if selected.contains(where: \.carriesFileTree),
                   maxFileSizeMB == Self.noFilesTag {
                    // Worth stating plainly: this is the one setting that makes
                    // the backup unable to restore a conversation's files at
                    // all, so it should not read like just another size.
                    Text("Chats includes every file in each conversation, not just the messages. File contents are not being backed up — the backup lists which files existed, but restoring won't bring them back.")
                } else if selected.contains(where: \.carriesFileTree),
                          maxFileSizeMB != Self.unlimitedTag {
                    Text("Chats includes every file in each conversation, not just the messages. Files larger than \(maxFileSizeMB) MB are listed in the backup but not included.")
                } else {
                    Text("Chats includes every file in each conversation, not just the messages.")
                }
            }

            // Encryption is a CHOICE; the passphrase only appears once it's on.
            //
            // The constraint that actually exists is narrower than "always
            // encrypt": credentials must never ship in the clear, because
            // secrets.json is base64 — an encoding, not protection. So
            // encryption is optional, and turning it OFF drops credentials from
            // the package rather than exposing them. The exporter enforces the
            // same rule independently (it refuses credentials without a
            // passphrase), so this is the UI expressing a real invariant, not
            // inventing one.
            Section {
                Toggle(isOn: $encryptBackup.animation()) {
                    HStack(spacing: 12) {
                        Image(systemName: encryptBackup ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(encryptBackup ? Color.green : Color.gray,
                                        in: Circle())
                        Text("Encrypt Backup")
                    }
                }
                .disabled(selected.contains(where: \.requiresEncryptedBackup))
                if encryptBackup {
                    SecureField("Passphrase", text: $passphrase)
                        .textContentType(.newPassword)
                    if !passphrase.isEmpty {
                        SecureField("Confirm passphrase", text: $confirmPassphrase)
                            .textContentType(.newPassword)
                        if passphrase != confirmPassphrase {
                            Text("Passphrases don't match.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } header: {
                Text("Encryption")
            } footer: {
                if encryptBackup {
                    // Both halves are load-bearing: what the passphrase covers,
                    // and that losing it is final. A user who doesn't
                    // understand the second can lose everything.
                    Text("This passphrase encrypts the entire backup, including chats, files, and credentials. There is no way to recover a forgotten passphrase — the backup cannot be opened without it.")
                } else if selected.contains(where: Self.credentialCarryingCategories.contains) {
                    // [T-backup-credentials-without-encryption] This used to
                    // read "API keys are left out", which was the old
                    // behaviour. Now they are IN, so the footer has to say the
                    // opposite — and say it as a warning, because the risk has
                    // moved from "my backup is useless" to "my keys are
                    // readable by anyone holding this file".
                    Label("This backup contains your API keys, OAuth tokens and environment variable values, and it is NOT encrypted — anyone with the file can read them. Turn on encryption to protect it.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("Without encryption the backup is not protected — anyone with the file can read its contents.")
                }
            }

            Section {
                Label("Minis ▸ Backups", systemImage: "folder.fill")
            } header: {
                Text("Backup Folder")
            } footer: {
                Text("Start Backup creates this folder automatically and saves each backup here.")
            }

            if !embedded {
                Section {
                    NavigationLink {
                        BackupRestoreView()
                    } label: {
                        Label {
                            Text("Restore from Backup…")
                        } icon: {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(.white)
                                .frame(width: 21, height: 21)
                                .background(.indigo, in: Circle())
                        }
                    }
                } footer: {
                    Text("Restoring merges a backup into your existing data. Nothing is deleted.")
                }
            }

            Section {
                // ONE button that toggles. While a backup runs it says "Stop
                // Backup" and stops it — nothing else about this row changes.
                //
                // It used to do three things at once: the button turned into a
                // disabled spinner captioned with the live status, and a
                // SECOND Stop button appeared under it. That put the progress
                // report inside the control, so the row a user reaches for
                // moved and greyed out at the moment they wanted to act, and
                // the section grew a row every time a run started. Progress
                // belongs in the run's own entry in Backup History below,
                // which already shows the status text and the full log; the
                // control stays a control.
                Button(role: runController.isRunning ? .destructive : nil) {
                    if runController.isRunning {
                        BackupRunController.shared.stop()
                        return
                    }
                    // The Task is handed to the controller so Stop (here or
                    // in the run's detail view) can cancel it — a view can be
                    // dismissed mid-backup, and a running task nobody holds is
                    // one nobody can stop.
                    let t = Task { await runExport() }
                    BackupRunController.shared.started(task: t)
                } label: {
                    // [T-restore-primary-action] Badged like every other
                    // action row in the backup screens, and matching Start
                    // Restore on the other tab — a bare glyph here was the odd
                    // one out. Red while running, so Stop reads as the
                    // destructive action it is.
                    HStack(spacing: 10) {
                        BackupActionIcon(
                            systemName: runController.isRunning
                                ? "stop.fill" : "externaldrive.badge.timemachine",
                            tint: runController.isRunning ? .red : .blue)
                        Text(runController.isRunning ? "Stop Backup" : "Start Backup")
                    }
                    // Without maxWidth the row sizes to its content and sits
                    // left; this is what centres it in the Form row.
                    .frame(maxWidth: .infinity)
                    .fontWeight(.medium)
                }
                // The start-time requirements gate STARTING only. Applying
                // them while running would disable the button mid-run and
                // leave no way to stop the backup from this screen.
                .disabled(!runController.isRunning
                          && (selected.isEmpty || !passphraseValid))
                // List aligns a row's separator to its first Text's leading
                // edge. These rows centre their content, so the text starts
                // mid-row and the separator under "Exporting sessions…" only
                // spanned the middle of the card (user report: the divider
                // above Stop Backup looked broken). Pin it to the row's
                // leading edge so it runs the full card width.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

                // A disabled button with no explanation is a dead end — say
                // which requirement is unmet rather than leaving the user to
                // guess why nothing happens when they tap.
                if !isExporting {
                    // Same centred-row separator fix as the buttons above:
                    // without the guide these hint rows inherit a mid-card
                    // separator start.
                    if selected.isEmpty {
                        Text("Choose at least one thing to include.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    } else if encryptBackup && passphrase.isEmpty {
                        Text("Set a passphrase to encrypt this backup.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    } else if encryptBackup && passphrase != confirmPassphrase {
                        Text("Confirm the passphrase to continue.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                }

                if runController.isRunning {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(runController.statusText.isEmpty
                             ? AppLocalized("Working…") : runController.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            historySection

            if let result {
                Section {
                    LabeledContent("Size", value: byteText(result.totalBytes))
                    if let count = result.categories[BackupCategory.chats.rawValue]?.unreadableSessions, count > 0 {
                        Label(String(format: AppLocalized("Chat sessions with missing or invalid IDs left out of this backup: %d."), count),
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let count = result.categories[BackupCategory.chats.rawValue]?.unreadableMessages, count > 0 {
                        Label(String(format: AppLocalized("Unreadable chat messages left out of this backup: %d."), count),
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if result.skippedFiles > 0 {
                        // §3.4: a size-capped export has gaps, and the user is
                        // told here rather than discovering it at restore time.
                        // "too large" would be wrong when files were left out
                        // on purpose — nothing exceeded anything.
                        LabeledContent(maxFileSizeMB == Self.noFilesTag
                                       ? "Files not included"
                                       : "Excluded (too large)",
                                       value: "\(result.skippedFiles) file(s)")
                    }
                    if shareURL != nil {
                        Button {
                            showShare = true
                        } label: {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showSaveToFiles = true
                        } label: {
                            Label("Save to Files…", systemImage: "folder")
                        }
                    }
                } header: {
                    Text("Backup Ready")
                } footer: {
                    Text("Saved in Minis ▸ Backups. Use Save to Files to copy it to iCloud Drive, a connected server, or another cloud provider.")
                }
            }
        }
        .modifier(StandaloneTitle(title: AppLocalized("Backup"),
                                 active: !embedded))
        .onAppear { loadSelectedCategories() }
        .sheet(isPresented: $showShare) {
            if let shareURL {
                BackupShareSheet(url: shareURL)
            }
        }
        .sheet(isPresented: $showSaveToFiles) {
            if let shareURL {
                BackupDocumentExportPicker(url: shareURL)
            }
        }
        // [review S14] The `pendingPackage` sheet used to live here. It is now
        // mounted at the WindowGroup root (MinisApp.swift) so opening a
        // .minisbak from Files works from ANY screen — this view is the one
        // place the user is least likely to already be standing when they
        // migrate to a new device.
    }

    // MARK: - Validation

    private var passphraseValid: Bool {
        // Encryption is optional; when enabled, require a matching passphrase.
        guard encryptBackup else { return true }
        return !passphrase.isEmpty && passphrase == confirmPassphrase
    }

    private func binding(for category: BackupCategory) -> Binding<Bool> {
        Binding(
            get: { BackupCategory.includingAgentOwners(selected).contains(category) },
            set: { on in
                if on {
                    selected.insert(category)
                    if category.requiresEncryptedBackup { encryptBackup = true }
                }
                else {
                    selected.remove(category)
                    if category == .agents { selected.subtract([.chats, .providers, .environmentVariables]) }
                }
                selectedStore = selected.map(\.rawValue).sorted().joined(separator: ",")
            })
    }

    /// Restore the persisted Include selection. An empty store means the user
    /// never changed anything — keep the all-on default.
    func loadSelectedCategories() {
        guard !selectedStore.isEmpty else { return }
        let stored = Set(selectedStore.split(separator: ",")
            .compactMap { BackupCategory(rawValue: String($0)) })
        // Categories that exist on this build but aren't in the stored string
        // stay OFF only if the user turned them off; a brand-new category
        // (added in an upgrade) defaults ON by not being representable in the
        // old string — but we can't tell those apart, so prefer the user's
        // explicit selection as saved.
        if !stored.isEmpty { selected = stored }
        if selected.contains(where: \.requiresEncryptedBackup) { encryptBackup = true }
    }

    /// Whether this record is the interrupted run whose staging is still on
    /// disk, and so can actually be continued.
    ///
    /// There is at most one such run — the journal keeps a single marker — so
    /// this matches on `backupId` rather than offering Resume on every failed
    /// record. A run that failed for any other reason has nothing to resume,
    /// and a Resume that quietly started a fresh backup would be a lie.
    ///
    /// Not shown while a backup is running: starting a second one is refused,
    /// and offering the action anyway invites a tap that does nothing.
    private func isResumable(_ r: BackupHistory.Record) -> Bool {
        guard !runController.isRunning, r.status == .failed,
              !r.backupId.isEmpty,
              let marker = BackupExportJournal.interrupted(),
              marker.backupId == r.backupId
        else { return false }
        return BackupExportJournal.canResume(marker)
    }

    /// [T-backup-device-name-setting] Lets the user name this device, which is
    /// what the backup filename leads with and what the iCloud sync device
    /// list shows.
    ///
    /// This is not cosmetic. Since iOS 16 `UIDevice.current.name` returns the
    /// MODEL ("iPhone") unless the app holds the user-assigned-device-name
    /// entitlement, so two iPhones backing up to one shared folder produce the
    /// same device token and remain indistinguishable — exactly the problem
    /// putting the device in the filename was meant to solve. Typing a name
    /// solves it without an entitlement.
    private var deviceNameSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue, in: Circle())
                // The placeholder is the automatic name, so an untouched field
                // shows the user what will be used rather than sitting blank.
                TextField(DeviceIdentity.automaticName, text: $deviceNameDraft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { commitDeviceName() }
                    // Committed on every change, not only on submit: this
                    // screen is usually left by swiping back or by tapping
                    // Create Backup, neither of which fires onSubmit — and a
                    // name that silently failed to save would be worse than
                    // no field at all.
                    //
                    // Single-parameter `onChange`, because the deployment
                    // target is iOS 16 and the two-parameter overload is 17+.
                    .onChange(of: deviceNameDraft) { _ in commitDeviceName() }
            }
        } header: {
            Text("Device Name")
        } footer: {
            // Says what the name is FOR — the whole point is the filename —
            // and how to get back to the default, which an empty field does
            // not otherwise advertise.
            Text("Used to identify this device in backup filenames and in the iCloud sync device list. Leave empty to use “\(DeviceIdentity.automaticName)”.")
        }
        // Seeded in onAppear rather than defaulted, so reopening the screen
        // shows what is actually stored instead of an empty field over a set
        // name.
        .onAppear { deviceNameDraft = DeviceIdentity.customName ?? "" }
    }

    /// Persists the draft. Empty (or whitespace) clears the override and falls
    /// back to the automatic name — `DeviceIdentity.customName` trims and
    /// length-caps, so nothing unusable is stored.
    private func commitDeviceName() {
        DeviceIdentity.customName = deviceNameDraft
    }

    @ViewBuilder
    private var historySection: some View {
        if !history.records.isEmpty {
            Section {
                ForEach(history.records) { r in
                    NavigationLink {
                        BackupHistoryDetailView(record: r)
                    } label: {
                        BackupHistoryRow(record: r)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            BackupHistory.shared.remove(r.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        // Continuing an interrupted run is now an explicit act
                        // on the run itself, so the user can see WHICH backup
                        // they are continuing. Start Backup no longer adopts it
                        // silently — that produced a package pinned to the old
                        // run's snapshot, missing everything written since.
                        if isResumable(r) {
                            Button {
                                let t = Task { await runExport(resuming: true) }
                                BackupRunController.shared.started(task: t)
                            } label: {
                                Label("Resume", systemImage: "play.circle")
                            }
                            .tint(.blue)
                        }
                    }
                }
            } header: {
                Text("Backup History")
            } footer: {
                Text("Records from the past month. Older ones are removed automatically.")
            }
        }
    }

    // MARK: - Export

    /// - Parameter resuming: continue the interrupted run instead of starting a
    ///   new one. Only ever true from the Resume action on that run's history
    ///   row — Start Backup always means "back up the data as it is now".
    private func runExport(resuming: Bool = false) async {
        isExporting = true
        errorText = nil
        result = nil
        shareURL = nil
        defer { isExporting = false }

        let options = BackupExporter.Options(
            categories: selected,
            // nil = no cap; 0 = every file is over the cap, i.e. contents are
            // skipped and only tombstones are recorded.
            maxFileBytes: maxFileSizeMB == Self.unlimitedTag ? nil
                : maxFileSizeMB == Self.noFilesTag ? 0
                : Int64(maxFileSizeMB) * 1024 * 1024,
            // [T-backup-credentials-without-encryption] Credentials always
            // ship. They used to be tied to `encryptBackup`, so the default
            // (encryption off) produced a backup that restored providers with
            // no keys and environment variables with no values — the one thing
            // a backup exists to carry. secrets.json is still base64, i.e. an
            // encoding and not protection, so the cost of this is disclosed in
            // the encryption footer below rather than enforced by dropping the
            // user's data.
            includeCredentials: true,
            passphrase: encryptBackup && !passphrase.isEmpty ? passphrase : nil,
            allowResume: resuming)

        // Opened BEFORE the work starts, so a run that crashes mid-flight still
        // leaves a record — that is exactly the case a user needs to see.
        let runId = BackupHistory.shared.begin(
            backupId: "", categories: selected.map(\.rawValue).sorted(),
            encrypted: encryptBackup)
        // Attach the real record id to the task the caller already registered,
        // and make sure the running state clears on EVERY exit path —
        // including cancellation.
        BackupRunController.shared.attach(recordId: runId)
        // Token-guarded: a start that was REFUSED (because another backup is
        // already running) still reaches this defer, and an unguarded call
        // would tear down the state — and the keep-alive audio session — of the
        // run that is legitimately in flight.
        let token = BackupRunController.shared.currentToken
        defer { BackupRunController.shared.finished(token: token) }

        do {
            try FileManager.default.createDirectory(at: BackupDelivery.backupsDirectory,
                                                    withIntermediateDirectories: true)
            // [review I5] Hold a background assertion so switching apps
            // mid-export doesn't get the process suspended ~30s later.
            let summary = try await BackupBackgroundAssertion.run("BackupExport") {
                try await BackupExporter().export(options: options) { id in
                    // Ties this record to its staging tree, so an interrupted
                    // run can be identified and offered for Resume.
                    Task { @MainActor in
                        BackupHistory.shared.setBackupId(runId, id)
                    }
                } progressDetailed: { text, transient in
                    // `transient` is a live counter line ("120/400 · about 40s
                    // left"); the history log replaces the previous one instead
                    // of stacking a new row every second.
                    Task { @MainActor in
                        BackupRunController.shared.update(status: text)
                        BackupHistory.shared.log(runId, text, isTransient: transient)
                    }
                }
            }
            // Out of tmp/ before anything else: iOS can purge that directory,
            // and the share sheet may be dismissed and re-opened later.
            let stable = try BackupDelivery.moveToVisibleStorage(summary.packageURL)
            var savedSummary = summary
            savedSummary.packageURL = stable
            result = savedSummary
            shareURL = stable
            BackupHistory.shared.log(runId, AppLocalized("Saved in Minis ▸ Backups."))

            BackupHistory.shared.finish(
                runId,
                totalBytes: summary.totalBytes,
                skippedFiles: summary.skippedFiles,
                packageName: stable.lastPathComponent,
                destinations: [],
                // Turn each skipped path into something recognisable. Paths are
                // `chats/<sessionId>/…`, and the title map was captured during
                // the export so a conversation deleted later still resolves.
                skippedEntries: summary.skippedPaths.map { item in
                    let parts = item.path.split(separator: "/")
                    let sid = parts.count > 1 && parts[0] == "chats"
                        ? String(parts[1]) : nil
                    return .init(path: item.path, size: item.size,
                                 sessionTitle: sid.flatMap { summary.sessionTitles[$0] })
                })

            logger.info("[Backup] user export saved locally bytes=\(summary.totalBytes)")
        } catch is CancellationError {
            // The user pressed Stop. That is an ACTION they took, not a failure
            // that happened to them — reporting it in red as an error (with
            // Foundation's generic "operation couldn't be completed" text) says
            // something went wrong when nothing did.
            errorText = nil
            let resumable = BackupExportJournal.interrupted().map(BackupExportJournal.canResume) ?? false
            BackupHistory.shared.fail(runId, message: resumable
                ? AppLocalized("Stopped — the next backup picks up from here.")
                : AppLocalized("Stopped — the next backup starts over."))
            logger.info("[Backup] user export stopped by user")
        } catch {
            errorText = error.localizedDescription
            BackupHistory.shared.fail(runId, message: error.localizedDescription)
            logger.error("[Backup] user export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Display

    private func displayName(_ c: BackupCategory) -> String {
        c.localizedName
    }

    /// Glyph + colour per category, matching the iCloud Sync list's visual
    /// language (and reusing its choices where the categories correspond).


    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

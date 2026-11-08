import SwiftUI
import UniformTypeIdentifiers

private let logger = AppLogger(category: "Backup")

/// User-facing restore flow (docs/backup-restore-design.md §8.1).
///
/// Follows the documented order exactly: pick a package → read its manifest and
/// show a summary → choose categories → passphrase if encrypted → confirm →
/// import → report.
///
/// Only **Merge** is offered. Replace / Skip-existing are stage 5, and shipping
/// a mode picker with one option would imply choices that don't exist. What the
/// mode does is stated in the UI rather than left for the user to infer — the
/// task flagged the risk that "restore" reads as "overwrite", and Merge is the
/// opposite: nothing local is deleted, and a newer local copy wins.
struct BackupRestoreView: View {
    /// Optional package to open immediately — set when the flow is entered by
    /// opening a `.minisbak` file from Files rather than from this screen.
    var initialPackageURL: URL?
    /// True when hosted inside `BackupAndRestoreView`, which owns the title.
    var embedded = false

    @State private var packageURL: URL?
    /// A copy we own. A URL from the document picker is security-scoped and
    /// only valid inside a start/stopAccessing pair, so the file is copied into
    /// tmp/ once and everything afterwards reads from that copy.
    @State private var localCopyURL: URL?
    @State private var manifest: BackupManifest?
    @State private var selected: Set<BackupCategory> = []
    @State private var passphrase = ""

    @State private var showPicker = false
    @State private var localPackages: [LocalBackupStorage.Package] = []
    @State private var isLoadingBackups = false
    @ObservedObject private var history = BackupHistory.shared
    /// True between picking a package and its manifest being read. Drives the
    /// "Opening backup…" row; without it a slow share looks like a dead tap.
    @State private var isInspecting = false
    /// [T-restore-inspect-cancel] Rotating detail under "Opening backup…".
    @State private var inspectStage = ""
    /// The in-flight inspect, so Cancel can stop it.
    @State private var inspectTask: Task<Void, Never>?
    @State private var isWorking = false
    @State private var statusText = ""
    @FocusState private var passphraseFocused: Bool
    @State private var errorText: String?
    @State private var report: BackupImporter.Report?
    @State private var showConfirm = false

    var body: some View {
        Form {
            if report == nil {
                // Chosen package FIRST. Everything below is about finding one;
                // once found, what it is and the button that acts on it are
                // what the user came for, and burying them under the pickers
                // meant scrolling past the whole browse UI to reach Restore.
                if let manifest {
                    selectedPackageSection(manifest)
                    categorySection(manifest)
                    if manifest.encryption != nil { passphraseSection }
                    actionSection
                    // [T-restore-hide-pickers] Nothing else. Once a package is
                    // chosen the screen is about THAT package, and leaving the
                    // destination list and "Other Sources" below it invited a
                    // second pick that would silently replace the first — and
                    // pushed Start Restore up into the middle of the screen
                    // with browse UI underneath. The way back is the card's own
                    // "Choose a Different Backup", which is where someone who
                    // has changed their mind will look.
                } else if isInspecting {
                    // Also alone: an open in progress owns the screen, and its
                    // Cancel is the way out.
                    inspectingSection
                } else {
                    localBackupsSection
                    otherSourcesSection
                }
            } else if let report {
                reportSection(report)
                Section {
                    Button("Choose a Different Backup") { clearSelection() }
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .modifier(StandaloneTitle(title: AppLocalized("Restore"),
                                 active: !embedded))
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [BackupDelivery.contentType, .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { load(url) }
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
        // [T-restore-confirm-alert] An alert, not a confirmationDialog. On
        // iOS 26 a confirmation dialog presents as a POPOVER anchored to its
        // source view, which here is the whole restore screen, so the question
        // floated as a speech bubble over the middle of the category list,
        // pointing at an unrelated row. A centred alert is the right shape for
        // a single yes/no about the whole operation.
        .alert("Restore this backup?", isPresented: $showConfirm) {
            Button("Restore") { Task { await runImport() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items from the backup are merged into your existing data. Nothing is deleted, and anything you've changed more recently is kept.")
        }
        .task { await reloadBackups() }
        .refreshable { await reloadBackups() }
        .onChange(of: history.records.first?.finishedAt) { _ in
            Task { await reloadBackups() }
        }
        .onAppear {
            if let initialPackageURL, packageURL == nil { load(initialPackageURL) }
        }
    }

    // MARK: - Sections

    private var localBackupsSection: some View {
        Section {
            if isLoadingBackups {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading backups…")
                        .foregroundStyle(.secondary)
                }
            } else if localPackages.isEmpty {
                Text("No backups yet. Create a backup on the Backup tab, or import a backup file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(localPackages) { package in
                Button {
                    load(package.url)
                } label: {
                    HStack(spacing: 12) {
                        BackupActionIcon(systemName: "doc.zipper", tint: .blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(package.url.lastPathComponent)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .foregroundStyle(.primary)
                            Text("\(ByteCountFormatter.string(fromByteCount: package.size, countStyle: .file)) · \(package.modified.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Backup Folder")
        } footer: {
            Text("Choose a backup from Minis ▸ Backups to restore. Newest backups appear first.")
        }
    }

    private var otherSourcesSection: some View {
        Section {
            Button {
                showPicker = true
            } label: {
                Label {
                    Text("Choose from Files…")
                } icon: {
                    BackupActionIcon(systemName: "folder.fill", tint: .blue)
                }
            }
        } footer: {
            Text("To restore a backup from another device, choose its .minisbak file from Files.")
        }
    }

    private func reloadBackups() async {
        isLoadingBackups = true
        defer { isLoadingBackups = false }
        let directory = BackupDelivery.backupsDirectory
        do {
            localPackages = try await Task.detached(priority: .userInitiated) {
                try LocalBackupStorage(directory: directory).packages()
            }.value
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Shown while the picked package is being opened and its manifest read.
    ///
    /// Without it, tapping a package on a slow share left the screen looking
    /// unchanged for several seconds — the summary simply had not appeared
    /// yet — which reads as a tap that did nothing.
    /// Shown while the picked package is being opened and its manifest read.
    ///
    /// [T-restore-inspect-cancel] Opening a multi-GB package means unzipping
    /// it, which can run for a long time with nothing to show — a single
    /// static "Opening backup…" reads as a hung screen. Two additions:
    ///
    ///  - a rotating detail line, in a smaller face beneath the title, naming
    ///    the stage the open is actually at;
    ///  - a Cancel, because until now the only way out of a slow open was to
    ///    kill the app, and doing that leaves the scratch copy behind.
    private var inspectingSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Opening backup…")
                        .foregroundStyle(.secondary)
                    // Deliberately smaller and dimmer than the title: it is
                    // reassurance that work is happening, not information the
                    // user has to read.
                    Text(inspectStage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        // The stage text changes underneath a fixed layout, so
                        // the row must not resize as the wording changes.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeInOut(duration: 0.2), value: inspectStage)
                }
                Spacer(minLength: 8)
                Button {
                    cancelInspect()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .layoutPriority(1)
            }
        }
    }

    /// [T-restore-destinations-first] The chosen package, at the very top:
    /// what it is, how big, and how much is in it.
    ///
    /// The per-category breakdown below this is the detail; this is the
    /// answer to "is this the right file?", which is the question a user has
    /// immediately after picking one — especially when several packages in a
    /// folder differ only by date.
    private func selectedPackageSection(_ m: BackupManifest) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    BackupActionIcon(systemName: "doc.zipper", tint: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(packageURL?.lastPathComponent ?? AppLocalized("Backup"))
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text(packageHeadline(m))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LabeledContent("Created",
                           value: m.createdAt.formatted(date: .abbreviated, time: .shortened))
            // The data cut-off, when the package records one. Distinct from
            // "Created": anything changed after this instant is deliberately
            // not in the package, and the user should see that before
            // deciding this is the backup they want.
            if let snapshotAt = m.snapshotAt, snapshotAt != m.createdAt {
                LabeledContent("Data as of",
                               value: snapshotAt.formatted(date: .abbreviated, time: .shortened))
            }
            LabeledContent("From", value: "\(m.deviceName) · \(m.app.platform) \(m.app.version)")
            if m.encryption != nil {
                LabeledContent("Encrypted", value: AppLocalized("Yes"))
            }
            if let limits = m.limits.maxFileBytes, limits == 0 {
                // The package was made with file contents switched off, so it
                // can restore conversations but none of their attachments.
                // Saying "size limit" here would be misleading — nothing was
                // too big, the user chose to leave files out.
                LabeledContent("File contents",
                               value: "Not included (\(m.limits.skippedFiles) file(s) listed)")
            } else if let limits = m.limits.maxFileBytes, limits > 0 {
                // §3.4 — the package is known-incomplete, and the user should
                // learn that here rather than after restoring.
                LabeledContent("Excluded (size limit)",
                               value: "\(m.limits.skippedFiles) file(s)")
            }

            // Escape hatch, kept with the thing it replaces rather than in the
            // pickers below: having chosen the wrong package, "choose another"
            // is the next action, and it should be where the user is looking.
            Button {
                clearSelection()
            } label: {
                Label {
                    Text("Choose a Different Backup")
                } icon: {
                    BackupActionIcon(systemName: "arrow.triangle.2.circlepath", tint: .gray)
                }
            }
            .disabled(isWorking)
        } header: {
            Text("Selected Backup")
        }
    }

    /// One line of totals for the package: size, then what is in it.
    ///
    /// Summed from the manifest's per-category stats rather than measured off
    /// the file, so it describes the CONTENT (what would be restored) and not
    /// the archive's compressed size on disk — the number the user is trying
    /// to sanity-check is "does this look like my data".
    private func packageHeadline(_ m: BackupManifest) -> String {
        let bytes = m.categories.values.reduce(Int64(0)) { $0 + $1.bytes }
        var bits = [ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)]
        bits.append(countLabel(m.categories.count,
                               one: AppLocalized("1 category"),
                               many: AppLocalized("%d categories")))
        let items = m.categories.values.reduce(0) { $0 + $1.entries }
        if items > 0 {
            bits.append(countLabel(items,
                                   one: AppLocalized("1 item"),
                                   many: AppLocalized("%d items")))
        }
        return bits.joined(separator: " · ")
    }

    /// [T-restore-inspect-cancel] Stage wording for the open. Not measured
    /// progress — `inspect` unzips in one synchronous call and reports nothing
    /// — so these describe what it is doing rather than how far along it is,
    /// and the last one is held once reached instead of looping back to the
    /// start, which would suggest the work had restarted.
    static let inspectStages: [String] = [
        AppLocalized("Reading the package…"),
        AppLocalized("Expanding files…"),
        AppLocalized("Checking contents…"),
        AppLocalized("Almost there…"),
    ]

    /// Abandon an open that is taking too long, and leave nothing behind.
    private func cancelInspect() {
        inspectTask?.cancel()
        inspectTask = nil
        resetSelection()
    }

    /// Drop the chosen package and go back to the pickers.
    private func clearSelection() {
        resetSelection()
        Task { await reloadBackups() }
    }

    /// [T-restore-reset-state] The ONE place selection state is torn down, so
    /// Cancel and "Choose a Different Backup" cannot clear different subsets
    /// and leave the screen wedged.
    ///
    /// Every field set while a package is selected is cleared here, including
    /// `isInspecting` and `report`: leaving `isInspecting` true would keep the
    /// spinner row on screen with no task behind it, and a stale `report`
    /// would hide the pickers entirely — both states the user cannot get out
    /// of without leaving the screen.
    private func resetSelection() {
        // Cancel first: a running open would otherwise finish and write its
        // manifest into the state we are about to clear, re-selecting a
        // package the user just dismissed.
        inspectTask?.cancel()
        inspectTask = nil

        // The local copy is ours and can be gigabytes; leaving it in tmp/ for
        // iOS to purge "eventually" is how the sweeper's whole class of bug
        // starts. BackupExportJournal.sweep() would catch it on next launch,
        // but there is no reason to wait.
        if let localCopyURL { try? FileManager.default.removeItem(at: localCopyURL) }
        // Remove the enclosing scratch directory too when the copy came from a
        // server download, for the same reason as `discardScratch`.
        if let packageURL,
           packageURL.path.hasPrefix(FileManager.default.temporaryDirectory.path),
           packageURL.deletingLastPathComponent().lastPathComponent.hasPrefix("server-restore-") {
            try? FileManager.default.removeItem(at: packageURL.deletingLastPathComponent())
        }

        packageURL = nil
        localCopyURL = nil
        manifest = nil
        selected = []
        passphrase = ""
        errorText = nil
        isInspecting = false
        inspectStage = ""
        report = nil
        statusText = ""
    }

    private func categorySection(_ m: BackupManifest) -> some View {
        Section {
            ForEach(availableCategories(m), id: \.self) { category in
                Toggle(isOn: binding(for: category)) {
                    // Same badge as the Backup tab, so a category is
                    // recognisable across both screens rather than only by
                    // its wording.
                    HStack(spacing: 12) {
                        BackupCategoryIcon(category: category)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName(category))
                            if let stat = m.categories[category.rawValue] {
                                Text(detailText(category, stat))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if category == .chats, let count = stat.unreadableSessions, count > 0 {
                                    Text(String(format: AppLocalized("Chat sessions with missing or invalid IDs left out of this backup: %d."), count))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                if category == .chats, let count = stat.unreadableMessages, count > 0 {
                                    Text(String(format: AppLocalized("Unreadable chat messages left out of this backup: %d."), count))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Restore")
        } footer: {
            Text("Restore matches stable IDs. Existing agent settings are kept. Newer memories are merged. Chats, providers and environment variables also restore agent ownership.")
        }
    }

    private var passphraseSection: some View {
        Section {
            // [T-restore-lock-passphrase] Locked while the restore runs: the
            // passphrase is already in use, and a focused field kept raising
            // the keyboard over the progress line.
            SecureField("Passphrase", text: $passphrase)
                .textContentType(.password)
                .focused($passphraseFocused)
                .disabled(isWorking)
        } header: {
            Text("Encryption")
        } footer: {
            Text("This backup is encrypted. Without its passphrase it cannot be opened.")
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                // [T-restore-lock-passphrase] Put the keyboard away before the
                // confirmation, so it is not left up for the whole restore.
                passphraseFocused = false
                showConfirm = true
            } label: {
                // [T-restore-primary-action] Centred icon + label, matching
                // Start Backup on the other tab. This is the screen's primary
                // action and was a left-aligned "Restore" that read like one
                // more row in the list rather than the thing to press.
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if isWorking {
                        ProgressView()
                            .frame(width: 28, height: 28)
                        Text(statusText.isEmpty ? AppLocalized("Working…") : statusText)
                            .foregroundStyle(.secondary)
                    } else {
                        BackupActionIcon(systemName: "arrow.down.doc.fill", tint: .indigo)
                        Text("Start Restore")
                            .fontWeight(.semibold)
                    }
                    Spacer(minLength: 0)
                }
            }
            .disabled(isWorking || selected.isEmpty || !passphraseReady)
        }
    }

    /// [T-restore-result-severity] The "warning, not failure" row style.
    ///
    /// The ⚠️ is an `Image`, deliberately NOT a character inside the string:
    /// each of these lines is a localized key with 17-18 translations, and
    /// prefixing the key would orphan every one of them and drop all locales
    /// back to English. Taking a `Text` (not a `String`) keeps the call site's
    /// literal a `LocalizedStringKey`.
    private func restoreNotice(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private func reportSection(_ r: BackupImporter.Report) -> some View {
        Section {
            ForEach(Array(r.warnings.enumerated()), id: \.offset) { _, warning in
                restoreNotice(Text(warning))
            }
            LabeledContent("Restored", value: "\(r.totalImported)")
            if r.totalUpdated > 0 { LabeledContent("Updated", value: "\(r.totalUpdated)") }
            // "Skipped" is the expected outcome for anything already present,
            // so it is labelled as such rather than looking like a failure.
            LabeledContent("Kept Existing", value: "\(r.totalSkipped)")
            if r.totalUnreadable > 0 {
                LabeledContent("Unreadable", value: "\(r.totalUnreadable)")
            }
            let credsRestored = r.categories.reduce(0) { $0 + $1.credentialsRestored }
            if credsRestored > 0 {
                LabeledContent("API keys restored", value: "\(credsRestored)")
            }
            // [T-restore-result-severity] Two tiers, told apart by colour AND
            // icon so the difference survives for colour-blind users:
            //   • red, no icon  — the category's restore actually FAILED;
            //   • orange + ⚠️   — the restore succeeded, but some files were
            //     not in the package to begin with.
            // Every "not in the package" line used to be red or grey, and red
            // read as a crash or corruption to users whose restore had in fact
            // gone fine.
            ForEach(r.categories, id: \.category) { c in
                if let failed = c.failed {
                    Text("\(displayNameRaw(c.category)): \(failed)")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    // Was `.secondary`, which made a real gap look like fine print.
                    if c.sizeSkippedInPackage > 0 {
                        restoreNotice(Text("\(displayNameRaw(c.category)): \(c.sizeSkippedInPackage) file(s) weren't in the backup (size limit)"))
                    }
                    // [review S9] Different remedy from the size cap, so it gets
                    // its own line rather than being folded into "skipped":
                    // these files exist, they just weren't on the device that
                    // made the backup.
                    if c.notDownloadedInPackage > 0 {
                        restoreNotice(Text("\(displayNameRaw(c.category)): \(c.notDownloadedInPackage) file(s) weren't in the backup (not downloaded from iCloud on the source device)"))
                    }
                    // [review S7] The package's own index referenced content it
                    // did not contain (the export is not a snapshot, so a file
                    // written between the index pass and the blob copy can be
                    // listed but not stored). Still always surfaced — that is
                    // what S7 fixed, since it used to be swallowed as a clean
                    // success — but as a warning, not a failure, per product
                    // decision: the restore itself worked, and the old
                    // "— the backup is incomplete" wording in red read as
                    // corruption. Note this is a genuine gap in THAT backup,
                    // not a policy skip: tombstones (size cap, not downloaded,
                    // unreadable) are filtered out before this is counted.
                    if c.missingBlobs > 0 {
                        restoreNotice(Text("\(displayNameRaw(c.category)): \(c.missingBlobs) file(s) were listed in the backup but missing from it"))
                    }
                }
            }
            if !r.rolledBack.isEmpty {
                restoreNotice(Text("Rolled back: \(r.rolledBack.joined(separator: ", "))"))
            }
        } header: {
            Text("Restore Complete")
        } footer: {
            if let prov = r.categories.first(where: { $0.category == BackupCategory.providers.rawValue }) {
                if prov.credentialsRestored > 0 {
                    // Credentials now always travel with Providers, so this is
                    // the normal outcome rather than a bonus.
                    Text("API keys were restored for \(prov.credentialsRestored) provider(s) along with their settings. Existing keys on this device were kept. OAuth logins may still need to be renewed if their tokens have expired.")
                } else if prov.credentialsKept > 0 {
                    // [T-backup-credentials-message-inverted] Nothing was
                    // WRITTEN, but only because every key in the package is
                    // already on this device — `credentialsRestored` counts
                    // keys actually written (BackupSecretsImporter increments
                    // it only `if wrote`), while an existing key increments
                    // `providersSkippedExisting` instead.
                    //
                    // This is the normal outcome when restoring onto the device
                    // that made the backup, and it used to fall into the branch
                    // below — telling the user "this backup was created without
                    // API keys… enter each API key again" on a fully
                    // credentialed device, which is exactly backwards.
                    // `credentialsKept` was already being computed for this and
                    // simply never read by any view.
                    Text("Your existing API keys were kept — the backup's keys matched credentials already on this device, so nothing needed to be overwritten.")
                } else {
                    // Reachable for OLDER packages: exports used to offer a
                    // credential-free "share copy", and those must keep
                    // restoring. Says why nothing arrived instead of implying
                    // the restore misbehaved.
                    Text("This backup was created without API keys, so restored providers have no credentials — enter each API key or sign in again before use.")
                }
            }
        }
    }

    // MARK: - Actions

    private func load(_ url: URL) {
        resetSelection()
        packageURL = url
        isInspecting = true
        inspectStage = Self.inspectStages.first ?? ""

        // Start progress before preparing a potentially multi-GB file.
        // The task owns its scratch until preparation and inspection finish,
        // so Cancel cannot delete a file while the background copy writes it.
        inspectTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("restore-\(UUID().uuidString).\(BackupFormat.fileExtension)")
            let ticker = Task { @MainActor in
                var i = 0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    guard !Task.isCancelled else { break }
                    i += 1
                    inspectStage = Self.inspectStages[min(i, Self.inspectStages.count - 1)]
                }
            }
            defer { ticker.cancel() }
            await withTaskCancellationHandler {
                do {
                    try Task.checkCancellation()
                    try await Task.detached(priority: .userInitiated) {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        if MountedFolderCoordinator.isUnderMount(url) {
                            try MountedFolderCoordinator.copy(from: url, to: dest)
                        } else {
                            try FileManager.default.copyItem(at: url, to: dest)
                        }
                    }.value
                    try Task.checkCancellation()
                    let m = try await BackupImporter().inspect(packageURL: dest)
                    try Task.checkCancellation()
                    localCopyURL = dest
                    manifest = m
                    isInspecting = false
                    inspectStage = ""
                    selected = Set(m.categories.keys.compactMap(BackupCategory.init(rawValue:)))
                } catch {
                    try? FileManager.default.removeItem(at: dest)
                    guard !Task.isCancelled else { return }
                    errorText = error.localizedDescription
                    packageURL = nil
                    isInspecting = false
                    inspectStage = ""
                }
            } onCancel: {
                ticker.cancel()
            }
        }
    }

    private func runImport() async {
        guard let localCopyURL else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }

        var options = BackupImporter.Options()
        options.categories = selected
        options.passphrase = passphrase.isEmpty ? nil : passphrase

        do {
            // [review I5] Same protection for restore — being suspended
            // part-way through writing user data is the worse of the two.
            let r = try await BackupBackgroundAssertion.run("BackupRestore") {
                try await BackupImporter().import(from: localCopyURL, options: options) { text in
                    Task { @MainActor in statusText = text }
                }
            }
            report = r
            statusText = ""
            logger.info("[Restore] user restore complete imported=\(r.totalImported) skipped=\(r.totalSkipped)")
        } catch {
            errorText = error.localizedDescription
            logger.error("[Restore] user restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private var passphraseReady: Bool {
        manifest?.encryption == nil || !passphrase.isEmpty
    }

    private func availableCategories(_ m: BackupManifest) -> [BackupCategory] {
        BackupCategory.allCases.filter { m.categories[$0.rawValue] != nil }
    }

    private func binding(for category: BackupCategory) -> Binding<Bool> {
        Binding(
            get: { BackupCategory.includingAgentOwners(selected).contains(category) },
            set: { on in
                if on { selected.insert(category) }
                else {
                    selected.remove(category)
                    if category == .agents { selected.subtract([.chats, .providers, .environmentVariables]) }
                }
            })
    }

    /// Singular/plural for a counted noun. Kept explicit rather than using a
    /// String Catalog plural rule because these keys are added by
    /// `scripts/add_localization.py`, which writes simple key/value entries —
    /// a `.stringsdict`-style variation would have to be hand-edited into the
    /// catalog and would not survive the next scripted addition.
    private func countLabel(_ n: Int, one: @autoclosure () -> String,
                            many: @autoclosure () -> String) -> String {
        n == 1 ? one() : String(format: many(), n)
    }

    /// [T-backup-category-counts] Say what the number actually counts. Every
    /// branch below falls back to the generic "items" line when the package
    /// predates the field it needs, so an old backup still renders sensibly.
    private func detailText(_ c: BackupCategory, _ stat: BackupManifest.CategoryStat) -> String {
        let size = ByteCountFormatter.string(fromByteCount: stat.bytes, countStyle: .file)
        switch c {
        case .browserCookies:
            return "\(stat.entries) · \(size) · " + AppLocalized("May restore website sign-ins")
        case .chats:
            // [T-restore-progress-localized] Counted through countLabel like
            // every other category; this line was a bare English literal.
            if let messages = stat.messages, let files = stat.files {
                let m = countLabel(messages,
                                   one: AppLocalized("1 message"),
                                   many: AppLocalized("%d messages"))
                let f = countLabel(files,
                                   one: AppLocalized("1 file"),
                                   many: AppLocalized("%d files"))
                return "\(m) · \(f) · \(size)"
            }
        case .skills:
            let skills = countLabel(stat.entries,
                                    one: AppLocalized("1 skill"),
                                    many: AppLocalized("%d skills"))
            if let files = stat.files {
                let f = countLabel(files,
                                   one: AppLocalized("1 file"),
                                   many: AppLocalized("%d files"))
                return "\(skills) · \(f) · \(size)"
            }
            return "\(skills) · \(size)"
        case .mcpServers:
            let servers = countLabel(stat.entries,
                                     one: AppLocalized("1 server"),
                                     many: AppLocalized("%d servers"))
            return "\(servers) · \(size)"
        case .providers:
            let providers = countLabel(stat.entries,
                                       one: AppLocalized("1 provider"),
                                       many: AppLocalized("%d providers"))
            if let rules = stat.thinkingRules, rules > 0 {
                let r = countLabel(rules,
                                   one: AppLocalized("1 thinking rule"),
                                   many: AppLocalized("%d thinking rules"))
                return "\(providers) · \(r) · \(size)"
            }
            return "\(providers) · \(size)"
        default:
            break
        }
        let items = countLabel(stat.entries,
                               one: AppLocalized("1 item"),
                               many: AppLocalized("%d items"))
        return "\(items) · \(size)"
    }

    private func displayName(_ c: BackupCategory) -> String {
        c.localizedName
    }

    private func displayNameRaw(_ raw: String) -> String {
        BackupCategory(rawValue: raw).map(displayName) ?? raw
    }
}

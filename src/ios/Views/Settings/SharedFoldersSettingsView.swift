//
//  SharedFoldersSettingsView.swift
//  MinisApp
//
//  Settings screen that lists the three FileProvider-exposed shared directories
//  (shared, skills, Backups), lets the user tap each row to manage its contents,
//  and toggles whether each one is visible in the iOS Files app under
//  "On My iPhone → Minis".
//

import SwiftUI
import FileProvider

struct SharedFoldersSettingsView: View {
    @StateObject private var model = SharedFoldersViewModel()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Shared folders", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                    Text("These directories appear in iOS Files under On My iPhone → Minis. Tap a row to see details, browse, or toggle visibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(AppLocalized("Folders")) {
                ForEach(model.entries) { entry in
                    NavigationLink {
                        if entry.name == BackupDelivery.backupsDirectoryName {
                            LocalBackupFolderView()
                        } else {
                            MountDetailView(
                                context: detailContext(for: entry),
                                onDismiss: { model.refresh() }
                            )
                        }
                    } label: {
                        SharedFolderRow(
                            entry: entry,
                            isVisible: model.isVisible(entry.name)
                        )
                    }
                }
            }
        }
        .navigationTitle("Shared Folders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refresh() }
    }

    private func detailContext(for entry: SharedFolderEntry) -> MountDetailContext {
        MountDetailContext(
            kind: .shared,
            linuxPath: entry.pathLabel,
            sourceDisplayName: nil,
            hostURL: entry.hostURL,
            iconName: entry.iconName,
            iconColor: entry.iconColor,
            subtitle: nil,
            initialName: entry.displayName,
            canRename: false,
            externalMountId: nil,
            isOSWritable: entry.isWritableFromFiles,
            initialUserAllowWrite: true,
            sharedFolderName: entry.name,
            initialVisibleInFiles: model.isVisible(entry.name),
            isReadOnlyFromFiles: !entry.isWritableFromFiles
        )
    }
}

// MARK: - Row

private struct SharedFolderRow: View {
    let entry: SharedFolderEntry
    let isVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.iconName)
                .font(.system(size: 9))
                .foregroundStyle(.white)
                .frame(width: 21, height: 21)
                .background(entry.iconColor, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.body)
                    accessBadge
                    if !isVisible {
                        Text("Hidden")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                Text(entry.pathLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    /// Small pill showing whether Files app access is read/write or read-only.
    @ViewBuilder
    private var accessBadge: some View {
        if entry.isWritableFromFiles {
            Text("R/W")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().strokeBorder(Color.green.opacity(0.5), lineWidth: 1)
                )
        } else {
            Text("Read-only")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().strokeBorder(Color.orange.opacity(0.5), lineWidth: 1)
                )
        }
    }
}

// MARK: - Model

struct SharedFolderEntry: Identifiable, Hashable {
    /// UserDefaults key / FileProvider subdir name ("shared", "skills", "Backups").
    let name: String
    let displayName: String
    /// User-facing location. Only agent folders have a Linux path.
    let pathLabel: String
    /// Host filesystem URL (App Group container) for FileBrowserView.
    let hostURL: URL
    let iconName: String
    let iconColor: Color
    /// Whether the Files app (via FileProvider extension) can write to this
    /// folder. `skills` is read-only from Files; `shared` and `Backups` are r/w.
    /// Note: the MinisApp itself always reads/writes all three — this flag only
    /// describes the Files-app-facing surface.
    let isWritableFromFiles: Bool

    var id: String { name }
}

@MainActor
final class SharedFoldersViewModel: ObservableObject {
    @Published private(set) var entries: [SharedFolderEntry]
    @Published private var visibilityState: [String: Bool]

    init() {
        self.entries = Self.buildEntries()
        var state: [String: Bool] = [:]
        for name in SharedFolderVisibility.allFolderNames {
            state[name] = SharedFolderVisibility.isVisible(name)
        }
        self.visibilityState = state
    }

    func isVisible(_ name: String) -> Bool {
        visibilityState[name] ?? true
    }

    func setVisible(_ name: String, to visible: Bool) {
        visibilityState[name] = visible
        SharedFolderVisibility.setVisible(name, to: visible)
        // Signal the FileProvider to re-enumerate so iOS Files reflects the
        // change. This is best-effort — iOS Files may take a moment to refresh.
        SharedFoldersViewModel.signalFileProvider(.rootContainer)
    }

    /// Re-read visibility state from the underlying UserDefaults store. Called
    /// by the detail view's onDismiss so the parent list updates after a save.
    func refresh() {
        var state: [String: Bool] = [:]
        for name in SharedFolderVisibility.allFolderNames {
            state[name] = SharedFolderVisibility.isVisible(name)
        }
        self.visibilityState = state
    }

    private static func buildEntries() -> [SharedFolderEntry] {
        let root = AIChatViewModel.minisAppGroupRoot
        return [
            SharedFolderEntry(
                name: "shared",
                displayName: AppLocalized("Shared"),
                pathLabel: "/var/minis/shared",
                hostURL: root.appendingPathComponent("shared", isDirectory: true),
                iconName: "folder.fill",
                iconColor: .blue,
                isWritableFromFiles: true
            ),
            SharedFolderEntry(
                name: "skills",
                displayName: AppLocalized("Skills"),
                pathLabel: "/var/minis/skills",
                hostURL: root.appendingPathComponent("skills", isDirectory: true),
                iconName: "sparkles",
                iconColor: .purple,
                isWritableFromFiles: false
            ),
            SharedFolderEntry(
                name: BackupDelivery.backupsDirectoryName,
                displayName: AppLocalized("Backup Folder"),
                pathLabel: "Minis/Backups",
                hostURL: BackupDelivery.backupsDirectory,
                iconName: "archivebox.fill",
                iconColor: .orange,
                isWritableFromFiles: true
            ),
        ]
    }

    fileprivate static func signalFileProvider(_ itemIdentifier: NSFileProviderItemIdentifier) {
        let domainIdentifier = NSFileProviderDomainIdentifier("com.fogharbor544.minis.files")
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, _ in
            guard let domain = domains.first(where: { $0.identifier == domainIdentifier }) else {
                return
            }
            NSFileProviderManager(for: domain)?.signalEnumerator(for: itemIdentifier) { _ in }
        }
    }
}

/// Manages completed local packages without exposing backups to agent tools.
private struct LocalBackupFolderView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var history = BackupHistory.shared
    @State private var packages: [LocalBackupStorage.Package] = []
    @State private var isLoading = false
    @State private var isDeleting = false
    @State private var pendingDelete: LocalBackupStorage.Package?
    @State private var sharingPackage: LocalBackupStorage.Package?
    @State private var errorText: String?
    @State private var visibleInFiles = SharedFolderVisibility.isVisible(BackupDelivery.backupsDirectoryName)

    var body: some View {
        List {
            Section {
                Toggle("Show in Files app", isOn: $visibleInFiles)
                NavigationLink("Backup & Restore") {
                    BackupAndRestoreView()
                }
            } footer: {
                Text("Manage local backups in Minis/Backups. Tap a backup to review it for restore, or use its menu to share or delete it.")
            }

            Section {
                if isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading backups…").foregroundStyle(.secondary)
                    }
                } else if packages.isEmpty {
                    Text("No local backups yet. Create a backup in Backup & Restore.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(packages) { package in
                    HStack(spacing: 8) {
                        NavigationLink {
                            BackupRestoreView(initialPackageURL: package.url)
                        } label: {
                            HStack(spacing: 12) {
                                SettingsActionIcon(systemImage: "doc.zipper", color: .orange)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(package.url.lastPathComponent)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                    Text(ByteCountFormatter.string(fromByteCount: package.size, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(package.modified.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Menu {
                            Button {
                                sharingPackage = package
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                pendingDelete = package
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Backup actions for \(package.url.lastPathComponent)"))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = package
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Backup Folder")
            }
            .disabled(isDeleting || isLoading)

            if isDeleting {
                Section {
                    ProgressView("Deleting backup…")
                }
            }
        }
        .navigationTitle("Backup Folder")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await reload() } }
        }
        .onChange(of: history.records.first?.finishedAt) { _ in
            Task { await reload() }
        }
        .onChange(of: visibleInFiles) { visible in
            SharedFolderVisibility.setVisible(BackupDelivery.backupsDirectoryName, to: visible)
            SharedFoldersViewModel.signalFileProvider(.rootContainer)
        }
        .sheet(item: $sharingPackage) { package in
            BackupShareSheet(url: package.url)
        }
        .alert("Delete this backup file?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            if let package = pendingDelete {
                Button("Delete", role: .destructive) {
                    Task { await delete(package) }
                }
                .disabled(isDeleting || isLoading)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let package = pendingDelete {
                Text("“\(package.url.lastPathComponent)” will be permanently deleted from this device. This cannot be undone. Your current chats and memories, backup history, and copies on other destinations are kept.")
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func reload() async {
        guard !isLoading, !isDeleting else { return }
        isLoading = true
        defer { isLoading = false }
        let directory = BackupDelivery.backupsDirectory
        do {
            packages = try await Task.detached(priority: .utility) {
                try LocalBackupStorage(directory: directory).packages()
            }.value
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(_ package: LocalBackupStorage.Package) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        let directory = BackupDelivery.backupsDirectory
        do {
            try await Task.detached(priority: .utility) {
                try LocalBackupStorage(directory: directory).delete(package.url)
            }.value
            packages.removeAll { $0.id == package.id }
            SharedFoldersViewModel.signalFileProvider(NSFileProviderItemIdentifier(BackupDelivery.backupsDirectoryName))
        } catch {
            errorText = error.localizedDescription
        }
    }
}

import SwiftUI

struct CloudSyncSettingsV2View: View {
    @State private var v2Enabled: Bool = false
    @State private var deviceName: String = ""
    @State private var deviceNameDraft: String = ""
    @State private var showDeviceNameEditor: Bool = false
    @State private var categoriesEnabled: [UploadPolicy.Category: Bool] = [:]
    @State private var maxFileSizeMB: Int = 1
    @State private var remoteDevices: [SyncDevice] = []
    @State private var statusText: String = ""
    private static let refreshIntervalSeconds: UInt64 = 5

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { v2Enabled },
                    set: { newValue in
                        if #available(iOS 17.0, *) { SyncV2Bootstrap.setEnabled(newValue) }
                        v2Enabled = newValue
                    }
                )) {
                    Text("Enable iCloud Sync")
                }
                if !statusText.isEmpty {
                    NavigationLink {
                        SyncStatusView()
                    } label: {
                        LabeledContent("Status") {
                            Text(statusText).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Toggle takes effect on next app launch.")
                    .font(.caption)
            }

            if v2Enabled {
                Section {
                    Button {
                        deviceNameDraft = deviceName
                        showDeviceNameEditor = true
                    } label: {
                        LabeledContent("Name") {
                            HStack(spacing: 6) {
                                Text(deviceName).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Upload (This Device)")
                } footer: {
                    Text("This device name is broadcast to your other devices in the iCloud Sync zone.")
                        .font(.caption)
                }

                Section {
                    ForEach(UploadPolicy.Category.allCases, id: \.self) { cat in
                        Toggle(isOn: Binding(
                            get: { categoriesEnabled[cat] ?? true },
                            set: { newVal in
                                UploadPolicy.setEnabled(cat, newVal)
                                categoriesEnabled[cat] = newVal
                                Task { await markDeviceDirty() }
                            }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: iconName(for: cat))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(iconColor(for: cat), in: RoundedRectangle(cornerRadius: 7))
                                Text(LocalizedStringKey(cat.displayName))
                            }
                        }
                    }
                    if categoriesEnabled[.sessionFiles] ?? true {
                        Picker(selection: $maxFileSizeMB) {
                            Text("256 KB").tag(0)
                            Text("1 MB").tag(1)
                            Text("4 MB").tag(4)
                            Text("16 MB").tag(16)
                            Text("64 MB").tag(64)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.zipper")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.gray, in: RoundedRectangle(cornerRadius: 7))
                                Text("Max Per-File Size")
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: maxFileSizeMB) { newValue in
                            UploadPolicy.maxFileSizeBytes = newValue == 0 ? 256 * 1024 : newValue * 1024 * 1024
                        }
                    }
                } footer: {
                    Text("Choose which data this device pushes to iCloud. API keys and secrets are synced securely via iCloud Keychain.")
                        .font(.caption)
                }

                Section {
                    if remoteDevices.isEmpty {
                        Text("No other devices found yet. Devices appear here once they enable iCloud Sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(remoteDevices, id: \.id) { d in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(d.deviceName).font(.body)
                                    Spacer()
                                    Text(relativeDate(d.lastSeen)).font(.caption2).foregroundStyle(.secondary)
                                }
                                if !d.uploadTypes.isEmpty {
                                    Text(uploadTypesSummary(d.uploadTypes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Other Devices")
                } footer: {
                    Text("Devices that are signed in to the same iCloud account and have sync enabled. Last seen reflects the most recent push from that device.")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("iCloud Sync")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task { await refreshLoop() }
        .alert("Device Name", isPresented: $showDeviceNameEditor) {
            TextField("Device name", text: $deviceNameDraft)
            Button("Save") {
                let trimmed = deviceNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    UploadPolicy.customDeviceName = nil
                    deviceName = DeviceIdentity.deviceName
                } else {
                    UploadPolicy.customDeviceName = trimmed
                    deviceName = trimmed
                }
                Task { await markDeviceDirty() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Friendly name shown to your other Minis devices.")
        }
    }

    @MainActor
    private func refreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: Self.refreshIntervalSeconds * 1_000_000_000)
            } catch {
                return  // cancelled during sleep
            }
            let backgrounded: Bool
            if #available(iOS 17.0, *) {
                backgrounded = SyncCore.shared.isAppInBackground
            } else {
                backgrounded = false
            }
            if !backgrounded {
                await refresh()
            }
        }
    }

    @MainActor
    private func refresh() async {
        if #available(iOS 17.0, *) {
            v2Enabled = SyncV2Bootstrap.isEnabled
        }
        deviceName = UploadPolicy.customDeviceName ?? DeviceIdentity.deviceName
        for cat in UploadPolicy.Category.allCases {
            categoriesEnabled[cat] = UploadPolicy.isEnabled(cat)
        }
        let bytes = UploadPolicy.maxFileSizeBytes
        maxFileSizeMB = bytes < 1024 * 1024 ? 0 : Int((Double(bytes) / (1024 * 1024)).rounded())
        let me = DeviceIdentity.deviceId
        let all = await ChatStore.shared.listSyncDevices()
        remoteDevices = all.filter { $0.id != me }.sorted { $0.lastSeen > $1.lastSeen }
        if #available(iOS 17.0, *), v2Enabled {
            statusText = SyncCore.shared.isRunning ? "Running" : "Starting"
        } else {
            statusText = "Off"
        }
    }

    /// Whenever the user changes their upload preferences or device
    /// name, re-broadcast our SyncDeviceV2 record so peers learn about
    /// the new state.
    private func markDeviceDirty() async {
        await ChatStore.shared.markDirty(
            recordType: "SyncDeviceV2",
            recordId: DeviceIdentity.deviceId
        )
        if #available(iOS 17.0, *) {
            SyncCore.shared.scheduleSend(delay: 1)
        }
    }

    private func iconName(for cat: UploadPolicy.Category) -> String {
        switch cat {
        case .chatSessions: return "bubble.left.and.bubble.right.fill"
        case .sessionFiles: return "doc.fill"
        case .skills:       return "puzzlepiece.fill"
        case .providers:    return "link"
        case .envVars:      return "rectangle.stack.fill"
        case .memory:       return "brain.head.profile"
        }
    }

    private func iconColor(for cat: UploadPolicy.Category) -> Color {
        switch cat {
        case .chatSessions: return .blue
        case .sessionFiles: return .indigo
        case .skills:       return .orange
        case .providers:    return .teal
        case .envVars:      return .green
        case .memory:       return .pink
        }
    }

    private func uploadTypesSummary(_ csv: [String]) -> String {
        guard !csv.isEmpty else { return AppLocalized("No categories enabled") }
        return csv.joined(separator: " · ")
    }

    private func relativeDate(_ d: Date) -> String {
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return AppLocalized("Just now") }
        let mins = secs / 60
        if mins < 60 { return AppLocalized("\(mins) min ago") }
        let hrs = mins / 60
        if hrs < 24 { return AppLocalized("\(hrs) hr ago") }
        let days = hrs / 24
        return AppLocalized("\(days) day ago")
    }
}

import SwiftUI

struct OffloadPermissionSettingsView: View {
    @ObservedObject private var configGate = MinisConfigPermissionStore.shared
    @ObservedObject private var correctionConsent = VoiceCorrectionCollectionConsent.shared
    @State private var showClearCorrectionConfirm = false
    @State private var correctionDataCleared = false

    var body: some View {
        List {
            Section("Background") {
                NavigationLink {
                    EnhancedBackgroundSettingsView()
                } label: {
                    Label("Background", systemImage: "location.circle.fill")
                }
            }

            Section {
                Toggle("Allow minis-config", isOn: $configGate.enabled)
            } header: {
                Text("Configuration Tool")
            } footer: {
                Text("When disabled, the agent cannot read or modify any settings via minis-config. The change history at Logs → Config Changes remains accessible. The agent will receive a permission_denied error and can guide you via deep links instead.")
            }

            Section {
                NavigationLink { BuiltinCapabilitiesView() } label: {
                    Label("连接器与内置能力", systemImage: "square.grid.2x2")
                }
            } header: {
                Text("系统授权与工具许可")
            } footer: {
                Text("统一在连接器的内置能力页管理。系统授权与 Bot 工具使用许可分别生效，此处不重复保存设置。")
            }

            Section {
                Toggle(AppLocalized("Collect voice correction data",
                              comment: "Permissions: toggle for voice-correction learning data collection"),
                       isOn: $correctionConsent.isEnabled)
                Button(role: .destructive) {
                    showClearCorrectionConfirm = true
                } label: {
                    Label(AppLocalized("Clear Collected Data",
                                 comment: "Permissions: wipe voice-correction learning data"),
                          systemImage: "trash")
                }
            } header: {
                Text("Voice Correction Learning")
            } footer: {
                Text("When enabled, your manual fixes to voice transcripts (original → corrected pairs), accepted/rejected AI corrections, and frequently typed terms are stored in a local on-device database to make future voice corrections smarter. Nothing is uploaded. Default is off; existing data stays until you clear it.")
            }
            .confirmationDialog(
                AppLocalized("Clear all collected voice correction data?",
                       comment: "Permissions: confirm wipe of correction learning data"),
                isPresented: $showClearCorrectionConfirm,
                titleVisibility: .visible
            ) {
                Button(AppLocalized("Clear All", comment: "Confirm clearing correction data"),
                       role: .destructive) {
                    Task {
                        if let db = VoiceCorrectionDB.shared {
                            await db.clearTable("confusion_dictionary")
                            await db.clearTable("typed_vocabulary")
                            await db.clearTable("correction_events")
                        }
                        correctionDataCleared = true
                    }
                }
                Button(AppLocalized("Cancel", comment: "Cancel"), role: .cancel) {}
            }
            .alert(AppLocalized("Voice correction data cleared",
                          comment: "Permissions: wipe done confirmation"),
                   isPresented: $correctionDataCleared) {
                Button("OK") {}
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
    }

}

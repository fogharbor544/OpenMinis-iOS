//
//  SettingsSheet.swift
//  Minis - home screen (session list, navigation, settings entry)
//
//  The settings screen presented from the home toolbar: its navigation
//  destinations and the top-level list linking to every settings page.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

// MARK: - Settings Sheet

private enum SettingsDestination: Hashable {
    case providers
    case providerDetail(instanceId: String)
    case modelGroups
    case modelGroupDetail(groupId: String)
    case usage
    case skills
    // [T-ios-assistant-header-open-soul]
    // [T-tools-master-switch]
    case tools
    case memory
    case storage
    case mountedFolders
    case sharedFolders
    case logs
    case appearance
    case background
    case about
    case permissions
    case environments
    // [T-mcp-oauth-deeplink]
    case mcpIntegrations
    case mcpServerDetail(serverId: String)
}

struct SettingsSheet: View {
    @Binding var showTerminal: Bool
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var deepLink = DeepLinkCoordinator.shared
    @State private var navPath = NavigationPath()
    @State private var showFeedbackDialog = false

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                Section {
                    NavigationLink {
                        ProviderInstancesView()
                    } label: {
                        SettingsRowLabel(title: "Manage Providers", systemImage: "key.fill", color: .orange)
                    }

                    NavigationLink {
                        ModelGroupsView()
                    } label: {
                        SettingsRowLabel(title: "Model Groups", systemImage: "square.stack.3d.up.fill", color: .indigo)
                    }

                    NavigationLink {
                        UsageStatsView()
                    } label: {
                        SettingsRowLabel(title: "Token Usage", systemImage: "chart.line.uptrend.xyaxis", color: .green)
                    }
                } header: {
                    Text("LLM Providers")
                } footer: {
                    Text("Configure which models the agent uses, manage API keys & OAuth for each provider, and create model groups for fallback or load balancing.")
                }

                Section("Appearance") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label {
                            Text("Appearance")
                        } icon: {
                            SettingsActionIcon(systemImage: "paintbrush.fill", color: .indigo)
                        }
                    }
                }

                Section("Agent Runtime") {
                    NavigationLink { ToolsSettingsView() } label: { SettingsRowLabel(title: "Agent 工具", systemImage: "wrench.and.screwdriver", color: .orange) }
                    NavigationLink { HelperSettingsView() } label: { SettingsRowLabel(title: "子代理", systemImage: "person.2", color: .blue) }
                    NavigationLink { EnvironmentVariablesView() } label: { SettingsRowLabel(title: "环境变量", systemImage: "terminal", color: .teal) }
                    NavigationLink { SkillsManagementView() } label: { SettingsRowLabel(title: "Skills", systemImage: "puzzlepiece.extension", color: .purple) }
                    NavigationLink { MCPIntegrationsView() } label: { SettingsRowLabel(title: "连接器", systemImage: "square.stack.3d.up", color: .indigo) }
                }

                Section("Storage") {
                    NavigationLink {
                        StorageManagementView()
                    } label: {
                        Label {
                            Text("Storage")
                        } icon: {
                            SettingsActionIcon(systemImage: "archivebox", color: .blue)
                        }
                    }
                    // Moved here from the Bot home list (was "Shared Materials").
                    NavigationLink {
                        BotMemoryView(owner: "shared", title: "共享记忆")
                    } label: {
                        Label {
                            Text("共享记忆")
                        } icon: {
                            SettingsActionIcon(systemImage: "brain", color: .pink)
                        }
                    }
                    NavigationLink {
                        SharedFoldersSettingsView()
                    } label: {
                        Label {
                            Text("Shared Folders")
                        } icon: {
                            SettingsActionIcon(systemImage: "folder.fill.badge.person.crop", color: .green)
                        }
                    }
                    NavigationLink {
                        MountedFoldersSettingsView()
                    } label: {
                        Label {
                            Text("Mount External Folders")
                        } icon: {
                            SettingsActionIcon(systemImage: "externaldrive.badge.plus", color: .orange)
                        }
                    }
                    if #available(iOS 17.0, *) {
                        NavigationLink {
                            // v2 is the default sync engine; legacy v1
                            // settings page is unreachable from here.
                            CloudSyncSettingsV2View()
                        } label: {
                            Label {
                                Text("iCloud Sync")
                            } icon: {
                                SettingsActionIcon(systemImage: "icloud", color: .cyan)
                            }
                        }
                    }
                    NavigationLink {
                        BackupAndRestoreView()
                    } label: {
                        Label {
                            // Not just "Backup": this screen is both halves of
                            // the feature, and on a new device restore is the
                            // only one the user is looking for.
                            Text("Backup & Restore")
                        } icon: {
                            // arrow.triangle.2.circlepath reads as a round trip
                            // rather than a one-way export.
                            SettingsActionIcon(systemImage: "arrow.triangle.2.circlepath", color: .indigo)
                        }
                    }
                }

                Section("Permissions") {
                    NavigationLink {
                        OffloadPermissionSettingsView()
                    } label: {
                        Label {
                            Text("Permissions")
                        } icon: {
                            SettingsActionIcon(systemImage: "lock.shield", color: .red)
                        }
                    }
                    if BiometricAuth.isAvailable {
                        NavigationLink {
                            FaceIDProtectionSettingsView()
                        } label: {
                            Label {
                                Text("\(BiometricAuth.biometryDisplayName) Protection")
                            } icon: {
                                // Match SF Symbol to the device's actual sensor — Touch ID
                                // devices showed a Face ID glyph here before.
                                SettingsActionIcon(systemImage: BiometricAuth.biometryIconName, color: .teal)
                            }
                        }
                    }
                }

                Section("Logs") {
                    NavigationLink {
                        LogManagementView()
                    } label: {
                        Label {
                            Text("Logs")
                        } icon: {
                            SettingsActionIcon(systemImage: "doc.text", color: .gray)
                        }
                    }
                }

                Section("About") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label {
                            Text("About Minis")
                        } icon: {
                            SettingsActionIcon(systemImage: "info", color: .indigo)
                        }
                    }
                    Link(destination: URL(string: "https://openminis.github.io/privacy-policy.html")!) {
                        Label {
                            Text("Privacy Policy")
                        } icon: {
                            SettingsActionIcon(systemImage: "hand.raised", color: .teal)
                        }
                    }
                    Button {
                        showFeedbackDialog = true
                    } label: {
                        Label {
                            Text("Feedback")
                        } icon: {
                            SettingsActionIcon(systemImage: "bubble.left.and.bubble.right.fill", color: .indigo)
                        }
                    }
                    .foregroundStyle(.primary)
                    .confirmationDialog("Feedback", isPresented: $showFeedbackDialog, titleVisibility: .visible) {
                        Button("Report a Bug (GitHub)") {
                            if let url = Self.makeBugReportURL() { UIApplication.shared.open(url) }
                        }
                        Button("Feedback (Telegram)") {
                            if let url = URL(string: "https://t.me/+2NzhOJuzRyI1YmM1") { UIApplication.shared.open(url) }
                        }
                        Button("Feedback (Email)") {
                            if let url = Self.makeFeedbackEmailURL() { UIApplication.shared.open(url) }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }

            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: SettingsDestination.self) { dest in
                switch dest {
                case .providers:
                    ProviderInstancesView()
                case .providerDetail(let id):
                    ProviderInstanceDetailView(instanceId: id)
                case .modelGroups:
                    ModelGroupsView()
                case .modelGroupDetail(let id):
                    ModelGroupDetailView(groupId: id)
                case .usage:
                    UsageStatsView()
                case .skills:
                    SkillsManagementView()
                case .tools:
                    ToolsSettingsView()
                case .memory:
                    MemoryManagementView()
                case .storage:
                    StorageManagementView()
                case .mountedFolders:
                    MountedFoldersSettingsView()
                case .sharedFolders:
                    SharedFoldersSettingsView()
                case .logs:
                    // Pull a one-shot tab hint from the deep link router
                    // (e.g. `?tab=config-audit`). LogManagementView clears
                    // its local state independently; the published value
                    // here is consumed once and reset to nil.
                    LogManagementView(initialTab: deepLink.pendingLogsTab ?? "logs")
                        .onAppear { deepLink.pendingLogsTab = nil }
                case .appearance:
                    AppearanceSettingsView()
                case .background:
                    EnhancedBackgroundSettingsView()
                case .about:
                    AboutView()
                case .environments:
                    EnvironmentVariablesView()
                case .permissions:
                    OffloadPermissionSettingsView()
                // [T-mcp-oauth-deeplink] Detail = the list view told to open
                // the server's edit sheet on appear; a deleted/unknown server
                // just lands on the list (no crash, sensible fallback).
                case .mcpIntegrations:
                    MCPIntegrationsView()
                case .mcpServerDetail(let serverId):
                    MCPIntegrationsView(initialEditServerId: serverId)
                }
            }
            .onAppear {
                applyPendingDeepLink()
                // Legacy flags — kept so older call sites keep working.
                if deepLink.showEnvironmentVariables {
                    navPath.append(SettingsDestination.environments)
                    deepLink.showEnvironmentVariables = false
                }
                if deepLink.showPermissions {
                    navPath.append(SettingsDestination.permissions)
                    deepLink.showPermissions = false
                }
                // Restore the user's location after a language-change rebuild.
                // AppearanceSettingsView's language picker writes this flag
                // right before flipping `appLanguage`, knowing the root
                // `.id(appLanguage)` will tear the whole tree down. ContentView
                // re-opens the sheet on re-mount; here we push back to the
                // destination so the user lands where they were, now rendered
                // in the new language.
                if let dest = UserDefaults.standard.string(forKey: "pendingSettingsReopen") {
                    UserDefaults.standard.removeObject(forKey: "pendingSettingsReopen")
                    switch dest {
                    case "appearance":
                        navPath.append(SettingsDestination.appearance)
                    default:
                        break
                    }
                }
            }
            .onChange(of: deepLink.pendingSettingsTarget) { _ in
                applyPendingDeepLink()
            }
        }
        .preferredColorScheme(appearanceMode == 1 ? .light : appearanceMode == 2 ? .dark : nil)
        .appFontScale()
    }

    /// Translate `DeepLinkCoordinator.pendingSettingsTarget` into a
    /// NavigationStack push and clear the pending value. Called from
    /// `onAppear` (cold-start deep link) and `onChange` (deep link
    /// arriving while the sheet is already open).
    ///
    /// `.environments` keeps its existing prefill semantics — the
    /// environments view consumes `pendingEnvVarCreate` separately on
    /// appear, so we only have to navigate here.
    private func applyPendingDeepLink() {
        guard let target = deepLink.pendingSettingsTarget else { return }
        // Reset path so deep links are predictable: a deep link always
        // lands on the requested destination as the only stack entry,
        // not on top of whatever the user was browsing earlier.
        navPath = NavigationPath()
        switch target {
        case .home:
            break // already at Settings root
        case .providers:
            navPath.append(SettingsDestination.providers)
        case .providerDetail(let id):
            navPath.append(SettingsDestination.providers)
            navPath.append(SettingsDestination.providerDetail(instanceId: id))
        case .modelGroups:
            navPath.append(SettingsDestination.modelGroups)
        case .modelGroupDetail(let id):
            navPath.append(SettingsDestination.modelGroups)
            navPath.append(SettingsDestination.modelGroupDetail(groupId: id))
        case .usage:
            navPath.append(SettingsDestination.usage)
        case .skills:
            navPath.append(SettingsDestination.skills)
        case .tools:
            navPath.append(SettingsDestination.tools)
        case .memory:
            navPath.append(SettingsDestination.memory)
        case .storage:
            navPath.append(SettingsDestination.storage)
        case .mountedFolders:
            navPath.append(SettingsDestination.mountedFolders)
        case .sharedFolders:
            navPath.append(SettingsDestination.sharedFolders)
        case .logs:
            navPath.append(SettingsDestination.logs)
        case .appearance:
            navPath.append(SettingsDestination.appearance)
        case .background:
            navPath.append(SettingsDestination.background)
        case .about:
            navPath.append(SettingsDestination.about)
        case .permissions:
            navPath.append(SettingsDestination.permissions)
        case .environments:
            navPath.append(SettingsDestination.environments)
        case .mcpIntegrations:
            navPath.append(SettingsDestination.mcpIntegrations)
        case .mcpServerDetail(let id):
            navPath.append(SettingsDestination.mcpServerDetail(serverId: id))
        }
        deepLink.pendingSettingsTarget = nil
    }

    /// Compose the feedback mailto URL with a prefilled body that includes
    /// app version, iOS version, and a machine identifier, plus a prompt
    /// asking the user to attach a screenshot manually (mailto:// can't
    /// auto-attach). Using URLComponents so the subject and body go through
    /// proper URL encoding without hand-rolling addingPercentEncoding calls.
    fileprivate static func makeFeedbackEmailURL() -> URL? {
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let iosVersion = UIDevice.current.systemVersion
        let device = machineIdentifier()

        let body = """
        Please describe your feedback:


        ---
        App Version: \(appVersion) (\(build))
        iOS Version: \(iosVersion)
        Device: \(device)

        Screenshot (optional): Please attach a screenshot if relevant.
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "dev@openminis.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Minis Feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    /// Build the GitHub Issue URL with a bilingual bug-report template
    /// pre-filled with platform / OS / app / device info. SwiftUI `Link`
    /// hands the URL to UIApplication.shared.open, which routes to Safari.
    fileprivate static func makeBugReportURL() -> URL? {
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let iosVersion = UIDevice.current.systemVersion
        let device = machineIdentifier()

        let body = """
        ## 📝 Problem Summary

        <!-- Briefly describe the issue you encountered -->


        ## 📱 Basic Information

        | Field | Value |
        |-------|-------|
        | Platform | iOS |
        | OS Version | iOS \(iosVersion) |
        | Minis Version | \(appVersion) (build \(build)) |
        | Device Model | \(device) |

        ## 🔁 Steps to Reproduce

        1.
        2.
        3.

        ## ❌ Error Details

        ```
        paste error here
        ```

        ## ✅ Expected Behavior



        ## 🗂️ Additional Information

        """

        var components = URLComponents(string: "https://github.com/OpenMinis/OpenMinis/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.md"),
            URLQueryItem(name: "title", value: "[Bug] "),
            URLQueryItem(name: "body", value: body),
        ]
        return components?.url
    }

    /// Returns the hardware model identifier, e.g. "iPhone16,2".
    /// `UIDevice.current.model` returns the generic "iPhone" / "iPad" and
    /// isn't useful in a bug report, so we fall back to utsname.
    private static func machineIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        let id = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}

#Preview {
    ContentView()
}

//
//  MCPIntegrationsView.swift
//  MinisApp
//
//  Management screen for MCP (Model Context Protocol) servers. Mirrors
//  SkillsManagementView: a list of servers with status dot + name + transport,
//  swipe-to-delete, and a toolbar "+" menu offering form-add or JSON-import.
//

import SwiftUI

struct MCPIntegrationsView: View {
    /// [T-mcp-oauth-deeplink] When set (minis://settings/mcp-servers/<id>),
    /// open this server's edit form on appear — that's where the Authorize
    /// button lives. Unknown/deleted ids fall through to the plain list.
    var initialEditServerId: String? = nil

    @ObservedObject private var store = MCPStore.shared

    @State private var editingServer: MCPServerConfig?
    @State private var showAddForm = false
    @State private var showJSONImport = false
    /// [T-mcp-tools-refresh] Server whose tools sheet is presented.
    @State private var toolsServer: MCPServerConfig?
    /// One-shot consumption of initialEditServerId.
    @State private var consumedInitialEdit = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    BuiltinCapabilitiesView()
                } label: {
                    Label("Built-in Capabilities", systemImage: "square.grid.2x2")
                }
            } footer: {
                Text("Manage OpenMinis tools, permissions, skills and scheduled tasks. Built-in capabilities are not external MCP servers.")
            }
            Section("External MCP Servers") {
            if store.servers.isEmpty {
                emptyState
            } else {
                ForEach(store.servers) { server in
                    Button {
                        editingServer = server
                    } label: {
                        row(for: server)
                    }
                    .buttonStyle(.plain)
                    // [T-mcp-tools-refresh] Per-server tools entry: opens the
                    // sheet, which force-reconnects + re-pulls tools/list.
                    .contextMenu {
                        Button {
                            toolsServer = server
                        } label: {
                            Label(AppLocalized("Refresh Tools"), systemImage: "arrow.clockwise")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            toolsServer = server
                        } label: {
                            Label(AppLocalized("Tools"), systemImage: "arrow.clockwise")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.servers[$0].id }
                    for id in ids { store.delete(id: id) }
                }
            }
            }
        }
        .navigationTitle(Text("MCP Integrations"))
        .navigationBarTitleDisplayMode(.inline)
        // [T-ios-mcp-list-reload-on-appear] Re-read servers.json on appear so a
        // server written by minis-mcp-cli after launch shows up without an app
        // restart (MCPStore.load() otherwise runs only in init). Mirrors
        // SkillsManagementView's .onAppear { store.reload() }.
        .onAppear {
            store.load()
            // [T-mcp-oauth-deeplink] Deep-linked server → open its edit form
            // once. Slightly deferred so the sheet presents after the push
            // animation settles (presenting during the transition is dropped
            // by UIKit on some iOS versions).
            if !consumedInitialEdit, let id = initialEditServerId {
                consumedInitialEdit = true
                if let server = store.servers.first(where: { $0.id == id }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        editingServer = server
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddForm = true
                    } label: {
                        Label(AppLocalized("Add Server"), systemImage: "plus")
                    }
                    Button {
                        showJSONImport = true
                    } label: {
                        Label(AppLocalized("Import JSON"), systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddForm) {
            MCPFormSheet(server: nil)
        }
        .sheet(item: $editingServer) { server in
            MCPFormSheet(server: server)
        }
        .sheet(isPresented: $showJSONImport) {
            MCPJSONImportSheet()
        }
        .sheet(item: $toolsServer) { server in
            MCPToolsSheet(serverName: server.id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No MCP Servers")
                .font(.headline)
            Text("Add an MCP server to give the agent extra tools. Tap + to add one manually or import a JSON config.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    private func row(for server: MCPServerConfig) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(server.enabled ? Color.green : Color.gray)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(server.id)
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(server.isHTTP ? "HTTP" : (server.isSTDIO ? "STDIO" : "—"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(server.transportSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Tools sheet [T-mcp-tools-refresh]

/// Live tools list for one server. Opening the sheet performs a FORCED
/// refresh (`minis-mcp-cli refresh <name>`: evict the daemon session,
/// re-handshake, tools/list) so tools the remote server added after we first
/// connected appear without restarting the app or the daemon.
struct MCPToolsSheet: View {
    let serverName: String
    @Environment(\.dismiss) private var dismiss
    @State private var tools: [MCPStore.MCPToolInfo] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reconnecting and fetching tools…")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorText {
                    Section {
                        Label {
                            Text(errorText)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        .font(.subheadline)
                    }
                } else if tools.isEmpty {
                    Text("The server reported no tools.")
                        .foregroundStyle(.secondary)
                } else {
                    Section(footer: Text("Fetched live from the server just now.")) {
                        ForEach(tools) { tool in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tool.name)
                                    .font(.body.monospaced())
                                if !tool.description.isEmpty {
                                    Text(tool.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: serverName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel(Text("Refresh tools"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized("Done")) { dismiss() }
                }
            }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        isLoading = true
        errorText = nil
        do {
            tools = try await MCPStore.shared.refreshTools(server: serverName)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

/// A catalog of existing controls, backed by the same stores used during execution.
private struct BuiltinCapabilitiesView: View {
    @ObservedObject private var configGate = MinisConfigPermissionStore.shared
    @AppStorage(AgentToolSwitch.browser.key) private var browser = AgentToolSwitch.browser.defaultValue
    @AppStorage(AgentToolSwitch.agents.key) private var agents = AgentToolSwitch.agents.defaultValue
    @AppStorage(AgentToolSwitch.userAsk.key) private var userAsk = AgentToolSwitch.userAsk.defaultValue

    var body: some View {
        List {
            Section {
                Toggle("Browser Use", isOn: $browser)
                Toggle("Sub Agents", isOn: $agents)
                Toggle("Ask the User", isOn: $userAsk)
                Toggle("Allow minis-config", isOn: $configGate.enabled)
            } header: { Text("Agent Tools") } footer: {
                Text("These are the existing global tool switches. Conversations and delegated agents use the same controls; asking the user is available only in interactive runs.")
            }
            Section("Configuration") {
                NavigationLink("Models") { ProviderInstancesView() }
                NavigationLink("Model Groups") { ModelGroupsView() }
                NavigationLink("Sub Agents") { HelperSettingsView() }
                NavigationLink("Skills") { SkillsManagementView() }
                NavigationLink("Soul") { SoulSettingsView() }
                NavigationLink("Memory") { MemoryManagementView() }
                NavigationLink("Scheduled Tasks") { ScheduledTasksManagementView() }
                NavigationLink("Permissions") { OffloadPermissionSettingsView() }
                NavigationLink("Environment Variables") { EnvironmentVariablesView() }
                NavigationLink("Shared Folders") { SharedFoldersSettingsView() }
                NavigationLink("Mounted Folders") { MountedFoldersSettingsView() }
            }
            Section {
                Label("Shell and Files", systemImage: "terminal")
                Text("Shell execution, file reading, writing, editing and image reading are core tools. They have no separate global disable switch.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Core Tools") }
            Section {
                ForEach(Self.nativeCommands, id: \.name) { command in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(command.displayLabel)
                        Text(command.description.isEmpty ? (Self.purposes[command.name] ?? command.name) : command.description)
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Built-in · \(command.name)").font(.caption2).foregroundStyle(.secondary)
                        if command.showInSettings {
                            CapabilityPermissionPicker(command: command)
                        } else if command.name == "minis-browser-use" {
                            Text(browser ? "Enabled" : "Disabled").font(.caption)
                        } else if command.name == "minis-config" {
                            Text(configGate.enabled ? "Enabled" : "Disabled").font(.caption)
                        } else {
                            Text("No additional OpenMinis permission gate")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text("Device Capabilities") } footer: {
                Text("These native commands are invoked through the existing shell/offload path. iOS authorization, device support and foreground requirements still apply. Permission policy does not guarantee system access.")
            }
        }
        .navigationTitle("Built-in Capabilities")
    }

    // Public native handlers registered by ISHKernel; permission ownership stays with the existing stores.
    private static var nativeCommands: [OffloadCommandInfo] {
        OffloadPermissionManager.allCommands + [
            .init(name: "apple-bluetooth", displayLabel: "Bluetooth", description: "Discover devices and read or write Bluetooth characteristics", category: .system, showInSettings: false),
            .init(name: "apple-nfc", displayLabel: "NFC", description: "Scan, read and write NFC tags on supported devices", category: .system, showInSettings: false),
            .init(name: "ffmpeg", displayLabel: "FFmpeg", description: "Native audio and video processing", category: .media, showInSettings: false),
            .init(name: "minis-model-use", displayLabel: "Model Calls", description: "List, search and invoke configured models", category: .system, showInSettings: false),
            .init(name: "minis-sessions-cli", displayLabel: "Sessions", description: "Read conversations and send prompts through the existing chat runtime", category: .system, showInSettings: false),
            .init(name: "minis-scheduled", displayLabel: "Scheduled Tasks", description: "Create and manage in-process scheduled prompts", category: .system, showInSettings: false),
            .init(name: "minis-browser-use", displayLabel: "Browser Commands", description: "Navigate and interact with the built-in browser", category: .system, showInSettings: false),
            .init(name: "minis-config", displayLabel: "Configuration Tool", description: "Read or change supported settings through the configuration permission gate", category: .system, showInSettings: false),
            .init(name: "minis-debug", displayLabel: "Diagnostics", description: "Read logs; developer RPC commands are available only in debug builds", category: .system, showInSettings: false)
        ]
    }

    private static let purposes: [String: String] = [
        "apple-speak": "Synthesize speech", "apple-speech": "Transcribe speech",
        "apple-player": "Play audio and video", "apple-media": "Inspect and transform media",
        "apple-device": "Read device information", "apple-notification": "Manage local notifications",
        "apple-alarm": "Manage alarms", "apple-open": "Open URLs in system apps",
        "apple-maps": "Search places and routes", "apple-weather": "Read weather information",
        "apple-nlp": "Analyze text", "apple-vision": "Recognize text and analyze images"
    ]
}

private struct CapabilityPermissionPicker: View {
    let command: OffloadCommandInfo
    @ObservedObject private var manager = OffloadPermissionManager.shared
    var body: some View {
        Picker("Permission", selection: Binding(
            get: { manager.permissionLevel(for: command.name) },
            set: { manager.setPermissionLevel($0, for: command.name) }
        )) {
            ForEach(OffloadPermissionLevel.allCases, id: \.self) { level in
                Text(level.displayName).tag(level)
            }
        }
    }
}

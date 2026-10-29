//
//  SessionMCPsView.swift
//  MinisApp
//
//  Per-session MCP-server toggle sheet: override which MCP servers are active
//  in a chat. Mirrors SessionSkillsView.
//

import SwiftUI

struct SessionMCPsView: View {
    let sessionId: String?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MCPStore.shared
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @State private var searchQuery = ""

    private func isEnabled(_ server: MCPServerConfig) -> Bool {
        if let sid = sessionId {
            return store.isEnabledForSession(server.id, sessionId: sid)
        }
        return server.enabled
    }

    private func setOverride(_ item: MCPServerConfig, _ enabled: Bool) {
        guard let sid = sessionId, workspace.bot(forSession: sid) != nil else { return }
        store.setSessionOverride(serverId: item.id, sessionId: sid, enabled: enabled)
    }

    private func applyToAll(_ scope: [MCPServerConfig], enabled: Bool) {
        for item in scope { setOverride(item, enabled) }
    }

    private var filteredServers: [MCPServerConfig] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.servers }
        return store.servers.filter {
            $0.id.lowercased().contains(q) || ($0.note ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        // Reference the version counter so SwiftUI refreshes on override changes.
        let _ = store.sessionOverrideVersion

        NavigationStack {
            List {
                Text("此处修改所属 Bot 的设置，对它的全部私聊和群聊生效。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error = workspace.errorMessage { Text(error).foregroundStyle(.red) }
                if store.servers.isEmpty {
                    Section {
                        SessionOverrideEmptyCard(systemImage: "square.stack.3d.up",
                                                 title: AppLocalized("No MCP servers"),
                                                 subtitle: AppLocalized("Add servers in Settings → MCP Integrations."))
                    }
                } else if filteredServers.isEmpty {
                    Section {
                        Text(AppLocalized("No MCP servers match \"\(searchQuery)\"."))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Section {
                        ForEach(filteredServers) { server in
                            // [T-session-mcp-detail] A tap opens the read-only
                            // detail; the toggle keeps its own tap target.
                            NavigationLink {
                                SessionMCPDetailView(server: server)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.id).font(.body)
                                        if let note = server.note, !note.isEmpty {
                                            Text(note)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { isEnabled(server) },
                                        set: { setOverride(server, $0) }
                                    ))
                                    .labelsHidden()
                                }
                            }
                        }
                    } header: {
                        let scope = filteredServers
                        SessionBulkToggleHeader(
                            availability: SessionBulkToggleRules.availability(scope.map { isEnabled($0) })
                        ) { applyToAll(scope, enabled: $0) }
                    } footer: {
                        SessionOverrideListFooter(
                            note: Text("修改所属 Bot 的连接器设置，对它的全部会话生效。"),
                            searchQuery: searchQuery)
                    }
                }
            }
            .disabled(sessionId.flatMap { workspace.bot(forSession: $0) } == nil)
            .navigationTitle("Bot 连接器")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(AppLocalized("Search MCP servers")))
            .onAppear { store.load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// BEGIN MCPServerDetailRules
/// What the read-only server detail shows, kept free of SwiftUI for tests.
enum MCPServerDetailRules {
    /// The config does not record whether a URL server speaks Streamable HTTP
    /// or SSE, so a URL server is shown as both, like the Android sheet.
    static func transportLabel(isSTDIO: Bool) -> String {
        isSTDIO ? "STDIO" : "HTTP / SSE"
    }

    /// Header / env-var NAMES, sorted. Only the keys are read: the values
    /// routinely hold API keys and this sheet sits over a chat that may be
    /// screen-shared, so they never reach the UI.
    static func secretNames(_ map: [String: String]?) -> [String] {
        guard let map else { return [] }
        return map.keys.sorted()
    }

    /// Args joined for display, or nil when there are none.
    static func argsLine(_ args: [String]?) -> String? {
        guard let args, !args.isEmpty else { return nil }
        return args.joined(separator: " ")
    }

    static func trimmedNote(_ note: String?) -> String? {
        let t = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
// END MCPServerDetailRules

/// [T-session-mcp-detail] Read-only detail of one MCP server, opened from the
/// in-chat sheet (Android 3109967bc has the same page). Nothing here writes
/// the config, exports it, or reads a header / env value.
private struct SessionMCPDetailView: View {
    let server: MCPServerConfig
    @State private var authorized = false

    var body: some View {
        let headerNames = MCPServerDetailRules.secretNames(server.headers)
        let envNames = MCPServerDetailRules.secretNames(server.env)
        List {
            Section {
                LabeledContent(AppLocalized("Transport"),
                               value: MCPServerDetailRules.transportLabel(isSTDIO: server.isSTDIO))
                if server.isSTDIO {
                    detailRow(AppLocalized("Command"), server.command ?? "")
                    if let args = MCPServerDetailRules.argsLine(server.args) {
                        detailRow(AppLocalized("Arguments"), args)
                    }
                    LabeledContent(AppLocalized("Startup timeout (seconds)"),
                                   value: server.startupTimeoutSeconds.map(String.init) ?? AppLocalized("Default 60"))
                } else {
                    let url = server.url ?? ""
                    // Long-press copies the URL, like a skill's source URL.
                    detailRow(AppLocalized("Server URL"), url, selectable: false)
                        .modifier(SkillSourceURLContextMenu(url: url.isEmpty ? nil : url,
                                                            title: AppLocalized("Copy URL")) {})
                    if server.oauth != nil {
                        LabeledContent("OAuth",
                                       value: authorized ? AppLocalized("Authorized") : AppLocalized("Not authorized"))
                    }
                }
            }

            if let note = MCPServerDetailRules.trimmedNote(server.note) {
                Section(AppLocalized("Note")) {
                    Text(note).textSelection(.enabled)
                }
            }

            if !headerNames.isEmpty {
                Section {
                    namesText(headerNames)
                } header: {
                    Text(AppLocalized("Custom Headers"))
                } footer: {
                    if envNames.isEmpty { valuesHiddenNote }
                }
            }
            if !envNames.isEmpty {
                Section {
                    namesText(envNames)
                } header: {
                    Text(AppLocalized("Environment Variables"))
                } footer: {
                    valuesHiddenNote
                }
            }
        }
        .navigationTitle(server.id)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: server.id) {
            guard server.oauth != nil else { return }
            authorized = MCPOAuthController.isAuthorized(server: server.id)
        }
    }

    private var valuesHiddenNote: some View {
        Text(AppLocalized("Values are hidden because they can contain keys. View or edit them in Settings → MCP Integrations."))
    }

    private func namesText(_ names: [String]) -> some View {
        Text(names.joined(separator: "\n"))
            .font(.system(.subheadline, design: .monospaced))
            .textSelection(.enabled)
    }

    /// Label above a full-width monospaced value. Not selectable when the row
    /// carries a long-press menu, which text selection would otherwise take.
    @ViewBuilder
    private func detailRow(_ label: String, _ value: String, selectable: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if selectable {
                Text(value).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
            } else {
                Text(value).font(.system(.subheadline, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

//
//  MCPIntegrationsView.swift
//  MinisApp
//
//  Management screen for MCP (Model Context Protocol) servers. Mirrors
//  SkillsManagementView: a list of servers with status dot + name + transport,
//  swipe-to-delete, and a toolbar "+" menu offering form-add or JSON-import.
//

import SwiftUI
import EventKit
import Photos
import MediaPlayer
import UserNotifications
import HomeKit
import HealthKit
import AlarmKit
import AVFoundation
import CoreLocation

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
                NavigationLink("按 Bot 配置") { BotCapabilitySettingsView(skills: false) }
            }
            Section {
                NavigationLink {
                    BuiltinCapabilitiesView()
                } label: {
                    Label("Built-in Capabilities", systemImage: "square.grid.2x2")
                }
            } footer: {
                Text("Manage supported iOS apps and external connectors.")
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

/// System authorization is queried again after returning from Settings; local policy
/// never stands in for an OS grant. Some Apple services deliberately hide read grants.
struct BuiltinCapabilitiesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var statuses: [String: String] = [:]
    @State private var granted: Set<String> = []
    @State private var busy: String?
    @State private var message: String?
    @StateObject private var homeAuthorization = HomeConnectorAuthorization()
    private let events = EKEventStore()
    @ObservedObject private var permissions = OffloadPermissionManager.shared

    private let apps: [(id: String, name: String, icon: String)] = [
        ("calendar", "日历", "calendar"), ("reminders", "提醒事项", "checklist"),
        ("photos", "照片", "photo"), ("camera", "相机", "camera"), ("music", "音乐", "music.note"),
        ("home", "家庭", "house"), ("health", "健康", "heart"),
        ("alarm", "时钟与闹钟", "alarm"), ("notification", "通知", "bell"),
        ("maps", "地图", "map"), ("weather", "天气", "cloud.sun"),
        ("location", "位置", "location"), ("clipboard", "剪贴板", "doc.on.clipboard")
    ]

    var body: some View {
        List {
            Section {
                Text("系统授权决定 iOS 是否开放数据；工具使用许可决定 Bot 能否调用。两者分别管理，对所有 Bot 生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(apps, id: \.id) { app in
                Section {
                    capabilityCard(app)
                }
            }
            Section {
                Text("健康读取权限由 iOS 隐藏，不会显示为已开启。地图和天气无需独立授权；定位权限单独管理。相机和音乐共用媒体工具许可。返回应用后会重新检查系统授权。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("内置能力")
        .task { await refresh() }
        .onChange(of: homeAuthorization.authorized) { _ in Task { await refresh() } }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await refresh() } }
        }
        .alert("系统权限", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("打开系统设置") { openSettings() }
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func capabilityCard(_ app: (id: String, name: String, icon: String)) -> some View {
        // A single list row owns the card's layout and separator.
        // Native row separators otherwise align to the trailing
        // status instead of the card's leading content edge.
        VStack(spacing: 4) {
            Button { Task { await manage(app.id) } } label: {
                HStack(spacing: 12) {
                    Image(systemName: app.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.body.weight(.medium))
                        HStack(spacing: 5) {
                            Image(systemName: granted.contains(app.id) ? "checkmark.circle.fill" : "info.circle")
                                .foregroundStyle(granted.contains(app.id) ? Color.green : Color.secondary)
                                .accessibilityHidden(true)
                            Text(statuses[app.id] ?? "检查中")
                                .foregroundStyle(granted.contains(app.id) ? Color.secondary : Color.primary)
                        }
                        .font(.footnote.weight(.medium))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if busy == app.id { ProgressView() }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(busy != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(app.name)：系统授权")
            .accessibilityValue(statuses[app.id] ?? "检查中")

            if let command = command(for: app.id) {
                Divider()
                HStack(spacing: 12) {
                    Text("Bot 调用")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Menu {
                        Picker("工具使用许可", selection: Binding(get: { permissions.permissionLevel(for: command) }, set: { permissions.setPermissionLevel($0, for: command) })) {
                            Text("允许").tag(OffloadPermissionLevel.bypass)
                            Text("每个会话首次询问").tag(OffloadPermissionLevel.askOnce)
                            Text("禁止").tag(OffloadPermissionLevel.notAllowed)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(permissions.permissionLevel(for: command).displayName)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("\(app.name)：工具使用许可")
                    .accessibilityValue(permissions.permissionLevel(for: command).displayName)
                }
                .font(.subheadline)
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }

    @MainActor private func refresh() async {
        var enabled = Set<String>()
        var values: [String: String] = [:]
        func record(_ id: String, _ allowed: Bool, _ other: String = "未开启") {
            values[id] = allowed ? "已开启" : other
            if allowed { enabled.insert(id) }
        }
        if #available(iOS 17.0, *) {
            record("calendar", EKEventStore.authorizationStatus(for: .event) == .fullAccess,
                   EKEventStore.authorizationStatus(for: .event) == .writeOnly ? "仅允许写入" : "未开启")
            record("reminders", EKEventStore.authorizationStatus(for: .reminder) == .fullAccess)
        } else {
            record("calendar", EKEventStore.authorizationStatus(for: .event) == .authorized)
            record("reminders", EKEventStore.authorizationStatus(for: .reminder) == .authorized)
        }
        let photos = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        record("photos", photos == .authorized, photos == .limited ? "仅选定照片" : "未开启")
        record("camera", AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        record("music", MPMediaLibrary.authorizationStatus() == .authorized)
        homeAuthorization.update()
        if let authorized = homeAuthorization.authorized {
            record("home", authorized)
        } else { values["home"] = "点按检查授权" }
        values["health"] = HKHealthStore.isHealthDataAvailable() ? "在健康中管理" : "设备不支持"
        if #available(iOS 26.0, *) {
            record("alarm", AlarmManager.shared.authorizationState == .authorized)
        } else { values["alarm"] = "需要 iOS 26" }
        let notification = await UNUserNotificationCenter.current().notificationSettings()
        record("notification", notification.authorizationStatus == .authorized,
               notification.authorizationStatus == .provisional ? "静默通知" : "未开启")
        values["maps"] = "无需独立授权"
        values["weather"] = "无需独立授权"
        let location = CLLocationManager().authorizationStatus
        record("location", location == .authorizedAlways || location == .authorizedWhenInUse,
               location == .restricted ? "系统限制" : "未开启")
        values["clipboard"] = "粘贴时由系统确认"
        statuses = values
        granted = enabled
    }

    @MainActor private func manage(_ id: String) async {
        busy = id
        defer { busy = nil }
        do {
            switch id {
            case "calendar":
                if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                    if #available(iOS 17.0, *) { _ = try await events.requestFullAccessToEvents() }
                    else { _ = try await events.requestAccess(to: .event) }
                } else { openSettings() }
            case "reminders":
                if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                    if #available(iOS 17.0, *) { _ = try await events.requestFullAccessToReminders() }
                    else { _ = try await events.requestAccess(to: .reminder) }
                } else { openSettings() }
            case "photos":
                if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                    _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                } else { openSettings() }
            case "music":
                if MPMediaLibrary.authorizationStatus() == .notDetermined {
                    _ = await MPMediaLibrary.requestAuthorization()
                } else { openSettings() }
            case "camera":
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                } else { openSettings() }
            case "notification":
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                } else { openSettings() }
            case "alarm":
                if #available(iOS 26.0, *) {
                    if AlarmManager.shared.authorizationState == .notDetermined {
                        _ = try await AlarmManager.shared.requestAuthorization()
                    } else { openSettings() }
                }
            case "home":
                homeAuthorization.start()
                message = "请在系统弹窗或设置 → 隐私与安全性 → HomeKit 中管理家庭权限。自签名证书需要包含 HomeKit 能力。"
            case "health":
                message = "请在健康 App → 头像 → App → OpenMinis 中按数据类型管理权限。首次使用健康工具时会申请授权；自签名证书需要包含 HealthKit 能力。iOS 不向 App 披露读取授权状态，授权弹窗完成也不代表所有权限已开启。"
            case "location":
                message = "请在系统设置 → OpenMinis → 位置中管理授权。使用当前位置的工具会请求必要权限。"
            case "clipboard":
                message = "读取其他应用复制的内容时，iOS 会按系统策略确认。工具许可不会绕过系统的粘贴保护。"
            case "maps":
                message = "地图支持地点搜索和路线查询，无需独立授权。使用当前位置时，请在系统设置 → OpenMinis → 位置中管理定位权限。"
            case "weather":
                message = "天气支持指定地点的天气查询，无需独立授权。使用当前位置时，请在系统设置 → OpenMinis → 位置中管理定位权限。"
            default: break
            }
            await refresh()
        } catch { message = error.localizedDescription }
    }

    private func command(for id: String) -> String? {
        switch id {
        case "health": return "apple-healthkit"
        case "home": return "apple-homekit"
        case "music", "camera": return "apple-media"
        default: return "apple-" + id
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

@MainActor
private final class HomeConnectorAuthorization: NSObject, ObservableObject, HMHomeManagerDelegate {
    @Published var authorized: Bool?
    private var manager: HMHomeManager?

    func start() {
        if manager == nil {
            let manager = HMHomeManager()
            manager.delegate = self
            self.manager = manager
        }
        update()
    }

    func update() {
        authorized = manager.map { $0.authorizationStatus.contains(.authorized) }
    }

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor [weak self] in self?.update() }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor [weak self] in self?.update() }
    }
}

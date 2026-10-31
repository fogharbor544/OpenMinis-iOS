import PhotosUI
import SwiftUI
import UIKit

/// Chat-page actions the profile's "会话" section hands back to the open chat.
/// They depend on the chat's own state (share picker, search bar, alerts), so
/// the profile only requests them; the chat performs them after dismissal.
enum BotChatAction: Equatable {
    case search, share, compact, clear, scheduledTasks, files, tokenUsage, forceSync, forcePull
}

/// Per-chat switches from the former "..." menu. Built by the open chat from
/// the same state and setters that menu used, so behaviour is identical.
struct BotChatControls {
    var speakEnabled: Bool
    var setSpeakEnabled: (Bool) -> Void
    var keepAwakeEnabled: Bool
    var setKeepAwake: (Bool) -> Void
    var screenSaverNowEnabled: Bool
    var setScreenSaverNow: (Bool) -> Void
    /// Hidden on a Mac, as in the old menu (no auto-lock, no OLED).
    var showsKeepAwake: Bool
    var showEnhancedCacheToggle: Bool
    var enhancedCacheEnabled: Bool
    var setEnhancedCache: (Bool) -> Void
    var showFastModeToggle: Bool
    var showUltrafast: Bool
    var speedTier: SpeedTier
    var setSpeedTier: (SpeedTier) -> Void
    var showsICloudActions: Bool
    var iCloudActionsDisabled: Bool
}

/// Bot profile page: avatar header, browser preview card, capability entries,
/// and the chat's former "..." actions. Opened from the home list's long-press,
/// the chat header name, and the chat's top-right profile button.
struct BotProfileView: View {
    let botID: String
    /// Non-nil when opened from a chat; enables the "会话" section.
    var sessionID: String? = nil
    var onChatAction: ((BotChatAction) -> Void)? = nil
    var chatControls: BotChatControls? = nil

    @ObservedObject private var store = BotWorkspaceStore.shared
    @ObservedObject private var runner = BotRoomRunner.shared
    @ObservedObject private var subAgents = SubAgentStore.shared
    @ObservedObject private var envVars = EnvVarStore.shared
    @ObservedObject private var skills = SkillStore.shared
    @ObservedObject private var connectors = MCPStore.shared
    @ObservedObject private var providers = ProviderConfigStore.shared
    @ObservedObject private var memory = BotMemoryStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var renaming = false
    @State private var draftName = ""
    @State private var editingInstructions = false
    @State private var choosingAvatar = false
    @State private var deleting = false
    @State private var browserTarget: BotBrowserTarget?
    @State private var showTerminal = false
    @State private var preview: (image: UIImage, pageURL: String?, capturedAt: Date)?
    @State private var openingSession = false
    @State private var resolvedSessionID: String?
    /// Values just switched in the 会话 controls, shown until the sheet closes.
    @State private var overriddenToggles: [ChatToggle: Bool] = [:]
    @State private var overriddenTier: SpeedTier?
    private enum ChatToggle: Hashable { case speak, keepAwake, screenSaver, enhancedCache }

    private var bot: BotProfile? { store.bot(botID) }
    /// A group round running anywhere locks Bot edits, as on the home list.
    private var locked: Bool { !runner.activeRooms.isEmpty }
    private var browserSessionID: String? { sessionID ?? bot?.sessionId }
    private var liveBrowsing: Bool {
        browserSessionID.flatMap { ViewModelCache.shared.get(for: $0)?.browserTabPool.isAgentBrowsing } ?? false
    }

    var body: some View {
        Group {
            if let bot { content(bot) }
            else { ContentUnavailableLabel(text: "This Bot or group no longer exists.") }
        }
        .navigationTitle("Bot 资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let bot { profileMenu(bot) }
            }
        }
        .task(id: browserSessionID) { loadPreview() }
    }

    // MARK: - Sections

    private func content(_ bot: BotProfile) -> some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Button { choosingAvatar = true } label: { BotAvatar(profile: bot, size: 72) }
                        .buttonStyle(.plain)
                        .disabled(locked)
                        .accessibilityLabel("更改头像")
                    Text(bot.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    BotRunStatusView(botID: bot.id, sessionID: sessionID, allowsWrapping: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section { browserCard(bot) }

            Section {
                NavigationLink { BotMemoryView(owner: "bot:\(bot.id)", title: bot.name) } label: {
                    SettingsRowLabel(title: "长期记忆", systemImage: "brain", color: .pink)
                }
                if let sessionID {
                    Button { request(.files) } label: { SettingsRowLabel(title: "对话文件", systemImage: "folder", color: .blue) }
                        .foregroundStyle(.primary)
                    Button { request(.scheduledTasks) } label: { SettingsRowLabel(title: "定时任务", systemImage: "clock", color: .orange) }
                        .foregroundStyle(.primary)
                } else {
                    NavigationLink { ScheduledTasksManagementView(botID: bot.id) } label: {
                        SettingsRowLabel(title: "定时任务", systemImage: "clock", color: .orange)
                    }
                }
            }

            Section("配置") {
                Button { editingInstructions = true } label: {
                    SettingsDetailRow(title: "指令", systemImage: "text.alignleft", color: .gray,
                                      value: bot.instructions.split(whereSeparator: \.isNewline).first.map(String.init) ?? "未设置",
                                      valueLineLimit: 2)
                }
                .foregroundStyle(.primary)
                .disabled(locked)
                Picker(selection: modelGroupBinding(bot)) {
                    Text("Default Model Group").tag("")
                    ForEach(providers.modelGroups) { group in Text(group.name).tag(group.id) }
                } label: { SettingsRowLabel(title: "模型组", systemImage: "square.stack.3d.up", color: .indigo) }
                .disabled(locked)
                NavigationLink { BotCapabilityToggles(botID: bot.id, skills: true) } label: {
                    SettingsDetailRow(title: "技能", systemImage: "puzzlepiece.extension", color: .purple,
                               value: enabledCount(bot.skillOverrides, all: skills.skills.map { ($0.id, $0.isEnabled) }))
                }
                NavigationLink { BotCapabilityToggles(botID: bot.id, skills: false) } label: {
                    SettingsDetailRow(title: "连接器 (MCP)", systemImage: "square.stack.3d.up", color: .indigo,
                               value: enabledCount(bot.connectorOverrides, all: connectors.servers.map { ($0.id, $0.enabled) }))
                }
                Toggle(isOn: memoryBinding(bot)) { SettingsRowLabel(title: "启用长期记忆", systemImage: "brain.head.profile", color: .pink) }
                    .disabled(locked)
                NavigationLink { HelperSettingsView(scopeBotID: bot.id) } label: {
                    SettingsDetailRow(title: "子代理", systemImage: "person.2", color: .blue,
                               value: "\(subAgents.subAgents.filter { $0.ownerBotId == bot.id }.count) 个专属")
                }
                NavigationLink { EnvironmentVariablesView(scopeBotID: bot.id) } label: {
                    SettingsDetailRow(title: "环境变量", systemImage: "terminal", color: .teal,
                               value: "\(envVars.entries(ownedBy: bot.id).count) 个专属")
                }
            }

            if sessionID != nil, onChatAction != nil {
                Section("会话") {
                    chatActionRow("在聊天中搜索", "magnifyingglass", .search)
                    chatActionRow("分享聊天", "square.and.arrow.up", .share)
                    chatActionRow("压缩消息", "arrow.down.right.and.arrow.up.left", .compact)
                    chatActionRow("用量统计", "number", .tokenUsage)
                    Button(role: .destructive) { request(.clear) } label: { SettingsRowLabel(title: "清空聊天", systemImage: "trash", color: .red) }
                }
                if let controls = chatControls { chatControlSections(controls) }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $choosingAvatar) { BotAvatarPicker(botID: bot.id) }
        .sheet(isPresented: $editingInstructions) { BotInstructionsEditor(botID: bot.id) }
        .sheet(item: $browserTarget, onDismiss: loadPreview) { target in
            BotBrowserHost(vm: target.vm)
        }
        .fullScreenCover(isPresented: $showTerminal) {
            NavigationStack {
                ISHTerminalView(sessionId: resolvedSessionID, showCloseButton: true)
                    .onAppear {
                        if let sid = resolvedSessionID { ViewModelCache.shared.getOrCreate(for: sid).vm.mountMinis(for: sid) }
                    }
            }
        }
        .alert("重命名", isPresented: $renaming) {
            TextField("名称", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard var current = store.bot(bot.id) else { return }
                current.name = draftName
                _ = store.save(current)
            }
            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("删除此 Bot？它的长期记忆、专属子代理和专属环境变量会一并删除，共享给它的记忆访问也会移除。对话记录保留。",
                            isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteBot(bot) }
        }
    }

    @ViewBuilder
    private func browserCard(_ bot: BotProfile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SettingsActionIcon(systemImage: "globe", color: .blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("浏览器").font(.body)
                    if liveBrowsing {
                        Text("运行中").foregroundStyle(.secondary)
                    } else if let preview {
                        Text(preview.capturedAt.formatted(.relative(presentation: .named)))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                Spacer(minLength: 8)
                Menu {
                    Button { openSessionThen { showTerminal = true } } label: { Label("打开终端", systemImage: "terminal") }
                    Button { refreshBrowser() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                        .disabled(browserSessionID == nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("浏览器选项")
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            Divider().padding(.horizontal, 16)
            Button { openSessionThen {
                guard let sid = resolvedSessionID else { return }
                let vm = ViewModelCache.shared.getOrCreate(for: sid).vm
                vm.browserTabPool.sessionId = sid
                browserTarget = BotBrowserTarget(id: sid, vm: vm)
            } } label: {
                VStack(spacing: 0) {
                    if let preview {
                        ZStack {
                            Color(UIColor.tertiarySystemFill)
                            Image(uiImage: preview.image).resizable().scaledToFill()
                        }
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("进入浏览器").font(.body)
                            Text(preview?.pageURL ?? "还没有打开过网页")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        if openingSession { ProgressView() }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .padding(16)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(openingSession)
            .accessibilityLabel("进入浏览器")
            .accessibilityValue(preview?.pageURL ?? "还没有打开过网页")
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private func profileMenu(_ bot: BotProfile) -> some View {
        Menu {
            Button { choosingAvatar = true } label: { Label("更改头像", systemImage: "arrow.left.arrow.right") }
                .disabled(locked)
            Button { draftName = bot.name; renaming = true } label: { Label("重命名", systemImage: "pencil") }
                .disabled(locked)
            Button { store.setPinned(bot.pinnedAt == nil, botID: bot.id) } label: {
                Label(bot.pinnedAt == nil ? "置顶此 Bot" : "取消置顶", systemImage: bot.pinnedAt == nil ? "pin" : "pin.slash")
            }
            Button {
                UIPasteboard.general.string = bot.id
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: { Label("复制 ID", systemImage: "doc.on.doc") }
            Divider()
            Button(role: .destructive) { deleting = true } label: { Label("删除此 Bot", systemImage: "trash") }
                .disabled(locked)
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多")
    }

    private func chatActionRow(_ title: String, _ symbol: String, _ action: BotChatAction) -> some View {
        Button { request(action) } label: { SettingsRowLabel(title: title, systemImage: symbol, color: .blue) }
            .foregroundStyle(.primary)
    }

    /// Switches act in place; local copies keep each row's checkmark current
    /// while the sheet stays open (the chat's own state updates underneath).
    @ViewBuilder
    private func chatControlSections(_ controls: BotChatControls) -> some View {
        Section {
            Toggle(isOn: toggle(.speak, controls.speakEnabled, controls.setSpeakEnabled)) {
                SettingsRowLabel(title: "朗读回复", systemImage: "speaker.wave.2", color: .blue)
            }
            if controls.showsKeepAwake {
                Toggle(isOn: toggle(.keepAwake, controls.keepAwakeEnabled, controls.setKeepAwake)) {
                    SettingsRowLabel(title: "保持屏幕常亮", systemImage: "sun.max", color: .orange)
                }
                Toggle(isOn: toggle(.screenSaver, controls.screenSaverNowEnabled, controls.setScreenSaverNow)) {
                    SettingsRowLabel(title: "使用屏保", systemImage: "moon.stars", color: .indigo)
                }
            }
        } footer: {
            if controls.showsKeepAwake { Text("仅对当前对话生效，离开对话后恢复设置中的默认值。") }
        }
        if controls.showEnhancedCacheToggle || controls.showFastModeToggle {
            Section("模型") {
                if controls.showEnhancedCacheToggle {
                    Toggle(isOn: toggle(.enhancedCache, controls.enhancedCacheEnabled, controls.setEnhancedCache)) {
                        SettingsRowLabel(title: "增强缓存", systemImage: "clock.arrow.circlepath", color: .teal)
                    }
                }
                if controls.showFastModeToggle {
                    if controls.showUltrafast {
                        Picker(selection: Binding(get: { overriddenTier ?? controls.speedTier },
                                                  set: { overriddenTier = $0; controls.setSpeedTier($0) })) {
                            ForEach(SpeedTier.allCases, id: \.self) { tier in
                                Label(tier.title, systemImage: tier.symbol).tag(tier)
                            }
                        } label: { SettingsRowLabel(title: "快速模式", systemImage: SpeedTier.entrySymbol, color: .orange) }
                    } else {
                        Toggle(isOn: Binding(get: { (overriddenTier ?? controls.speedTier) != .standard },
                                             set: { on in
                                                 let tier: SpeedTier = on ? .fast : .standard
                                                 overriddenTier = tier
                                                 controls.setSpeedTier(tier)
                                             })) {
                            SettingsRowLabel(title: "快速模式", systemImage: SpeedTier.fast.symbol, color: .orange)
                        }
                    }
                }
            }
        }
        if controls.showsICloudActions {
            Section("iCloud") {
                chatActionRow("强制 iCloud 同步", "icloud.and.arrow.up", .forceSync)
                    .disabled(controls.iCloudActionsDisabled)
                chatActionRow("强制拉取消息", "icloud.and.arrow.down", .forcePull)
                    .disabled(controls.iCloudActionsDisabled)
            }
        }
    }

    /// A toggle that shows the new value immediately and forwards it to the chat.
    private func toggle(_ key: ChatToggle, _ initial: Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { overriddenToggles[key] ?? initial },
                set: { overriddenToggles[key] = $0; set($0) })
    }

    // MARK: - Actions

    private func request(_ action: BotChatAction) {
        onChatAction?(action)
        dismiss()
    }

    private func loadPreview() {
        guard let sid = browserSessionID else { preview = nil; return }
        if let pool = ViewModelCache.shared.get(for: sid)?.browserTabPool { pool.persistPreviewIfChanged(sessionId: sid) }
        preview = BrowserTabPool.loadPreview(for: sid)
    }

    /// Uses this Bot's own conversation so its browser and shell stay its own.
    private func openSessionThen(_ show: @escaping () -> Void) {
        if let sid = browserSessionID { resolvedSessionID = sid; show(); return }
        openingSession = true
        Task { @MainActor in
            defer { openingSession = false }
            do {
                resolvedSessionID = try await store.session(botID: botID)
                show()
            } catch { store.errorMessage = error.localizedDescription }
        }
    }

    private func refreshBrowser() {
        guard let sid = browserSessionID, let manager = ViewModelCache.shared.get(for: sid)?.browserTabPool.activeManager else {
            loadPreview()
            return
        }
        manager.reload()
        Task { @MainActor in
            // Let the reload paint before re-capturing the card's preview.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !manager.isSecureInputActive,
               let image = try? await manager.webView.takeSnapshot(configuration: nil),
               !manager.isSecureInputActive {
                manager.lastScreenshot = image
            }
            loadPreview()
        }
    }

    private func deleteBot(_ bot: BotProfile) {
        do {
            try memory.forgetOwner("bot:\(bot.id)")
            SubAgentStore.shared.removeSubAgents(ownedBy: bot.id)
            EnvVarStore.shared.deleteEntries(ownedBy: bot.id)
            store.deleteBot(bot.id)
            dismiss()
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func modelGroupBinding(_ bot: BotProfile) -> Binding<String> {
        Binding(get: { store.bot(bot.id)?.modelGroupId ?? "" }, set: { value in
            guard var current = store.bot(bot.id) else { return }
            current.modelGroupId = value.isEmpty ? nil : value
            _ = store.save(current)
        })
    }

    private func memoryBinding(_ bot: BotProfile) -> Binding<Bool> {
        Binding(get: { store.bot(bot.id)?.memoryEnabled ?? true }, set: { value in
            guard var current = store.bot(bot.id) else { return }
            current.memoryEnabled = value
            _ = store.save(current)
        })
    }

    private func enabledCount(_ overrides: [String: Bool]?, all: [(String, Bool)]) -> String {
        let on = all.filter { overrides?[$0.0] ?? $0.1 }.count
        return "\(on) / \(all.count) 已启用"
    }
}

// MARK: - Pieces

/// 群聊资料: members, memory, pin and delete — the group counterpart of BotProfileView.
struct BotRoomProfileView: View {
    let roomID: String
    @ObservedObject private var store = BotWorkspaceStore.shared
    @ObservedObject private var runner = BotRoomRunner.shared
    @ObservedObject private var memory = BotMemoryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: BotRoom?
    @State private var deleting = false

    private var room: BotRoom? { store.room(roomID) }
    private var running: Bool { runner.activeRooms.contains(roomID) }

    var body: some View {
        List {
            if let room {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.fill").font(.largeTitle).foregroundStyle(.teal)
                            .frame(width: 92, height: 92)
                            .background(Color.teal.opacity(0.18), in: Circle())
                            .accessibilityHidden(true)
                        Text(room.name).font(.title2.weight(.bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section("成员") {
                    ForEach(room.members, id: \.self) { id in
                        if let bot = store.bot(id) {
                            NavigationLink { BotProfileView(botID: bot.id) } label: {
                                HStack(spacing: 12) { BotAvatar(profile: bot, size: 32); Text(bot.name) }
                            }
                        }
                    }
                    Button { editing = room } label: { Label("编辑成员", systemImage: "person.2") }
                        .disabled(running)
                }
                Section {
                    NavigationLink { BotMemoryView(owner: "room:\(room.id)", title: room.name) } label: {
                        Label("群聊记忆", systemImage: "brain")
                    }
                    Button { store.setPinned(room.pinnedAt == nil, roomID: room.id) } label: {
                        Label(room.pinnedAt == nil ? "置顶此群聊" : "取消置顶", systemImage: room.pinnedAt == nil ? "pin" : "pin.slash")
                    }
                }
                Section {
                    Button(role: .destructive) { deleting = true } label: { Label("删除此群聊", systemImage: "trash") }
                        .disabled(running)
                }
            } else {
                Text("This Bot or group no longer exists.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("群聊资料")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { BotRoomEditor(room: $0) }
        .confirmationDialog("Delete this group, its memories and shared transcript? Member chat data is retained.",
                            isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do {
                    try memory.forgetOwner("room:\(roomID)")
                    store.deleteRoom(roomID)
                    dismiss()
                } catch { store.errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct ContentUnavailableLabel: View {
    let text: LocalizedStringKey
    var body: some View {
        Label(text, systemImage: "person.crop.circle.badge.questionmark")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One Bot's skill or connector switches (the per-Bot part of BotCapabilitySettingsView).
private struct BotCapabilityToggles: View {
    let botID: String
    let skills: Bool
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @ObservedObject private var skillStore = SkillStore.shared
    @ObservedObject private var connectorStore = MCPStore.shared

    var body: some View {
        List {
            if let bot = workspace.bot(botID) {
                Section {
                    if skills {
                        ForEach(skillStore.skills) { skill in
                            Toggle(skill.name, isOn: binding(skill.id, default: skill.isEnabled, bot: bot))
                        }
                    } else {
                        ForEach(connectorStore.servers) { server in
                            Toggle(server.id, isOn: binding(server.id, default: server.enabled, bot: bot))
                        }
                    }
                } footer: { Text("未单独设置的项目跟随全局默认值。") }
                Section {
                    Button("恢复全局默认") {
                        guard var current = workspace.bot(botID) else { return }
                        if skills { current.skillOverrides = [:] } else { current.connectorOverrides = [:] }
                        _ = workspace.save(current)
                    }
                }
            }
        }
        .navigationTitle(skills ? "技能" : "连接器 (MCP)")
    }

    private func binding(_ id: String, default value: Bool, bot: BotProfile) -> Binding<Bool> {
        Binding(get: { (skills ? workspace.bot(botID)?.skillOverrides : workspace.bot(botID)?.connectorOverrides)?[id] ?? value },
                set: { enabled in
                    guard var current = workspace.bot(botID) else { return }
                    if skills { current.skillOverrides = (current.skillOverrides ?? [:]).merging([id: enabled]) { $1 } }
                    else { current.connectorOverrides = (current.connectorOverrides ?? [:]).merging([id: enabled]) { $1 } }
                    _ = workspace.save(current)
                })
    }
}

/// "更改头像": the existing icon set plus a photo, saved immediately.
private struct BotAvatarPicker: View {
    let botID: String
    @ObservedObject private var store = BotWorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let bot = store.bot(botID) {
                    Section {
                        HStack(spacing: 16) {
                            BotAvatar(profile: bot, size: 56)
                            PhotosPicker("Choose Custom Image", selection: $selectedPhoto, matching: .images)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                            ForEach(SessionCategory.all, id: \.key) { category in
                                let selected = bot.iconImageData == nil && bot.iconSymbol == category.icon
                                Button { update { $0.iconImageData = nil; $0.iconSymbol = category.icon } } label: {
                                    Image(systemName: category.icon).font(.title3)
                                        .foregroundStyle(selected ? .white : category.color)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(selected ? category.color : category.color.opacity(0.18)))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(LocalizedStringKey(category.label)))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
                }
            }
            .navigationTitle("更改头像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        error = String(localized: "Unable to read this image.")
                        return
                    }
                    let jpeg = BotAvatarPicker.thumbnail(image)
                    update { $0.iconImageData = jpeg }
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func update(_ change: (inout BotProfile) -> Void) {
        guard var bot = store.bot(botID) else { return }
        change(&bot)
        _ = store.save(bot)
    }

    /// Same 192pt center-crop BotProfileEditor applies.
    static func thumbnail(_ image: UIImage) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let side: CGFloat = 192
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        return rendered.jpegData(compressionQuality: 0.85)
    }
}

/// "指令" editor; saving writes straight to the Bot profile.
private struct BotInstructionsEditor: View {
    let botID: String
    @ObservedObject private var store = BotWorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 220).accessibilityLabel("Instructions")
                } footer: { Text("描述这个 Bot 的角色、语气和要遵守的规则") }
            }
            .navigationTitle("指令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard var bot = store.bot(botID) else { return }
                        bot.instructions = text
                        if store.save(bot) { dismiss() }
                    }
                }
            }
            .onAppear { text = store.bot(botID)?.instructions ?? "" }
        }
    }
}

private struct BotBrowserTarget: Identifiable {
    let id: String
    let vm: AIChatViewModel
}

private struct BotBrowserHost: View {
    @ObservedObject var vm: AIChatViewModel
    var body: some View {
        BrowserSheetView(pool: vm.browserTabPool, isAgentBusy: vm.browserTabPool.isAgentBrowsing,
                         onTakeover: { vm.browserTakeoverActive = true })
    }
}

import SwiftUI
import PhotosUI

private struct BotChatTarget: Identifiable { var id: String }
private struct BotMemoryTarget: Identifiable { var id: String; var title: String }

struct BotWorkspaceView: View {
    var embedded = false
    var onOpenTerminal: (() -> Void)?
    var onOpenRootfs: (() -> Void)?
    var onOpenBrowser: (() -> Void)?
    var onBrowserSettings: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenConversation: ((String) -> Void)?
    @ObservedObject private var store = BotWorkspaceStore.shared
    @ObservedObject private var runner = BotRoomRunner.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editingBot: BotProfile?
    @State private var editingRoom: BotRoom?
    @State private var chat: BotChatTarget?
    @State private var showSearch = false
    @State private var query = ""
    @State private var botSnippets: [String: String] = [:]
    @State private var roomSnippets: [String: String] = [:]
    @FocusState private var searchFocused: Bool
    @State private var savedNewBot: BotProfile?
    @State private var opening = false
    @State private var failedBot: BotProfile?
    @State private var deletingBot: BotProfile?
    @State private var deletingRoom: BotRoom?
    @State private var memoryTarget: BotMemoryTarget?
    @ObservedObject private var memory = BotMemoryStore.shared

    var body: some View {
        Group {
            if embedded { workspaceContent }
            else { NavigationStack { workspaceContent } }
        }
    }

    private var workspaceContent: some View {
            List {
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                if opening { ProgressView("正在打开 Bot…") }
                if let failedBot {
                    Button("Retry") { open(failedBot) }.disabled(opening)
                }
                Section("Bots") {
                    ForEach(store.data.bots.filter { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || botSnippets[$0.id] != nil }) { bot in
                        Button { open(bot) } label: {
                            HStack {
                                BotAvatar(profile: bot)
                                VStack(alignment: .leading) {
                                    Text(bot.name).foregroundStyle(.primary)
                                    if let snippet = botSnippets[bot.id], !snippet.isEmpty {
                                        Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                                Spacer()
                            }.frame(minHeight: 44)
                        }
                        .accessibilityLabel(bot.name)
                        .disabled(opening)
                        .contextMenu {
                            Button("Memory") { memoryTarget = BotMemoryTarget(id: "bot:\(bot.id)", title: bot.name) }
                            Button("Edit") { editingBot = bot }
                                .disabled(!runner.activeRooms.isEmpty)
                            Button("Delete", role: .destructive) { deletingBot = bot }
                                .disabled(!runner.activeRooms.isEmpty)
                        }
                        .swipeActions(edge: .leading) { Button("Edit") { editingBot = bot }.disabled(!runner.activeRooms.isEmpty) }
                        .swipeActions { Button("Delete", role: .destructive) { deletingBot = bot }.disabled(!runner.activeRooms.isEmpty) }
                    }
                }
                Section("Groups") {
                    ForEach(store.data.rooms.filter { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || roomSnippets[$0.id] != nil }) { room in
                        NavigationLink { BotRoomView(roomID: room.id) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Label(room.name, systemImage: "person.2")
                                    if let snippet = roomSnippets[room.id], !snippet.isEmpty {
                                        Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                                Spacer()
                                if runner.activeRooms.contains(room.id) { ProgressView() }
                            }
                        }
                        .contextMenu {
                            Button("Edit") { editingRoom = room }.disabled(runner.activeRooms.contains(room.id))
                            Button("Delete", role: .destructive) { deletingRoom = room }.disabled(runner.activeRooms.contains(room.id))
                        }
                    }
                }
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && botSnippets.isEmpty && roomSnippets.isEmpty {
                    Text("没有找到匹配的 Bot、群聊或消息").foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("Shared Materials") { BotMemoryView(owner: "shared", title: "Shared Materials") }
                    Text("点击 Bot 开始对话。技能和连接器在应用设置中管理，Bot 资料和群聊记录保存在此设备。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bots & Groups")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    if showSearch {
                        HStack {
                            TextField("搜索 Bot、群聊及消息", text: $query)
                                .focused($searchFocused).autocorrectionDisabled()
                            Button { query = ""; showSearch = false } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("关闭搜索").frame(width: 44, height: 44)
                        }.padding(.leading, 12).background(.regularMaterial, in: Capsule())
                    } else {
                        Button { showSearch = true; searchFocused = true } label: {
                            Image(systemName: "magnifyingglass").font(.title2).frame(width: 56, height: 56)
                        }.accessibilityLabel("搜索 Bot、群聊及消息")
                        Spacer()
                    }
                    Menu {
                        Button("创建 Bot") { editingBot = store.newBot() }
                        Button("创建群聊") { editingRoom = BotRoom(name: "", members: []) }
                            .disabled(store.data.bots.count < 2)
                    } label: {
                        Image(systemName: "plus").font(.title2).frame(width: 56, height: 56)
                    }
                    .buttonStyle(.borderedProminent).clipShape(Circle())
                    .accessibilityLabel("创建 Bot 或群聊")
                }.padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onOpenSettings { Button(action: onOpenSettings) { Image(systemName: "gear") }.accessibilityLabel("Settings") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { onOpenTerminal?() } label: { Label("Shell Terminal", systemImage: "terminal") }
                        Button { onOpenRootfs?() } label: { Label("Rootfs Management", systemImage: "externaldrive") }
                        Divider()
                        Button { onOpenBrowser?() } label: { Label("Open Browser", systemImage: "globe") }
                        Button { onBrowserSettings?() } label: { Label("Browser Settings", systemImage: "globe.badge.chevron.backward") }
                    } label: { Image(systemName: "terminal") }
                    .accessibilityLabel("工具")
                }
            }
            .background {
                Button { showSearch = true; searchFocused = true } label: { EmptyView() }
                    .keyboardShortcut("f", modifiers: .command).hidden()
            }
            .task(id: query) { await search() }
            .sheet(item: $editingBot, onDismiss: {
                if let bot = savedNewBot { savedNewBot = nil; open(bot) }
            }) { profile in
                BotProfileEditor(profile: profile) { saved in
                    if profile.sessionId == nil { savedNewBot = saved }
                }
            }
            .sheet(item: $editingRoom) { BotRoomEditor(room: $0) }
            .sheet(item: $memoryTarget) { target in
                NavigationStack { BotMemoryView(owner: target.id, title: target.title).toolbar { Button("Done") { memoryTarget = nil } } }
            }
            .sheet(item: $chat) { target in
                NavigationStack {
                    AIChatView(sessionId: target.id)
                        .id(target.id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { chat = nil } } }
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                if let bot = store.bot(forSession: target.id) {
                                    HStack {
                                        NavigationLink { BotMemoryView(owner: "bot:\(bot.id)", title: bot.name) }
                                        label: { Image(systemName: "brain") }
                                        .accessibilityLabel("Memory")
                                    }
                                }
                            }
                        }
                        .safeAreaInset(edge: .bottom) {
                            if let entry = memory.lastSaved, entry.sourceSession == target.id, store.owner(forSession: target.id)?.memoryKey == entry.owner {
                                HStack {
                                    Text("Remembered: \(entry.content)").font(.caption).lineLimit(2)
                                    Button("Undo") {
                                        do { try memory.forget(id: entry.id, owner: entry.owner) }
                                        catch { store.errorMessage = error.localizedDescription }
                                    }
                                }.padding(8).background(.regularMaterial)
                            }
                        }
                }
            }
            .confirmationDialog("Delete Bot and its memories? Shared access to its memories will be removed. Chat data is retained.", isPresented: Binding(get: { deletingBot != nil }, set: { if !$0 { deletingBot = nil } })) {
                Button("Delete", role: .destructive) {
                    if let deletingBot {
                        do { try memory.forgetOwner("bot:\(deletingBot.id)"); store.deleteBot(deletingBot.id) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                    deletingBot = nil
                }
            }
            .confirmationDialog("Delete this group, its memories and shared transcript? Member chat data is retained.", isPresented: Binding(get: { deletingRoom != nil }, set: { if !$0 { deletingRoom = nil } })) {
                Button("Delete", role: .destructive) {
                    if let deletingRoom {
                        do { try memory.forgetOwner("room:\(deletingRoom.id)"); store.deleteRoom(deletingRoom.id) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                    deletingRoom = nil
                }
            }
    }

    private func search() async {
        let terms = SearchKeywords.terms(query)
        guard !terms.isEmpty else { botSnippets = [:]; roomSnippets = [:]; return }
        let results = await ChatStore.shared.searchSessions(query: query)
        guard !Task.isCancelled else { return }
        let matches = BotWorkspaceSearch.matches(data: store.data, terms: terms,
            hits: results.compactMap { result in
                result.matchSnippet.map { BotWorkspaceSearch.Hit(sessionID: result.session.id, snippet: $0) }
            })
        botSnippets = matches.bots
        roomSnippets = matches.rooms
    }


    private func open(_ bot: BotProfile) {
        failedBot = nil
        opening = true
        Task { @MainActor in
            defer { opening = false }
            do {
                let id = try await store.session(botID: bot.id)
                if let onOpenConversation { onOpenConversation(id) }
                else { chat = BotChatTarget(id: id) }
            }
            catch { failedBot = bot; store.errorMessage = error.localizedDescription }
        }
    }
}

struct BotProfileEditor: View {
    @State var profile: BotProfile
    var onSave: ((BotProfile) -> Void)? = nil
    @ObservedObject private var store = BotWorkspaceStore.shared
    @ObservedObject private var providers = ProviderConfigStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var iconError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $profile.name)
                Section("Bot Icon") {
                    HStack {
                        BotAvatar(profile: profile)
                        PhotosPicker("Choose Custom Image", selection: $selectedPhoto, matching: .images)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                        ForEach(SessionCategory.all, id: \.key) { category in
                            let symbol = category.icon
                            Button {
                                selectedPhoto = nil
                                profile.iconImageData = nil
                                profile.iconSymbol = symbol
                            } label: {
                                let selected = profile.iconImageData == nil && profile.iconSymbol == symbol
                                VStack(spacing: 6) {
                                    Image(systemName: symbol)
                                        .font(.system(size: 20))
                                        .foregroundStyle(selected ? .white : category.color)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(selected ? category.color : category.color.opacity(0.12)))
                                    Text(LocalizedStringKey(category.label))
                                        .font(.caption2)
                                        .foregroundStyle(selected ? category.color : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(LocalizedStringKey(category.label)))
                            .accessibilityAddTraits(profile.iconImageData == nil && profile.iconSymbol == symbol ? .isSelected : [])
                        }
                    }
                    if let iconError { Text(iconError).foregroundStyle(.red) }
                }
                Section("Instructions") { TextEditor(text: $profile.instructions).frame(minHeight: 120) }
                Picker("Model Group", selection: Binding(get: { profile.modelGroupId ?? "" }, set: { profile.modelGroupId = $0.isEmpty ? nil : $0 })) {
                    Text("Default Model Group").tag("")
                    ForEach(providers.modelGroups) { group in Text(group.name).tag(group.id) }
                }
                Toggle("启用此 Bot 的长期记忆", isOn: Binding(get: { profile.memoryEnabled ?? true }, set: { profile.memoryEnabled = $0 }))
                Section("Agent 运行时") {
                    NavigationLink("Agent 工具") { ToolsSettingsView() }
                    NavigationLink("子代理") { HelperSettingsView() }
                    NavigationLink("长期记忆") { BotMemoryView(owner: "bot:\(profile.id)", title: profile.name) }
                    NavigationLink("定时任务") { ScheduledTasksManagementView(botID: profile.id) }
                    NavigationLink("环境变量") { EnvironmentVariablesView() }
                    Text("工具、子代理和环境变量沿用应用共享配置；记忆与定时任务仅显示此 Bot 的内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("技能和连接器请在应用设置中管理。模型组作为首次打开 Bot 的默认值。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit Bot")
            .task {
                if profile.memoryEnabled == nil, let sid = profile.sessionId {
                    let legacy = await ChatStore.shared.getMemoryEnabled(sessionId: sid)
                    if profile.memoryEnabled == nil { profile.memoryEnabled = legacy }
                }
            }
            .onAppear {
                if let sid = profile.sessionId {
                    if profile.skillOverrides == nil { profile.skillOverrides = Dictionary(uniqueKeysWithValues: SkillStore.shared.skills.map { ($0.id, SkillStore.shared.isEnabledForSession($0.id, sessionId: sid)) }) }
                    if profile.connectorOverrides == nil { profile.connectorOverrides = Dictionary(uniqueKeysWithValues: MCPStore.shared.servers.map { ($0.id, MCPStore.shared.isEnabledForSession($0.id, sessionId: sid)) }) }
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        iconError = String(localized: "Unable to read this image.")
                        return
                    }
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    let size = CGSize(width: 192, height: 192)
                    let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        let scale = max(size.width / image.size.width, size.height / image.size.height)
                        let width = image.size.width * scale, height = image.size.height * scale
                        image.draw(in: CGRect(x: (192 - width) / 2, y: (192 - height) / 2, width: width, height: height))
                    }
                    try Task.checkCancellation()
                    profile.iconImageData = thumbnail.jpegData(compressionQuality: 0.85)
                    iconError = nil
                } catch is CancellationError { } catch { iconError = error.localizedDescription }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.save(profile) { onSave?(profile); dismiss() } }
                        .disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

        }
    }
}

private struct BotRoomEditor: View {
    @State var room: BotRoom
    @ObservedObject private var store = BotWorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                TextField("Group Name", text: $room.name)
                Toggle("启用此群组的长期记忆", isOn: Binding(get: { room.memoryEnabled ?? true }, set: { room.memoryEnabled = $0 }))
                Section("Speaking Order") {
                    ForEach(room.members, id: \.self) { id in
                        if let bot = store.bot(id) { Text(bot.name) }
                    }
                    .onMove { room.members.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { room.members.remove(atOffsets: $0) }
                }
                Section("Add Members") {
                    ForEach(store.data.bots.filter { !room.members.contains($0.id) }) { bot in
                        Button(bot.name) { room.members.append(bot.id) }
                    }
                }
                Section {
                    Text("Each user message starts one round. All selected members reply once in order and see earlier replies. Private chats are not shared. You can stop a round at any time.")
                        .font(.footnote)
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Group")
            .task {
                if room.memoryEnabled == nil, let sid = room.sessions.values.sorted().first {
                    let legacy = await ChatStore.shared.getMemoryEnabled(sessionId: sid)
                    if room.memoryEnabled == nil { room.memoryEnabled = legacy }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.save(room) { dismiss() } }
                        .disabled(room.members.count < 2 || room.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct BotRoomView: View {
    let roomID: String
    @ObservedObject private var store = BotWorkspaceStore.shared
    @ObservedObject private var runner = BotRoomRunner.shared
    @ObservedObject private var memory = BotMemoryStore.shared
    @State private var input = ""
    @State private var recipient = ""
    @State private var editing: BotRoom?
    @State private var chat: BotChatTarget?
    private var room: BotRoom? { store.room(roomID) }
    private var isRunning: Bool { runner.activeRooms.contains(roomID) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if room?.messages.isEmpty == true { Text("Send a message to start a group round.").foregroundStyle(.secondary) }
                        ForEach(room?.messages ?? []) { message in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(message.speaker).font(.headline)
                                    Text(message.date, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(message.text).textSelection(.enabled)
                                if let sessionID = message.sessionId {
                                    Button("View Tools and Conversation") { chat = BotChatTarget(id: sessionID) }.font(.caption)
                                }
                            }.id(message.id)
                        }
                        if let speaker = runner.speakers[roomID] { ProgressView("\(speaker) is working…") }
                        if room?.interrupted == true && !isRunning {
                            Text("The previous round was interrupted. Send a new message to continue.").foregroundStyle(.secondary)
                        }
                        if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                    }.padding()
                }
                .onChange(of: room?.messages.count) { _ in
                    if let last = room?.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            VStack {
                Picker("Recipients", selection: $recipient) {
                    Text("All Members").tag("")
                    ForEach(room?.members ?? [], id: \.self) { id in Text(store.bot(id)?.name ?? id).tag(id) }
                }.disabled(isRunning)
                HStack(alignment: .bottom) {
                    TextField("Message", text: $input, axis: .vertical).lineLimit(1...6)
                    if isRunning { Button("Stop", role: .destructive) { runner.stop(roomID) } }
                    else {
                        Button("Send") {
                            runner.send(input, roomID: roomID, recipient: recipient.isEmpty ? nil : recipient)
                            if runner.activeRooms.contains(roomID) { input = "" }
                        }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || room?.members.isEmpty != false)
                    }
                }
            }.padding()
        }
        .navigationTitle(room?.name ?? String(localized: "Group"))
        .safeAreaInset(edge: .bottom) {
            if let entry = memory.lastSaved, entry.owner == "room:\(roomID)" {
                HStack {
                    Text("Remembered: \(entry.content)").font(.caption).lineLimit(2)
                    Button("Undo") {
                        do { try memory.forget(id: entry.id, owner: entry.owner) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                }.padding(8).background(.regularMaterial)
            }
        }
        .toolbar {
            Button("Members") { editing = room }.disabled(isRunning)
            NavigationLink("Memory") { BotMemoryView(owner: "room:\(roomID)", title: room?.name ?? "Group Memory") }
        }
        .sheet(item: $editing) { BotRoomEditor(room: $0) }
        .sheet(item: $chat) { target in
            NavigationStack {
                AIChatView(sessionId: target.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { chat = nil } } }
            }
        }
    }
}

struct BotAvatar: View {
    let profile: BotProfile
    var size: CGFloat = 32
    private var iconColor: Color {
        SessionCategory.all.first { $0.icon == profile.iconSymbol }?.color ?? .green
    }
    var body: some View {
        Group {
            if let data = profile.iconImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: profile.iconSymbol ?? "bubble.left.fill")
                    .resizable().scaledToFit().padding(7)
                    .foregroundStyle(iconColor)
                    .background(iconColor.opacity(0.12), in: Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

struct BotConversationPicker: View {
    var excludedSessionID: String? = nil
    var onSelect: (String) -> Void
    @ObservedObject private var store = BotWorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newBot: BotProfile?
    @State private var savedBot: BotProfile?
    @State private var opening = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.data.bots.filter { excludedSessionID == nil || $0.sessionId != excludedSessionID }) { bot in
                        Button {
                            opening = true
                            Task { @MainActor in
                                defer { opening = false }
                                do {
                                    let id = try await store.session(botID: bot.id)
                                    onSelect(id)
                                } catch { self.error = error.localizedDescription }
                            }
                        } label: { Label { Text(bot.name) } icon: { BotAvatar(profile: bot) } }
                        .disabled(opening)
                    }
                    Button { newBot = store.newBot() } label: { Label("Create Bot", systemImage: "plus") }
                        .disabled(opening)
                } footer: { Text("Choose a Bot before starting a conversation") }
                if opening { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Choose Bot")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(opening) } }
            .sheet(item: $newBot, onDismiss: {
                guard let bot = savedBot else { return }
                savedBot = nil
                opening = true
                Task { @MainActor in
                    defer { opening = false }
                    do { onSelect(try await store.session(botID: bot.id)) }
                    catch { self.error = error.localizedDescription }
                }
            }) { BotProfileEditor(profile: $0, onSave: { savedBot = $0 }) }
            .interactiveDismissDisabled(opening)
        }
    }
}


struct BotCapabilitySettingsView: View {
    let skills: Bool
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @ObservedObject private var skillStore = SkillStore.shared
    @ObservedObject private var connectorStore = MCPStore.shared

    var body: some View {
        List {
            if workspace.data.bots.isEmpty { Text("请先创建 Bot") }
            ForEach(workspace.data.bots) { bot in
                Section(bot.name) {
                    if skills {
                        ForEach(skillStore.skills) { skill in
                            Toggle(skill.name, isOn: Binding(
                                get: { bot.skillOverrides?[skill.id] ?? skill.isEnabled },
                                set: { value in update(bot.id, capability: skill.id, enabled: value) }
                            ))
                        }
                    } else {
                        ForEach(connectorStore.servers) { server in
                            Toggle(server.id, isOn: Binding(
                                get: { bot.connectorOverrides?[server.id] ?? server.enabled },
                                set: { value in update(bot.id, capability: server.id, enabled: value) }
                            ))
                        }
                    }
                    Button("恢复全局默认") {
                        guard var current = workspace.bot(bot.id) else { return }
                        if skills { current.skillOverrides = [:] }
                        else { current.connectorOverrides = [:] }
                        _ = workspace.save(current)
                    }
                }
            }
            if let error = workspace.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(skills ? LocalizedStringKey("Bot 技能配置") : LocalizedStringKey("Bot 连接器配置"))
    }

    private func update(_ botID: String, capability: String, enabled: Bool) {
        guard var bot = workspace.bot(botID) else { return }
        if skills {
            var overrides = bot.skillOverrides ?? [:]
            overrides[capability] = enabled
            bot.skillOverrides = overrides
        } else {
            var overrides = bot.connectorOverrides ?? [:]
            overrides[capability] = enabled
            bot.connectorOverrides = overrides
        }
        _ = workspace.save(bot)
    }
}

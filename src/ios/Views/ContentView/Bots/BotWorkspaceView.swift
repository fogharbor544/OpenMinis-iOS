import SwiftUI
import PhotosUI

private struct BotChatTarget: Identifiable { var id: String }
private struct BotMemoryTarget: Identifiable { var id: String; var title: String }

struct BotWorkspaceView: View {
    var embedded = false
    var historicalSessions: [ChatSession] = []
    var sessionSnapshots: [ChatSession]? = nil
    var sessionMenuActions: SessionMenuActionChannel? = nil
    var onShowHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onNewConversation: (() -> Void)?
    var onOpenConversation: ((String) -> Void)?
    @ObservedObject private var store = BotWorkspaceStore.shared
    @ObservedObject private var runner = BotRoomRunner.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editingBot: BotProfile?
    @State private var editingRoom: BotRoom?
    @State private var chat: BotChatTarget?
    @State private var expandedBots: Set<String> = []
    @State private var opening = false
    @State private var deletingBot: BotProfile?
    @State private var deletingRoom: BotRoom?
    @State private var memoryTarget: BotMemoryTarget?
    @State private var conversationsBot: BotProfile?
    @State private var selectedConversation: String?
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
                Section("Bots") {
                    ForEach(store.data.bots) { bot in
                        Button {
                            if expandedBots.contains(bot.id) { expandedBots.remove(bot.id) }
                            else { expandedBots.insert(bot.id) }
                        } label: {
                            HStack {
                                BotAvatar(profile: bot)
                                Text(bot.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: expandedBots.contains(bot.id) ? "chevron.down" : "chevron.right").foregroundStyle(.secondary)
                            }.frame(minHeight: 44)
                        }
                        .accessibilityLabel("\(bot.name)，\(expandedBots.contains(bot.id) ? "收起会话" : "展开会话")")
                        .disabled(opening)
                        .contextMenu {
                            Button("New Conversation") { open(bot, newConversation: true) }
                            Button("Conversations") { conversationsBot = bot }
                            Button("Memory") { memoryTarget = BotMemoryTarget(id: "bot:\(bot.id)", title: bot.name) }
                            Button("Edit") { editingBot = bot }
                                .disabled(!runner.activeRooms.isEmpty)
                            Button("Delete", role: .destructive) { deletingBot = bot }
                                .disabled(!runner.activeRooms.isEmpty)
                        }
                        .swipeActions(edge: .leading) { Button("Edit") { editingBot = bot }.disabled(!runner.activeRooms.isEmpty) }
                        .swipeActions { Button("Delete", role: .destructive) { deletingBot = bot }.disabled(!runner.activeRooms.isEmpty) }
                        if expandedBots.contains(bot.id) {
                            BotConversationRows(bot: bot, menuActions: sessionMenuActions, snapshots: sessionSnapshots, onOpen: { id in
                                if let onOpenConversation { onOpenConversation(id) }
                                else { chat = BotChatTarget(id: id) }
                            }, onCreate: { open(bot, newConversation: true) })
                        }
                    }
                }
                Section("Groups") {
                    ForEach(store.data.rooms) { room in
                        NavigationLink { BotRoomView(roomID: room.id) } label: {
                            HStack {
                                Label(room.name, systemImage: "person.2")
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
                if !historicalSessions.isEmpty {
                    Section("历史会话") {
                        ForEach(historicalSessions) { session in
                            Button {
                                if let onOpenConversation { onOpenConversation(session.id) }
                                else { chat = BotChatTarget(id: session.id) }
                            } label: { SessionRow(session: session).equatable() }
                            .contextMenu {
                                if let sessionMenuActions {
                                    SessionContextMenu(key: MenuKey(sid: session.id, pinned: session.isPinned, title: session.title, filed: session.isFiled), actions: sessionMenuActions)
                                }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink("Shared Materials") { BotMemoryView(owner: "shared", title: "Shared Materials") }
                    Text("Bots use OpenMinis model groups, skills, MCP servers and device permissions. Expand a Bot to see its conversations. Bot profiles and group transcripts are stored on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bots & Groups")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Menu {
                        Button("创建 Bot") { editingBot = store.newBot() }
                        Button("创建群聊") { editingRoom = BotRoom(name: "", members: []) }
                            .disabled(store.data.bots.count < 2)
                    } label: {
                        Image(systemName: "plus").font(.title2).frame(width: 56, height: 56)
                    }
                    .buttonStyle(.borderedProminent).clipShape(Circle())
                    .accessibilityLabel("创建 Bot 或群聊")
                    Spacer()
                }.padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onOpenSettings { Button(action: onOpenSettings) { Image(systemName: "gear") }.accessibilityLabel("Settings") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !embedded { Button("Done") { dismiss() } }
                }
            }
            .sheet(item: $editingBot) { BotProfileEditor(profile: $0) }
            .sheet(item: $editingRoom) { BotRoomEditor(room: $0) }
            .sheet(item: $memoryTarget) { target in
                NavigationStack { BotMemoryView(owner: target.id, title: target.title).toolbar { Button("Done") { memoryTarget = nil } } }
            }
            .sheet(item: $conversationsBot, onDismiss: {
                if let id = selectedConversation {
                    selectedConversation = nil
                    if let onOpenConversation { onOpenConversation(id) }
                    else { chat = BotChatTarget(id: id) }
                }
            }) { bot in
                BotConversationsView(botID: bot.id) { id in selectedConversation = id }
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
                                        Button { open(bot, newConversation: true) } label: { Image(systemName: "square.and.pencil") }
                                            .accessibilityLabel("New Conversation")
                                            .disabled(opening)
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
            .confirmationDialog("Delete Bot and its memories? Shared access to its memories will be removed. Conversations remain in History.", isPresented: Binding(get: { deletingBot != nil }, set: { if !$0 { deletingBot = nil } })) {
                Button("Delete", role: .destructive) {
                    if let deletingBot {
                        do { try memory.forgetOwner("bot:\(deletingBot.id)"); store.deleteBot(deletingBot.id) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                    deletingBot = nil
                }
            }
            .confirmationDialog("Delete this group, its memories and shared transcript? Member conversations remain in History.", isPresented: Binding(get: { deletingRoom != nil }, set: { if !$0 { deletingRoom = nil } })) {
                Button("Delete", role: .destructive) {
                    if let deletingRoom {
                        do { try memory.forgetOwner("room:\(deletingRoom.id)"); store.deleteRoom(deletingRoom.id) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                    deletingRoom = nil
                }
            }
    }

    private func open(_ bot: BotProfile, newConversation: Bool = false) {
        opening = true
        Task { @MainActor in
            defer { opening = false }
            do {
                let id = try await store.session(botID: bot.id, newConversation: newConversation)
                if let onOpenConversation { onOpenConversation(id) }
                else { chat = BotChatTarget(id: id) }
            }
            catch { store.errorMessage = error.localizedDescription }
        }
    }
}

private struct BotProfileEditor: View {
    @State var profile: BotProfile
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) {
                        ForEach(BotProfile.builtinIcons, id: \.self) { symbol in
                            Button {
                                selectedPhoto = nil
                                profile.iconImageData = nil
                                profile.iconSymbol = symbol
                            } label: {
                                Image(systemName: symbol).frame(width: 44, height: 44)
                                    .background(profile.iconImageData == nil && profile.iconSymbol == symbol ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
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
                Section("Skills") {
                    ForEach(SkillStore.shared.skills) { skill in
                        Toggle(skill.name, isOn: Binding(get: { profile.skillOverrides?[skill.id] ?? skill.isEnabled }, set: { profile.skillOverrides = (profile.skillOverrides ?? [:]).merging([skill.id: $0]) { _, new in new } }))
                    }
                }
                Section("连接器") {
                    ForEach(MCPStore.shared.servers) { server in
                        Toggle(server.id, isOn: Binding(get: { profile.connectorOverrides?[server.id] ?? server.enabled }, set: { profile.connectorOverrides = (profile.connectorOverrides ?? [:]).merging([server.id: $0]) { _, new in new } }))
                    }
                }
                Section("Agent 运行时") {
                    NavigationLink("Agent 工具") { ToolsSettingsView() }
                    NavigationLink("子代理") { HelperSettingsView() }
                    NavigationLink("长期记忆") { BotMemoryView(owner: "bot:\(profile.id)", title: profile.name) }
                    NavigationLink("定时任务") { ScheduledTasksManagementView(botID: profile.id) }
                    NavigationLink("环境变量") { EnvironmentVariablesView() }
                    Text("工具、子代理和环境变量沿用应用共享配置；记忆与定时任务仅显示此 Bot 的内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("技能和连接器设置适用于此 Bot 的全部私聊和群聊。模型选择作为新会话的默认值，已有会话的临时覆盖不会被改写。")
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
                    Button("Save") { if store.save(profile) { dismiss() } }
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
    var body: some View {
        Group {
            if let data = profile.iconImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: profile.iconSymbol ?? "sparkles").resizable().scaledToFit().padding(5)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

struct BotConversationPicker: View {
    var onSelect: (String) -> Void
    @ObservedObject private var store = BotWorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newBot: BotProfile?
    @State private var opening = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.data.bots) { bot in
                        Button {
                            opening = true
                            Task { @MainActor in
                                defer { opening = false }
                                do {
                                    let id = try await store.session(botID: bot.id, newConversation: true)
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
            .sheet(item: $newBot) { BotProfileEditor(profile: $0) }
            .interactiveDismissDisabled(opening)
        }
    }
}

private struct BotConversationRows: View {
    let bot: BotProfile
    var menuActions: SessionMenuActionChannel?
    var snapshots: [ChatSession]?
    var onOpen: (String) -> Void
    var onCreate: () -> Void
    @State private var conversations: [ChatSession] = []
    @State private var loading = true
    private var visibleConversations: [ChatSession] {
        let ids = Set(bot.conversationIds + [bot.sessionId].compactMap { $0 })
        return (snapshots ?? conversations).filter { ids.contains($0.id) }
            .sorted { $0.isPinned != $1.isPinned ? $0.isPinned : $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        Group {
            if loading && snapshots == nil { ProgressView().padding(.leading, 40) }
            else if visibleConversations.isEmpty {
                Button(action: onCreate) { Label("创建新会话", systemImage: "plus.bubble") }.padding(.leading, 40)
            } else {
                ForEach(visibleConversations) { session in
                    Button { onOpen(session.id) } label: {
                        SessionRow(session: session).equatable()
                    }.padding(.leading, 40)
                    .contextMenu {
                        if let menuActions {
                            SessionContextMenu(key: MenuKey(sid: session.id, pinned: session.isPinned, title: session.title, filed: session.isFiled), actions: menuActions)
                        }
                    }
                }
            }
        }
        .task(id: bot.conversationIds) {
            guard snapshots == nil else { return }
            var loaded: [ChatSession] = []
            for id in Set(bot.conversationIds + [bot.sessionId].compactMap { $0 }) {
                if let session = await ChatStore.shared.getSession(id) { loaded.append(session) }
            }
            guard !Task.isCancelled else { return }
            conversations = loaded.sorted { $0.isPinned != $1.isPinned ? $0.isPinned : $0.updatedAt > $1.updatedAt }
            loading = false
        }
    }
}

import SwiftUI
import PhotosUI

private struct BotChatTarget: Identifiable { var id: String }

struct BotWorkspaceView: View {
    var embedded = false
    var onOpenTerminal: (() -> Void)?
    var onOpenRootfs: (() -> Void)?
    var onOpenBrowser: (() -> Void)?
    var onBrowserSettings: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenConversation: ((String) -> Void)?
    /// The home screen's already-loaded session list. Row previews read from it
    /// so this view adds no store reads of its own: ContentView's refresh is
    /// already throttled, cooldown-gated and deferred during scrolling.
    var sessions: [ChatSession] = []
    @ObservedObject private var store = BotWorkspaceStore.shared
    @ObservedObject private var runner = BotRoomRunner.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingBot: BotProfile?
    @State private var editingRoom: BotRoom?
    @State private var chat: BotChatTarget?
    @State private var showSearch = false
    @State private var query = ""
    @State private var searchedQuery = ""
    @State private var botSnippets: [String: String] = [:]
    @State private var roomSnippets: [String: String] = [:]
    @FocusState private var searchFocused: Bool
    @State private var savedNewBot: BotProfile?
    @State private var openingBotID: String?
    @State private var failedBot: BotProfile?
    @ObservedObject private var memory = BotMemoryStore.shared
    @State private var profileBot: BotChatTarget?
    @State private var profileRoom: BotChatTarget?

    private var opening: Bool { openingBotID != nil }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isWorkspaceEmpty: Bool { store.data.bots.isEmpty && store.data.rooms.isEmpty }
    private var visibleBots: [BotProfile] {
        store.data.bots.filter { trimmedQuery.isEmpty || botSnippets[$0.id] != nil }
    }
    private var visibleRooms: [BotRoom] {
        store.data.rooms.filter { trimmedQuery.isEmpty || roomSnippets[$0.id] != nil }
    }

    var body: some View {
        Group {
            if embedded { workspaceContent }
            else { NavigationStack { workspaceContent } }
        }
    }

    /// One row of the mixed home list. Pinned rows first (latest pin on top),
    /// then everything else by last activity, like the reference chat list.
    private enum HomeItem: Identifiable {
        case bot(BotProfile)
        case room(BotRoom)
        var id: String {
            switch self {
            case .bot(let bot): return "bot:\(bot.id)"
            case .room(let room): return "room:\(room.id)"
            }
        }
        var pinnedAt: Date? {
            switch self {
            case .bot(let bot): return bot.pinnedAt
            case .room(let room): return room.pinnedAt
            }
        }
    }

    /// Each Bot's main conversation, keyed by session id. Built once per body pass.
    private var botPreviews: [String: ChatSession] {
        let ids = Set(store.data.bots.compactMap(\.sessionId))
        guard !ids.isEmpty else { return [:] }
        return Dictionary(sessions.lazy.filter { ids.contains($0.id) }.map { ($0.id, $0) }) { first, _ in first }
    }

    private func homeItems(_ previews: [String: ChatSession]) -> [HomeItem] {
        let items = visibleBots.map(HomeItem.bot) + visibleRooms.map(HomeItem.room)
        return items.sorted { lhs, rhs in
            switch (lhs.pinnedAt, rhs.pinnedAt) {
            case let (l?, r?): return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lastActivity(lhs, previews) > lastActivity(rhs, previews)
            }
        }
    }

    private func lastActivity(_ item: HomeItem, _ previews: [String: ChatSession]) -> Date {
        switch item {
        case .bot(let bot): return bot.sessionId.flatMap { previews[$0]?.updatedAt } ?? .distantPast
        case .room(let room): return room.messages.last?.date ?? .distantPast
        }
    }

    private var workspaceContent: some View { workspaceList(previews: botPreviews) }

    private func workspaceList(previews: [String: ChatSession]) -> some View {
            List {
                if showSearch {
                    Section { searchField }
                }
                if store.errorMessage != nil || failedBot != nil {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 6) {
                                if let error = store.errorMessage { Text(error) }
                                if let failedBot {
                                    Button("Retry") { open(failedBot) }
                                        .buttonStyle(.borderless)
                                        .disabled(opening)
                                }
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
                if isWorkspaceEmpty {
                    Section { emptyState.listRowBackground(Color.clear) }
                }
                ForEach(homeItems(previews)) { item in
                    switch item {
                    case .bot(let bot): botRow(bot, preview: bot.sessionId.flatMap { previews[$0] })
                    case .room(let room): roomRow(room)
                    }
                }
                .listRowSeparator(.hidden)
                if !trimmedQuery.isEmpty && searchedQuery == query && visibleBots.isEmpty && visibleRooms.isEmpty {
                    Label("没有找到匹配的 Bot、群聊或消息", systemImage: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Bots & Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onOpenSettings { Button(action: onOpenSettings) { Image(systemName: "gear") }.accessibilityLabel("Settings") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { onOpenTerminal?() } label: { Label("Shell Terminal", systemImage: "terminal") }
                        Button { onOpenRootfs?() } label: { Label("Rootfs Management", systemImage: "externaldrive") }
                        Divider()
                        Button { onOpenBrowser?() } label: { Label("Open Browser", systemImage: "globe") }
                        Button { onBrowserSettings?() } label: { Label("Browser Settings", systemImage: "globe.badge.chevron.backward") }
                    } label: { Image(systemName: "terminal") }
                    .accessibilityLabel("工具")
                    Button { showSearch ? closeSearch() : openSearch() } label: { Image(systemName: "magnifyingglass") }
                        .disabled(isWorkspaceEmpty)
                        .accessibilityLabel("搜索 Bot、群聊及消息")
                    createMenu
                }
            }
            .background {
                Button { openSearch() } label: { EmptyView() }
                    .keyboardShortcut("f", modifiers: .command).hidden()
                    .disabled(isWorkspaceEmpty)
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
            .sheet(item: $profileBot) { target in
                NavigationStack {
                    BotProfileView(botID: target.id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { profileBot = nil } } }
                }
            }
            .sheet(item: $profileRoom) { target in
                NavigationStack {
                    BotRoomProfileView(roomID: target.id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { profileRoom = nil } } }
                }
            }
            .sheet(item: $chat) { target in
                NavigationStack {
                    AIChatView(sessionId: target.id)
                        .id(target.id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { chat = nil } } }
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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("创建你的第一个 Bot").font(.title3.weight(.semibold))
            Text("Bot 保存名称、指令和默认模型。创建后即可开始对话，两个以上 Bot 可组成群聊。")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { editingBot = store.newBot() } label: {
                Label("创建 Bot", systemImage: "plus").frame(minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    /// Shared row chrome: 54pt avatar, name + time on one line, preview below.
    private func homeRow<Avatar: View, Status: View>(name: String, tag: String?, pinned: Bool, date: Date?,
                                                     subtitle: String?, busy: Bool,
                                                     @ViewBuilder avatar: () -> Avatar,
                                                     @ViewBuilder status: () -> Status) -> some View {
        HStack(spacing: 12) {
            avatar()
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    if let tag {
                        Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(.teal)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.teal.opacity(0.15), in: Capsule())
                    }
                    if pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("已置顶")
                    }
                    Spacer(minLength: 8)
                    if busy { ProgressView().controlSize(.small) }
                    else if let date { Text(Self.rowDate(date)).font(.footnote).foregroundStyle(.secondary) }
                }
                status()
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Today → time, this week → weekday, else month/day (matches the reference list).
    private static func rowDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.defaultDigits).day())
    }

    private func botRow(_ bot: BotProfile, preview: ChatSession?) -> some View {
        let subtitle = botSnippets[bot.id].flatMap { $0.isEmpty ? nil : $0 }
            ?? preview?.lastMessage
            ?? bot.instructions.split(whereSeparator: \.isNewline).first.map(String.init)
        return Button { open(bot) } label: {
            homeRow(name: bot.name, tag: nil, pinned: bot.pinnedAt != nil, date: preview?.updatedAt,
                    subtitle: subtitle, busy: openingBotID == bot.id,
                    avatar: { BotAvatar(profile: bot, size: 54) },
                    status: { BotRunStatusView(botID: bot.id, hidesWhenIdle: true) })
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开对话")
        .disabled(opening)
        .contextMenu {
            Button { profileBot = BotChatTarget(id: bot.id) } label: { Label("Bot 资料", systemImage: "person.text.rectangle") }
            pinButton(pinned: bot.pinnedAt != nil, noun: "Bot") { store.setPinned(bot.pinnedAt == nil, botID: bot.id) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            pinButton(pinned: bot.pinnedAt != nil, noun: "Bot") { store.setPinned(bot.pinnedAt == nil, botID: bot.id) }
                .tint(.blue)
        }
    }

    private func roomRow(_ room: BotRoom) -> some View {
        let running = runner.activeRooms.contains(room.id)
        let members = ListFormatter.localizedString(byJoining: room.members.compactMap { store.bot($0)?.name })
        let last = room.messages.last
        let subtitle = roomSnippets[room.id].flatMap { $0.isEmpty ? nil : $0 }
            ?? last.map { "\($0.speaker)：\($0.text)" } ?? members
        return NavigationLink { BotRoomView(roomID: room.id) } label: {
            homeRow(name: room.name, tag: "群聊", pinned: room.pinnedAt != nil, date: last?.date,
                    subtitle: subtitle, busy: running,
                    avatar: {
                        Image(systemName: "person.2.fill")
                            .font(.title3)
                            .foregroundStyle(.teal)
                            .frame(width: 54, height: 54)
                            .background(Color.teal.opacity(0.18), in: Circle())
                            .accessibilityHidden(true)
                    },
                    status: { EmptyView() })
        }
        .contextMenu {
            Button { profileRoom = BotChatTarget(id: room.id) } label: { Label("群聊资料", systemImage: "person.2.badge.gearshape") }
            pinButton(pinned: room.pinnedAt != nil, noun: "群聊") { store.setPinned(room.pinnedAt == nil, roomID: room.id) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            pinButton(pinned: room.pinnedAt != nil, noun: "群聊") { store.setPinned(room.pinnedAt == nil, roomID: room.id) }
                .tint(.blue)
        }
    }

    private func pinButton(pinned: Bool, noun: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(pinned ? "取消置顶" : "置顶此 \(noun)", systemImage: pinned ? "pin.slash.fill" : "pin.fill")
        }
    }

    private var createMenu: some View {
        Menu {
            Button { editingBot = store.newBot() } label: { Label("创建 Bot", systemImage: "person.crop.circle.badge.plus") }
            Button { editingRoom = BotRoom(name: "", members: []) } label: {
                // A second Text renders as the menu item's subtitle.
                Label("创建群聊", systemImage: "person.2")
                if store.data.bots.count < 2 { Text("至少需要 2 个 Bot") }
            }
            .disabled(store.data.bots.count < 2)
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("创建 Bot 或群聊")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("搜索 Bot、群聊及消息", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
            Button { closeSearch() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭搜索")
        }
        .transition(.opacity)
    }

    private func openSearch() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showSearch = true }
        searchFocused = true
    }

    private func closeSearch() {
        query = ""
        searchFocused = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showSearch = false }
    }

    private func search() async {
        let terms = SearchKeywords.terms(query)
        guard !terms.isEmpty else { botSnippets = [:]; roomSnippets = [:]; searchedQuery = query; return }
        // Debounce typing; `.task(id:)` cancels this when the query changes again.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        let results = await ChatStore.shared.searchSessions(query: query)
        guard !Task.isCancelled else { return }
        let matches = BotWorkspaceSearch.matches(data: store.data, terms: terms,
            hits: results.compactMap { result in
                result.matchSnippet.map { BotWorkspaceSearch.Hit(sessionID: result.session.id, snippet: $0) }
            })
        botSnippets = matches.bots
        roomSnippets = matches.rooms
        searchedQuery = query
    }


    private func open(_ bot: BotProfile) {
        failedBot = nil
        openingBotID = bot.id
        Task { @MainActor in
            defer { openingBotID = nil }
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
                Section("Name") {
                    TextField("Name", text: $profile.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                }
                Section("Bot Icon") {
                    HStack(spacing: 16) {
                        BotAvatar(profile: profile, size: 56)
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
                                        .font(.title3)
                                        .foregroundStyle(selected ? .white : category.color)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(selected ? category.color : category.color.opacity(0.18)))
                                    Text(LocalizedStringKey(category.label))
                                        .font(.caption2)
                                        .foregroundStyle(selected ? category.color : .secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(LocalizedStringKey(category.label)))
                            .accessibilityAddTraits(profile.iconImageData == nil && profile.iconSymbol == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    if let iconError {
                        Label(iconError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                Section {
                    ZStack(alignment: .topLeading) {
                        if profile.instructions.isEmpty {
                            // TextEditor has no placeholder; mirror its text inset.
                            Text("描述这个 Bot 的角色、语气和要遵守的规则")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $profile.instructions)
                            .frame(minHeight: 120)
                            .accessibilityLabel("Instructions")
                    }
                } header: { Text("Instructions") }
                Section {
                    Picker("Model Group", selection: Binding(get: { profile.modelGroupId ?? "" }, set: { profile.modelGroupId = $0.isEmpty ? nil : $0 })) {
                        Text("Default Model Group").tag("")
                        ForEach(providers.modelGroups) { group in Text(group.name).tag(group.id) }
                    }
                    NavigationLink("长期记忆") { BotMemoryView(owner: "bot:\(profile.id)", title: profile.name) }
                    Toggle("启用此 Bot 的长期记忆", isOn: Binding(get: { profile.memoryEnabled ?? true }, set: { profile.memoryEnabled = $0 }))
                } footer: {
                    Text("技能和连接器请在应用设置中管理。模型组作为首次打开 Bot 的默认值。")
                }
                if let error = store.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle(store.bot(profile.id) == nil ? LocalizedStringKey("新建 Bot") : LocalizedStringKey("Edit Bot"))
            .navigationBarTitleDisplayMode(.inline)
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

struct BotRoomEditor: View {
    @State var room: BotRoom
    @ObservedObject private var store = BotWorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Group Name", text: $room.name)
                    Toggle("启用此群组的长期记忆", isOn: Binding(get: { room.memoryEnabled ?? true }, set: { room.memoryEnabled = $0 }))
                }
                Section {
                    ForEach(Array(room.members.enumerated()), id: \.element) { index, id in
                        if let bot = store.bot(id) {
                            HStack(spacing: 12) {
                                Text(index + 1, format: .number)
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(minWidth: 20)
                                    .accessibilityHidden(true)
                                BotAvatar(profile: bot, size: 32)
                                Text(bot.name)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .onMove { room.members.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { room.members.remove(atOffsets: $0) }
                    if room.members.isEmpty {
                        Text("从下方添加至少 2 个成员").foregroundStyle(.secondary)
                    }
                } header: { Text("Speaking Order") } footer: {
                    Text("Each user message starts one round. All selected members reply once in order and see earlier replies. Private chats are not shared. You can stop a round at any time.")
                }
                let candidates = store.data.bots.filter { !room.members.contains($0.id) }
                if !candidates.isEmpty {
                    Section("Add Members") {
                        ForEach(candidates) { bot in
                            Button { room.members.append(bot.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.green).font(.title3)
                                        .accessibilityHidden(true)
                                    BotAvatar(profile: bot, size: 32)
                                    Text(bot.name).foregroundStyle(.primary)
                                }
                            }
                            .accessibilityLabel(bot.name)
                            .accessibilityHint("添加到群聊")
                        }
                    }
                }
                if let error = store.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(store.room(room.id) == nil ? LocalizedStringKey("创建群聊") : LocalizedStringKey("Edit Group"))
            .navigationBarTitleDisplayMode(.inline)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var input = ""
    @State private var recipient = ""
    @State private var editing: BotRoom?
    @State private var chat: BotChatTarget?
    @State private var showMemory = false
    private var room: BotRoom? { store.room(roomID) }
    private var isRunning: Bool { runner.activeRooms.contains(roomID) }
    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && room?.members.isEmpty == false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if room?.messages.isEmpty == true {
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.largeTitle).foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text("Send a message to start a group round.")
                                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 48)
                        }
                        ForEach(room?.messages ?? []) { message in
                            messageRow(message).id(message.id)
                        }
                        if let speaker = runner.speakers[roomID] {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("\(speaker) is working…").font(.subheadline).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .id("working")
                        }
                        if room?.interrupted == true && !isRunning {
                            Label("The previous round was interrupted. Send a new message to continue.", systemImage: "pause.circle")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let error = store.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                    }.padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: room?.messages.count) { _ in
                    guard let last = room?.messages.last else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: runner.speakers[roomID]) { speaker in
                    if speaker != nil { proxy.scrollTo("working", anchor: .bottom) }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Menu {
                    Picker("Recipients", selection: $recipient) {
                        Text("All Members").tag("")
                        ForEach(room?.members ?? [], id: \.self) { id in Text(store.bot(id)?.name ?? id).tag(id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "at").accessibilityHidden(true)
                        Text(recipient.isEmpty ? String(localized: "All Members") : (store.bot(recipient)?.name ?? recipient))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).accessibilityHidden(true)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 32)
                }
                .accessibilityLabel("Recipients")
                .disabled(isRunning)
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message", text: $input, axis: .vertical)
                        .lineLimit(1...6)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    if isRunning {
                        Button { runner.stop(roomID) } label: {
                            Image(systemName: "stop.circle.fill").font(.title).foregroundStyle(.red)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Stop")
                    } else {
                        Button {
                            runner.send(input, roomID: roomID, recipient: recipient.isEmpty ? nil : recipient)
                            if runner.activeRooms.contains(roomID) { input = "" }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title)
                                .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .disabled(!canSend)
                        .accessibilityLabel("Send")
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(room?.name ?? String(localized: "Group"))
        .navigationBarTitleDisplayMode(.inline)
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = room } label: { Label("Members", systemImage: "person.2") }.disabled(isRunning)
                    // A sheet rather than a NavigationLink: links inside toolbar menus don't push reliably.
                    Button { showMemory = true } label: { Label("Memory", systemImage: "brain") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More")
            }
        }
        .sheet(item: $editing) { BotRoomEditor(room: $0) }
        .sheet(isPresented: $showMemory) {
            NavigationStack {
                BotMemoryView(owner: "room:\(roomID)", title: room?.name ?? "Group Memory")
                    .toolbar { Button("Done") { showMemory = false } }
            }
        }
        .sheet(item: $chat) { target in
            NavigationStack {
                AIChatView(sessionId: target.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { chat = nil } } }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: BotRoomMessage) -> some View {
        let bot = message.botId.flatMap { store.bot($0) }
        // User turns carry neither a botId nor a session; system notices carry no session.
        let isUser = message.botId == nil && message.sessionId == nil && message.speaker == String(localized: "You")
        if isUser {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.text).textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(message.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                if let bot { BotAvatar(profile: bot, size: 32) }
                else {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                        .frame(width: 32, height: 32).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(message.speaker).font(.subheadline.weight(.semibold))
                        Text(message.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(message.text).textSelection(.enabled)
                    if let sessionID = message.sessionId {
                        Button { chat = BotChatTarget(id: sessionID) } label: {
                            Label("View Tools and Conversation", systemImage: "wrench.and.screwdriver")
                                .font(.caption).frame(minHeight: 32)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Spacer(minLength: 24)
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
                    // Inset scales with the avatar so 22pt headers and 44pt rows look alike.
                    .resizable().scaledToFit().padding(size * 0.24)
                    .foregroundStyle(iconColor)
                    // 18% tint matches the session-list category avatars (shared/design/category-colors.md).
                    .background(iconColor.opacity(0.18), in: Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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
    @State private var openingBotID: String?
    @State private var error: String?
    private var opening: Bool { openingBotID != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.data.bots.filter { excludedSessionID == nil || $0.sessionId != excludedSessionID }) { bot in
                        Button {
                            openingBotID = bot.id
                            Task { @MainActor in
                                defer { openingBotID = nil }
                                do {
                                    let id = try await store.session(botID: bot.id)
                                    onSelect(id)
                                } catch { self.error = error.localizedDescription }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                BotAvatar(profile: bot, size: 40)
                                Text(bot.name).foregroundStyle(.primary)
                                Spacer()
                                if openingBotID == bot.id { ProgressView() }
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .disabled(opening)
                    }
                    Button { newBot = store.newBot() } label: { Label("Create Bot", systemImage: "plus") }
                        .frame(minHeight: 44)
                        .disabled(opening)
                } footer: { Text("Choose a Bot before starting a conversation") }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Choose Bot")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(opening) } }
            .sheet(item: $newBot, onDismiss: {
                guard let bot = savedBot else { return }
                savedBot = nil
                openingBotID = bot.id
                Task { @MainActor in
                    defer { openingBotID = nil }
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

/// Reads the existing runtime tracker without creating/loading conversations just for list rows.
struct BotRunStatusView: View {
    let botID: String
    var sessionID: String? = nil
    /// Home rows show the status only while something is happening, so an
    /// idle list reads like the reference: name, time and last message.
    var hidesWhenIdle = false
    @ObservedObject private var activity = SessionActivityTracker.shared
    @ObservedObject private var workspace = BotWorkspaceStore.shared

    private var sessionIDs: Set<String> {
        if let sessionID { return [sessionID] }
        return Set(workspace.data.sessionOwners.filter { $0.value.botId == botID }.map(\.key))
    }

    private var status: (text: String, symbol: String, running: Bool) {
        let ids = sessionIDs
        let running = ids.intersection(activity.activeSessions)
        if !running.isEmpty {
            let tools = running.compactMap { activity.sessionToolInfo[$0] }
            if let tool = tools.filter({ !$0.toolName.isEmpty }).max(by: { $0.lastActivity < $1.lastActivity }) {
                return (tool.toolStatus.isEmpty ? "正在执行工具" : tool.toolStatus, "wrench.and.screwdriver", true)
            }
            return ("正在回复", "ellipsis", true)
        }
        if !ids.isDisjoint(with: activity.delegatingSessions) { return ("正在等待子任务", "person.2", true) }
        if !ids.isDisjoint(with: activity.scheduledSessions) { return ("等待定时任务", "clock", false) }
        let models = ids.compactMap { ViewModelCache.shared.get(for: $0) }
        // completedAt records when a loop ended, including interruption. Inspect the
        // latest conversation's outcome first; an old failed chat must not mask a newer success.
        if let latestModel = models.max(by: {
            ($0.messages.last?.timestamp ?? .distantPast) < ($1.messages.last?.timestamp ?? .distantPast)
        }) {
            let reply = latestModel.messages.last(where: { $0.role == .assistant })
            if latestModel.errorMessage != nil || reply?.error != nil {
                return ("运行出错", "exclamationmark.triangle", false)
            }
            if latestModel.canResume { return ("已停止，可继续", "pause.circle", false) }
            if reply?.completedAt != nil { return ("回复已完成", "checkmark.circle", false) }
        }
        return ("空闲", "circle", false)
    }

    var body: some View {
        let value = status
        // Errors stay visible on home rows; only quiet states are hidden there.
        let isQuiet = !value.running && value.symbol != "exclamationmark.triangle"
        if !(hidesWhenIdle && isQuiet) {
            HStack(spacing: 5) {
                if value.running { ProgressView().controlSize(.mini) }
                else { Image(systemName: value.symbol) }
                Text(value.text).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(value.running ? Color.green : .secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

import SwiftUI

private struct BotChatTarget: Identifiable { var id: String }

struct BotWorkspaceView: View {
    var embedded = false
    var onShowHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @ObservedObject private var store = BotWorkspaceStore.shared
    @ObservedObject private var runner = BotRoomRunner.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editingBot: BotProfile?
    @State private var editingRoom: BotRoom?
    @State private var chat: BotChatTarget?
    @State private var opening = false
    @State private var deletingBot: BotProfile?
    @State private var deletingRoom: BotRoom?

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
                    Button { editingBot = BotProfile(name: "") } label: { Label("Create Bot", systemImage: "plus") }
                    ForEach(store.data.bots) { bot in
                        Button { open(bot) } label: {
                            Label(bot.name, systemImage: "person.crop.square")
                        }
                        .disabled(opening)
                        .contextMenu {
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
                    Button { editingRoom = BotRoom(name: "", members: []) } label: { Label("Create Group", systemImage: "person.2.badge.plus") }
                        .disabled(store.data.bots.count < 2)
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
                Section {
                    Text("Bots use OpenMinis model groups, skills, MCP servers and device permissions. Existing conversations remain in History. Bot profiles and group transcripts are stored on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bots & Groups")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onOpenSettings { Button("Settings", action: onOpenSettings) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let onShowHistory { Button("History", action: onShowHistory) }
                    else { Button("Done") { dismiss() } }
                }
            }
            .sheet(item: $editingBot) { BotProfileEditor(profile: $0) }
            .sheet(item: $editingRoom) { BotRoomEditor(room: $0) }
            .sheet(item: $chat) { target in
                NavigationStack {
                    AIChatView(sessionId: target.id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { chat = nil } } }
                }
            }
            .confirmationDialog("Delete Bot? Its conversations will remain in History.", isPresented: Binding(get: { deletingBot != nil }, set: { if !$0 { deletingBot = nil } })) {
                Button("Delete", role: .destructive) { if let deletingBot { store.deleteBot(deletingBot.id) }; deletingBot = nil }
            }
            .confirmationDialog("Delete this group and its shared transcript? Member conversations remain in History.", isPresented: Binding(get: { deletingRoom != nil }, set: { if !$0 { deletingRoom = nil } })) {
                Button("Delete", role: .destructive) { if let deletingRoom { store.deleteRoom(deletingRoom.id) }; deletingRoom = nil }
            }
    }

    private func open(_ bot: BotProfile) {
        opening = true
        Task { @MainActor in
            defer { opening = false }
            do { chat = BotChatTarget(id: try await store.session(botID: bot.id)) }
            catch { store.errorMessage = error.localizedDescription }
        }
    }
}

private struct BotProfileEditor: View {
    @State var profile: BotProfile
    @ObservedObject private var store = BotWorkspaceStore.shared
    @ObservedObject private var providers = ProviderConfigStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var capabilities: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $profile.name)
                Section("Instructions") { TextEditor(text: $profile.instructions).frame(minHeight: 120) }
                Picker("Model Group", selection: Binding(get: { profile.modelGroupId ?? "" }, set: { profile.modelGroupId = $0.isEmpty ? nil : $0 })) {
                    Text("Default Model Group").tag("")
                    ForEach(providers.modelGroups) { group in Text(group.name).tag(group.id) }
                }
                Section {
                    if let sessionID = profile.sessionId {
                        Button("Skills") { capabilities = "skills" }
                        Button("MCP Servers") { capabilities = "mcp" }
                        Text("New group conversations inherit these choices. Existing group conversations keep their own overrides.").font(.footnote)
                        Text(sessionID).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        Text("Open this Bot once to configure its conversation's skills and MCP servers.").font(.footnote)
                    }
                    NavigationLink("Global Tools and Permissions") { MCPIntegrationsView() }
                } header: { Text("Capabilities") }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit Bot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.save(profile) { store.applyModel(for: profile); dismiss() } }
                        .disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: Binding(get: { capabilities != nil }, set: { if !$0 { capabilities = nil } })) {
                if capabilities == "skills" { SessionSkillsView(sessionId: profile.sessionId) }
                else { SessionMCPsView(sessionId: profile.sessionId) }
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
                .onChange(of: room?.messages.count) { _, _ in
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
        .toolbar { Button("Members") { editing = room }.disabled(isRunning) }
        .sheet(item: $editing) { BotRoomEditor(room: $0) }
        .sheet(item: $chat) { target in
            NavigationStack {
                AIChatView(sessionId: target.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { chat = nil } } }
            }
        }
    }
}

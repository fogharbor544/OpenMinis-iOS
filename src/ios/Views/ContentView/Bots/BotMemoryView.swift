import SwiftUI

struct BotMemoryView: View {
    let owner: String
    var title = String(localized: "Memory")
    @ObservedObject private var store = BotMemoryStore.shared
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @State private var entries: [BotMemoryEntry] = []
    @State private var editing: BotMemoryEntry?
    @State private var deleting: BotMemoryEntry?
    @State private var sharing: BotMemoryEntry?
    @State private var query = ""
    @State private var error: String?
    private var ownerAvailable: Bool {
        owner == "shared" || workspace.data.bots.contains { "bot:\($0.id)" == owner } ||
        workspace.data.rooms.contains { "room:\($0.id)" == owner }
    }

    var body: some View {
        List {
            Section {
                Text("Memories belong to this Bot or group. Private memories are not automatically used in groups. Shared entries appear only where you grant access.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
            if !ownerAvailable { Text("This Bot or group no longer exists.").foregroundStyle(.secondary) }
            if entries.isEmpty { Label("No Memories", systemImage: "brain").foregroundStyle(.secondary) }
            ForEach(entries.filter { query.isEmpty || $0.content.localizedCaseInsensitiveContains(query) || $0.scope.localizedCaseInsensitiveContains(query) }) { entry in
                Section {
                    Text(entry.content).textSelection(.enabled)
                    Text("\(entry.category) · \(entry.scope)").font(.caption).foregroundStyle(.secondary)
                    Text(entry.updatedAt, style: .date).font(.caption)
                    if entry.pinned { Label("Always include", systemImage: "pin").font(.caption) }
                    if entry.automatic { Text("Automatically remembered").font(.caption) }
                    DisclosureGroup("Source") {
                        Text(entry.evidence.isEmpty
                             ? (entry.automatic ? String(localized: "No additional source information") : String(localized: "Added or edited by you"))
                             : entry.evidence).textSelection(.enabled)
                        if let id = entry.sourceSession { Text("Conversation: \(id)").font(.caption2).textSelection(.enabled) }
                        if let id = entry.sourceMessage { Text("Message: \(id)").font(.caption2).textSelection(.enabled) }
                    }
                    if entry.owner == owner {
                        HStack {
                            Button("Edit") { editing = entry }
                            Button("Share") { sharing = entry }
                            Button(entry.automatic ? "Undo Memory" : "Delete", role: .destructive) { deleting = entry }
                        }.buttonStyle(.borderless)
                    } else {
                        Text("Shared with this conversation. Manage the original entry to change or revoke sharing.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(Text(title))
        .searchable(text: $query)
        .toolbar {
            Button { editing = BotMemoryEntry(owner: owner, content: "", category: "fact", scope: "general", evidence: "") }
            label: { Label("Add Memory", systemImage: "plus") }
                .disabled(!ownerAvailable)
        }
        .onAppear { reload() }
        .onChange(of: store.revision) { _ in reload() }
        .sheet(item: $editing) { entry in BotMemoryEditor(entry: entry) }
        .sheet(item: $sharing) { entry in BotMemorySharingView(entry: entry) }
        .confirmationDialog("Forget this memory? It will no longer be retrieved or shared, and old source messages cannot automatically restore it.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Forget", role: .destructive) {
                guard let entry = deleting else { return }
                do { try store.forget(id: entry.id, owner: owner); deleting = nil }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func reload() {
        do { entries = try store.visible(to: owner); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct BotMemoryEditor: View {
    @State var entry: BotMemoryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $entry.content).frame(minHeight: 120)
                Picker("Category", selection: $entry.category) {
                    Text("Preference").tag("preference")
                    Text("Fact").tag("fact")
                    Text("Convention").tag("convention")
                    Text("Experience").tag("experience")
                }
                TextField("Scope", text: $entry.scope)
                Toggle("Always include", isOn: $entry.pinned)
                Text("Pinned memories are always included. Recent notes are loaded by date; search memory for other relevant context.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Edit Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let original = try BotMemoryStore.shared.entries().first { $0.id == entry.id }
                            var draft = entry
                            draft.id = UUID().uuidString
                            draft.createdAt = Date(); draft.updatedAt = Date(); draft.automatic = false
                            draft.evidence = "Edited by user"; draft.sourceMessage = nil; draft.sourceSession = nil
                            _ = try BotMemoryStore.shared.save(draft, replacing: original?.id, userInitiated: true)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(entry.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct BotMemorySharingView: View {
    let entry: BotMemoryEntry
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @State private var grants: Set<String> = []
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Text(entry.content)
                Text("Only selected Bots and groups may retrieve this entry. Unchecking revokes future access; previously sent chat messages remain in their conversations.")
                    .font(.footnote).foregroundStyle(.secondary)
                Section("Bots") {
                    ForEach(workspace.data.bots.filter { "bot:\($0.id)" != entry.owner }) { bot in
                        Toggle(bot.name, isOn: selection("bot:\(bot.id)"))
                    }
                }
                Section("Groups") {
                    ForEach(workspace.data.rooms.filter { "room:\($0.id)" != entry.owner }) { room in
                        Toggle(room.name, isOn: selection("room:\(room.id)"))
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Share Memory")
            .onAppear { grants = Set(entry.grants) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try BotMemoryStore.shared.setGrants(id: entry.id, owner: entry.owner, grants: Array(grants)); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }

    private func selection(_ key: String) -> Binding<Bool> {
        Binding(get: { grants.contains(key) }, set: { if $0 { grants.insert(key) } else { grants.remove(key) } })
    }
}

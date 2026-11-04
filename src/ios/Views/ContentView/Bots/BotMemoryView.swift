import SwiftUI
import UIKit

@MainActor private func memoryOwnerExists(_ owner: String) -> Bool {
    let data = BotWorkspaceStore.shared.data
    return owner == "shared" || data.bots.contains { "bot:\($0.id)" == owner } || data.rooms.contains { "room:\($0.id)" == owner }
}

struct BotMemoryView: View {
    let owner: String
    var title = String(localized: "Memory")
    @ObservedObject private var store = BotMemoryStore.shared
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @State private var owned: [BotMemoryEntry] = []
    @State private var shared: [BotMemoryEntry] = []
    private enum MemorySection: Hashable { case fixed, history }
    @State private var section: MemorySection = .fixed
    @State private var editing = false
    @State private var addingFixed = false
    @State private var sharing = false
    @State private var clearing = false
    @State private var query = ""
    @State private var error: String?
    private var document: String { BotMemoryStore.documentText(owned) }
    private var available: Bool { memoryOwnerExists(owner) }
    private var displayedEntries: [BotMemoryEntry] {
        if section == .fixed { return owned.filter(\.isFixedMemory) }
        return owned.filter { !$0.isFixedMemory }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
    }
    private var displayedShared: [BotMemoryEntry] {
        shared.filter { $0.isFixedMemory == (section == .fixed) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("长期记忆文档", systemImage: "doc.text").font(.title2.bold())
                    Text("固定记忆用于长期保留规则和偏好；其他记忆与事件可在历史中浏览。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let date = owned.map(\.updatedAt).max() {
                        Text("最近更新 \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("记忆分类", selection: $section) {
                    Text("固定记忆").tag(MemorySection.fixed)
                    Text("历史浏览").tag(MemorySection.history)
                }
                .pickerStyle(.segmented)

                if !query.isEmpty {
                    Text(BotMemoryStore.documentText(displayedEntries + displayedShared).localizedCaseInsensitiveContains(query)
                         ? "匹配内容已高亮" : "当前分类未找到匹配内容").font(.caption).foregroundStyle(.secondary)
                }
                if !available { Text("此 Bot 或群组已不存在。").foregroundStyle(.secondary) }
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                if section == .fixed {
                    Button { addingFixed = true } label: {
                        Label("添加固定记忆", systemImage: "plus").frame(minHeight: 44)
                    }
                    .disabled(!available)
                }
                if displayedEntries.isEmpty {
                    if section == .fixed {
                        Text("还没有固定记忆").foregroundStyle(.secondary)
                    } else {
                        Text("还没有历史记忆").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(displayedEntries) { entry in
                        memoryRow(entry)
                    }
                }
                if !displayedShared.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Label("共享给我的记忆", systemImage: "person.2").font(.headline)
                        Text("这些内容也可供当前 Bot 参考；编辑和撤销共享由来源 Bot 管理。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(Array(Set(displayedShared.map(\.owner))).sorted(), id: \.self) { source in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sharedSourceName(source)).font(.subheadline.weight(.semibold))
                                highlighted(BotMemoryStore.documentText(displayedShared.filter { $0.owner == source }))
                                    .font(.body).lineSpacing(6).textSelection(.enabled)
                            }
                        }
                    }
                }
            }.frame(maxWidth: 760, alignment: .leading).padding(20).frame(maxWidth: .infinity)
        }
        .background(Color(UIColor.systemBackground))
        .navigationTitle(Text(title)).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "在当前分类查找")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("编辑") { editing = true }.disabled(!available)
                Menu {
                    Button { UIPasteboard.general.string = document } label: { Label("复制全文", systemImage: "doc.on.doc") }
                        .disabled(document.isEmpty)
                    ShareLink(item: document) { Label("导出文档", systemImage: "square.and.arrow.up") }.disabled(document.isEmpty)
                    Button { sharing = true } label: { Label("共享给 Bot 或群组", systemImage: "person.2") }
                        .disabled(owned.isEmpty || !available)
                    Button(role: .destructive) { clearing = true } label: { Label("清空当前文档", systemImage: "trash") }
                        .disabled(owned.isEmpty || !available)
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("文档操作")
            }
        }
        .onAppear { reload() }
        .onChange(of: store.revision) { _ in reload() }
        .sheet(isPresented: $editing) { BotMemoryDocumentEditor(owner: owner, baseline: owned) }
        .sheet(isPresented: $addingFixed) { BotFixedMemoryComposer(owner: owner) }
        .sheet(isPresented: $sharing) { BotMemoryDocumentSharing(owner: owner, baseline: owned) }
        .confirmationDialog("清空这篇记忆文档？", isPresented: $clearing, titleVisibility: .visible) {
            Button("清空文档", role: .destructive) {
                guard available else { return }
                do { try store.saveDocument(owner: owner, text: "", baseline: owned) }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("当前内容将被遗忘，并撤销其共享。旧消息不会自动把它恢复。") }
    }

    private func memoryRow(_ entry: BotMemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if entry.category == "event" {
                    Text(eventPresentation(entry)).font(.caption).foregroundStyle(.secondary)
                } else if section == .history {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                highlighted(entry.content).font(.body).lineSpacing(6).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.category != "event" || entry.isFixedMemory {
                Button {
                    guard available else { return }
                    do { try store.setFixedMemory(id: entry.id, owner: owner, fixed: !entry.isFixedMemory) }
                    catch { self.error = error.localizedDescription }
                } label: {
                    Image(systemName: entry.isFixedMemory ? "pin.slash" : "pin")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!available)
                .accessibilityLabel(entry.isFixedMemory ? Text("取消固定") : Text("固定记忆"))
            }
        }
    }

    private func highlighted(_ text: String) -> Text {
        guard !query.isEmpty else { return Text(text) }
        var result = Text("")
        var start = text.startIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: start..<text.endIndex) {
            result = result + Text(String(text[start..<range.lowerBound])) + Text(String(text[range])).bold().foregroundColor(.accentColor)
            start = range.upperBound
        }
        return result + Text(String(text[start...]))
    }

    private func eventPresentation(_ entry: BotMemoryEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let kind: String
        switch entry.eventKind {
        case "decision": kind = "决定"
        case "delivery": kind = "交付"
        case "verification": kind = "验证"
        default: kind = "事件"
        }
        return "记录时间 \(formatter.string(from: entry.createdAt)) · \(kind)"
    }

    private func sharedSourceName(_ owner: String) -> String {
        workspace.data.bots.first(where: { "bot:\($0.id)" == owner })?.name ??
        workspace.data.rooms.first(where: { "room:\($0.id)" == owner })?.name ?? "其他来源"
    }

    private func reload() {
        do {
            owned = try store.documentEntries(owner: owner)
            shared = try store.sharedDocumentEntries(to: owner)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct BotFixedMemoryComposer: View {
    let owner: String
    @State private var draft = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $draft)
                    .frame(minHeight: 140)
                    .accessibilityLabel("固定记忆内容")
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("添加固定记忆")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!draft.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard memoryOwnerExists(owner) else { error = "此 Bot 或群组已不存在。"; return }
                        do {
                            try BotMemoryStore.shared.saveFixedMemory(owner: owner, content: draft)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct BotMemoryDocumentEditor: View {
    let owner: String
    @State private var baseline: [BotMemoryEntry]
    @State private var draft: String
    @State private var entryDrafts: [String: String]
    @State private var error: String?
    @State private var discarding = false
    @Environment(\.dismiss) private var dismiss
    private var changed: Bool {
        draft != BotMemoryStore.documentText(baseline.filter { $0.category != "event" && !$0.isFixedMemory }) ||
        baseline.filter { $0.category == "event" || $0.isFixedMemory }.contains { entryDrafts[$0.id] != $0.content }
    }
    private var draftDocument: String {
        ([draft] + baseline.filter { $0.category == "event" || $0.isFixedMemory }.map { entryDrafts[$0.id] ?? "" })
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    init(owner: String, baseline: [BotMemoryEntry]) {
        self.owner = owner
        _baseline = State(initialValue: baseline)
        _draft = State(initialValue: BotMemoryStore.documentText(baseline.filter { $0.category != "event" && !$0.isFixedMemory }))
        _entryDrafts = State(initialValue: Dictionary(uniqueKeysWithValues: baseline.filter { $0.category == "event" || $0.isFixedMemory }.map { ($0.id, $0.content) }))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("普通记忆用空行分段。固定记忆和事件单独编辑；清空对应内容即可删除。")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
                if let error {
                    VStack(alignment: .leading) {
                        Text(error).font(.callout).foregroundStyle(.red)
                        Button("复制草稿") { UIPasteboard.general.string = draftDocument }.frame(minHeight: 44)
                    }.padding(.horizontal, 16)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("普通记忆").font(.headline)
                        TextEditor(text: $draft).font(.body).lineSpacing(6).frame(minHeight: 240)
                            .accessibilityLabel("长期记忆文档内容")
                        ForEach(baseline.filter { $0.category == "event" || $0.isFixedMemory }) { entry in
                            if entry.isFixedMemory {
                                Text("固定记忆").font(.headline)
                            } else {
                                Text("事件 · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.headline)
                            }
                            TextEditor(text: Binding(get: { entryDrafts[entry.id] ?? "" },
                                                     set: { entryDrafts[entry.id] = $0 }))
                                .font(.body).lineSpacing(6).frame(minHeight: 140)
                                .accessibilityLabel(entry.isFixedMemory ? Text("固定记忆内容") : Text("事件内容"))
                        }
                    }.padding(.horizontal, 16)
                }
            }.padding(.top, 12)
                .navigationTitle("编辑记忆文档").navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(changed)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { if changed { discarding = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            guard memoryOwnerExists(owner) else { error = "此 Bot 或群组已不存在。"; return }
                            let events = Set(baseline.filter { $0.category == "event" }.map(\.id))
                            do {
                                try BotMemoryStore.shared.saveDocument(
                                    owner: owner, text: draft, baseline: baseline,
                                    eventEdits: entryDrafts.filter { events.contains($0.key) },
                                    fixedEdits: entryDrafts.filter { !events.contains($0.key) }
                                )
                                dismiss()
                            }
                            catch { self.error = error.localizedDescription }
                        }.disabled(!changed)
                    }
                }
                .confirmationDialog("放弃尚未保存的修改？", isPresented: $discarding, titleVisibility: .visible) {
                    Button("放弃修改", role: .destructive) { dismiss() }
                }
        }
    }
}

private struct BotMemoryDocumentSharing: View {
    let owner: String
    @State private var baseline: [BotMemoryEntry]
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @State private var grants: Set<String> = []
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(owner: String, baseline: [BotMemoryEntry]) {
        self.owner = owner
        _baseline = State(initialValue: baseline)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("保存会统一当前文档的共享范围。所选 Bot 或群组可读取整篇内容；之后新增或改写的内容默认私有，需要重新共享。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Bot") {
                    ForEach(workspace.data.bots.filter { "bot:\($0.id)" != owner }) { bot in shareToggle(bot.name, key: "bot:\(bot.id)") }
                }
                Section("群组") {
                    ForEach(workspace.data.rooms.filter { "room:\($0.id)" != owner }) { room in shareToggle(room.name, key: "room:\(room.id)") }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("共享记忆文档").navigationBarTitleDisplayMode(.inline)
            .onAppear { grants = baseline.dropFirst().reduce(Set(baseline.first?.grants ?? [])) { $0.intersection($1.grants) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard memoryOwnerExists(owner) else { error = "此 Bot 或群组已不存在。"; return }
                        do { try BotMemoryStore.shared.setDocumentGrants(owner: owner, baseline: baseline, grants: Array(grants)); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
    private func shareToggle(_ name: String, key: String) -> some View {
        Toggle(isOn: selection(key)) {
            HStack {
                Text(name)
                if baseline.contains(where: { $0.grants.contains(key) }) && !baseline.allSatisfy({ $0.grants.contains(key) }) {
                    Text("部分内容已共享").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func selection(_ key: String) -> Binding<Bool> {
        Binding(get: { grants.contains(key) }, set: { if $0 { grants.insert(key) } else { grants.remove(key) } })
    }
}

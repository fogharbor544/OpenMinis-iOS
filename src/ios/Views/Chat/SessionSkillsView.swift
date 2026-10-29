//
//  SessionSkillsView.swift
//  MinisApp
//
//  Per-session skill toggle sheet: override which skills are active in a chat.
//

import SwiftUI

struct SessionSkillsView: View {
    let sessionId: String?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SkillStore.shared
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    @State private var searchQuery = ""

    private func isEnabled(_ skill: Skill) -> Bool {
        if let sid = sessionId {
            return store.isEnabledForSession(skill.id, sessionId: sid)
        }
        return skill.isEnabled
    }

    private func setOverride(_ item: Skill, _ enabled: Bool) {
        guard let sid = sessionId, workspace.bot(forSession: sid) != nil else { return }
        store.setSessionOverride(skillId: item.id, sessionId: sid, enabled: enabled)
    }

    private func applyToAll(_ scope: [Skill], enabled: Bool) {
        for item in scope { setOverride(item, enabled) }
    }

    private var filteredSkills: [Skill] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.skills }
        return store.skills.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
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
                if store.skills.isEmpty {
                    Section {
                        SessionOverrideEmptyCard(systemImage: "doc.text",
                                                 title: AppLocalized("No skills installed"),
                                                 subtitle: AppLocalized("Import skills from Settings → Skills."))
                    }
                } else if filteredSkills.isEmpty {
                    Section {
                        Text(AppLocalized("No skills match \"\(searchQuery)\"."))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Section {
                        ForEach(filteredSkills) { skill in
                            NavigationLink {
                                SessionSkillDetailView(skill: skill)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(skill.name).font(.body)
                                        if !skill.description.isEmpty {
                                            Text(skill.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { isEnabled(skill) },
                                        set: { setOverride(skill, $0) }
                                    ))
                                    .labelsHidden()
                                }
                            }
                            // [T-skill-copy-source-url] Same long-press as the
                            // Settings list; the success haptic is the feedback.
                            .modifier(SkillSourceURLContextMenu(url: skill.importSource.copyableURL) {})
                        }
                    } header: {
                        let scope = filteredSkills
                        SessionBulkToggleHeader(
                            availability: SessionBulkToggleRules.availability(scope.map { isEnabled($0) })
                        ) { applyToAll(scope, enabled: $0) }
                    } footer: {
                        SessionOverrideListFooter(
                            note: Text("修改所属 Bot 的技能设置，对它的全部会话生效。"),
                            searchQuery: searchQuery)
                    }
                }
            }
            .disabled(sessionId.flatMap { workspace.bot(forSession: $0) } == nil)
            .navigationTitle("Bot 技能")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(AppLocalized("Search skills")))
            .onAppear { store.reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SessionSkillDetailView: View {
    let skill: Skill
    @ObservedObject private var store = SkillStore.shared

    private var additionalFiles: [String] {
        store.listSkillFiles(skill.id).filter { $0 != "SKILL.md" }
    }

    var body: some View {
        List {
            Section("SKILL.md") {
                let content = store.readSkillContent(skill.id) ?? "(empty)"
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            if !additionalFiles.isEmpty {
                Section("Other Files") {
                    ForEach(additionalFiles, id: \.self) { relativePath in
                        NavigationLink {
                            SkillFilePreviewView(skillId: skill.id, relativePath: relativePath)
                        } label: {
                            Label {
                                Text(relativePath)
                                    .font(.system(.subheadline, design: .monospaced))
                            } icon: {
                                Image(systemName: iconName(for: relativePath))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func iconName(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "md": return "doc.text"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        case "sh": return "terminal"
        case "yaml", "yml": return "list.bullet.indent"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        default: return "doc"
        }
    }
}

private struct SkillFilePreviewView: View {
    let skillId: String
    let relativePath: String

    @ObservedObject private var store = SkillStore.shared
    @State private var content: String = ""

    private var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    private var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "webp"].contains((relativePath as NSString).pathExtension.lowercased())
    }

    var body: some View {
        Group {
            if isImage {
                let fileURL = store.skillDirectoryURL(for: skillId).appendingPathComponent(relativePath)
                if let data = try? Data(contentsOf: fileURL),
                   let uiImage = UIImage(data: data) {
                    ScrollView {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                } else {
                    Text("Could not load image.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !isImage {
                content = store.readSkillFile(skillId, relativePath: relativePath) ?? ""
            }
        }
    }
}

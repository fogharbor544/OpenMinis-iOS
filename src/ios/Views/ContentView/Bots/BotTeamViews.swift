import SwiftUI

struct BotDelegationLink: View {
    let record: BotDelegation
    var incoming = false
    var fromCommander = false
    @State private var showingTranscript = false
    @ObservedObject private var store = BotWorkspaceStore.shared
    private var current: BotDelegation { store.delegation(record.id) ?? record }
    private var labelBotID: String { fromCommander ? current.fromBotID : current.toBotID }
    private var labelName: String { fromCommander ? current.fromName : current.toName }
    var body: some View {
        Button { showingTranscript = true } label: {
            HStack(spacing: 6) {
                Text(incoming ? "消息来自" : "发消息给")
                if let bot = store.bot(labelBotID) { BotAvatar(profile: bot, size: 20) }
                Text(store.bot(labelBotID)?.name ?? labelName)
                Image(systemName: "chevron.right").font(.caption2)
            }.font(.caption).foregroundStyle(.secondary).frame(minHeight: 44)
        }.buttonStyle(.plain)
        .sheet(isPresented: $showingTranscript) {
            if let sid = current.childSessionID {
                HelperTranscriptPage(target: HelperSheetTarget(id: sid, title: "\(current.fromName) ↔ \(current.toName)"))
                    .presentationDetents([.large]).interactiveDismissDisabled()
            } else {
                NavigationStack {
                    List {
                        Text(current.title).font(.headline)
                        Text(current.state.label).foregroundStyle(.secondary)
                        Text(current.task).textSelection(.enabled)
                        if let result = current.result { Text(result).textSelection(.enabled) }
                    }
                    .navigationTitle("\(current.fromName) ↔ \(current.toName)")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingTranscript = false } } }
                }
            }
        }
    }
}

/// Part of the message timeline, not a floating overlay over chat content.
struct BotConversationOverview: View {
    @EnvironmentObject private var vm: AIChatViewModel
    @ObservedObject private var store = BotWorkspaceStore.shared
    @State private var selected: Set<Int> = []
    @State private var error: String?
    @State private var openBot: BotProfile?
    private var bot: BotProfile? { vm.sessionId.flatMap { store.bot(forSession: $0) } }
    private var records: [BotDelegation] {
        guard let bot else { return [] }
        return store.data.delegations.filter { $0.toBotID == bot.id }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let bot {
                if let intro = bot.introduction, !intro.isEmpty {
                    Text(intro).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                }
                if let onboarding = bot.onboarding, !onboarding.dismissed {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Text(onboarding.question).font(.headline)
                            Spacer(minLength: 8)
                            Button { dismissOnboarding(bot) } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                                .accessibilityLabel("跳过偏好选择")
                        }
                        ForEach(Array(onboarding.options.enumerated()), id: \.offset) { i, option in
                            Button {
                                if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selected.contains(i) ? "checkmark.circle.fill" : "circle")
                                    Text(option).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                }.frame(minHeight: 44)
                            }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(i) ? .isSelected : [])
                        }
                        HStack {
                            Button("跳过") { dismissOnboarding(bot) }
                            Spacer()
                            Button("记住选择") { savePreferences(bot, onboarding: onboarding) }.disabled(selected.isEmpty)
                        }.frame(minHeight: 44)
                        Text(bot.memoryEnabled == false ? "长期记忆已关闭，选择不会长期保存。可以直接开始聊天。" : "可多选，也可以跳过；选择仅用于长期偏好，不会自动执行任务。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(16).background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                }
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("来自指挥官的任务").font(.headline)
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 0) {
                                BotDelegationLink(record: record, incoming: true, fromCommander: true)
                                Text(record.title).font(.subheadline).lineLimit(2)
                                Text(record.state.label).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }.padding(16).background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                }
                if bot.isCommander {
                    let created = store.data.bots.filter { $0.creationRequestID != nil }
                    if !created.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("已创建的 Bot").font(.headline)
                            ForEach(created) { target in
                                Button { openBot = target } label: {
                                    HStack { BotAvatar(profile: target, size: 28); Text(target.name); Spacer(); Image(systemName: "chevron.right") }
                                        .frame(minHeight: 44)
                                }.buttonStyle(.plain)
                            }
                        }.padding(16).background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .sheet(item: $openBot) { BotOpenedChat(botID: $0.id) }
        .onChange(of: store.data) { _ in
            NotificationCenter.default.post(name: .minisAttachmentSizeChanged, object: "bot-overview")
        }
    }

    private func dismissOnboarding(_ bot: BotProfile) {
        guard var current = store.bot(bot.id) else { return }
        current.onboarding?.dismissed = true
        if !store.save(current) { error = "无法保存引导状态，请重试。" }
    }

    private func savePreferences(_ bot: BotProfile, onboarding: BotOnboarding) {
        guard var current = store.bot(bot.id) else { return }
        let choices = selected.sorted().filter { onboarding.options.indices.contains($0) }.map { onboarding.options[$0] }
        guard !choices.isEmpty else { return }
        if current.memoryEnabled != false {
            do {
                let text = "常用需求：" + choices.joined(separator: "；")
                let entry = BotMemoryEntry(owner: "bot:\(bot.id)", content: text, category: "preference", scope: "onboarding",
                    sourceSession: vm.sessionId, sourceMessage: "onboarding:\(bot.id)", evidence: choices.joined(separator: "；"), automatic: false)
                _ = try BotMemoryStore.shared.save(entry, userInitiated: true)
            } catch { self.error = error.localizedDescription; return }
        }
        current.onboarding?.selected = selected.sorted(); current.onboarding?.dismissed = true
        if !store.save(current) { error = "偏好处理完成，但卡片状态保存失败，请重试。" }
    }
}

struct BotOpenedChat: View {
    let botID: String
    @Environment(\.dismiss) private var dismiss
    @State private var sessionID: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let sessionID { AIChatView(sessionId: sessionID).id(sessionID) }
                else if let error { Text(error).padding() }
                else { ProgressView() }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.task {
            do { sessionID = try await BotWorkspaceStore.shared.session(botID: botID) }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct BotSourceRow: View {
    let message: ChatMessage
    @EnvironmentObject private var vm: AIChatViewModel
    @ObservedObject private var store = BotWorkspaceStore.shared
    var body: some View {
        if let callback = message.agentCallback,
           let record = store.data.delegations.first(where: { $0.childSessionID == callback.childSessionId }) {
            BotDelegationLink(record: record, incoming: true).frame(maxWidth: .infinity)
        } else if let sid = vm.sessionId,
                  let record = store.data.delegations.first(where: { $0.childSessionID == sid }), message.role == .user {
            HStack(spacing: 6) {
                if let bot = store.bot(record.fromBotID) { BotAvatar(profile: bot, size: 20) }
                Text(record.fromName)
                Text("· 只读委派消息").foregroundStyle(.secondary)
            }.font(.caption).padding(.horizontal, 16)
        }
    }
}

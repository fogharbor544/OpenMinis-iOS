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
                Text(store.statusLabel(for: current)).font(.caption2)
                Image(systemName: "chevron.right").font(.caption2)
            }.font(.caption).foregroundStyle(.secondary).frame(minHeight: 44)
        }.buttonStyle(.plain)
        .sheet(isPresented: $showingTranscript) {
            BotTaskConversation(delegationID: current.id)
        }
    }
}

/// Part of the message timeline, not a floating overlay over chat content.
/// The target Bot's normal, interactive conversation with the commander.
struct BotTaskConversation: View {
    let delegationID: String
    @ObservedObject private var store = BotWorkspaceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var checkedSession: String?
    @State private var exists = false
    private var record: BotDelegation? { store.delegation(delegationID) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let record {
                    HStack(spacing: 8) {
                        if let bot = store.bot(record.fromBotID) { BotAvatar(profile: bot, size: 24) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("与 \(record.fromName) 的会话").font(.subheadline.weight(.semibold))
                            Text(store.statusLabel(for: record)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("完成") { dismiss() }.frame(minHeight: 44)
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                    Divider()
                    if let sid = record.childSessionID {
                        if checkedSession != sid { ProgressView() }
                        else if !exists { Text("会话记录不可用，任务不会重新执行。").padding() }
                        else if record.directExecution == true {
                            if store.owner(forSession: sid) == BotSessionOwner(botId: record.toBotID, delegationID: record.id) {
                                AIChatView(sessionId: sid).id(sid)
                            } else { Text("会话归属不可用，任务不会重新执行。").padding() }
                        } else {
                            // Historical helper runs stay read-only; never replay them.
                            HelperTranscriptPage(target: HelperSheetTarget(id: sid, title: "\(record.fromName) ↔ \(record.toName)"))
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(record.title).font(.headline)
                                Text(record.task).textSelection(.enabled)
                                if let result = record.result { Text(result).textSelection(.enabled) }
                                Text(record.state == .queued ? "等待目标 Bot 开始任务。" : "会话记录不可用。")
                                    .foregroundStyle(.secondary)
                            }.padding()
                        }
                    }
                } else {
                    Text("任务记录不可用。").padding()
                    Button("完成") { dismiss() }.frame(minHeight: 44)
                }
            }
            .task(id: record?.childSessionID) {
                guard let sid = record?.childSessionID else { return }
                let found = await ChatStore.shared.sessionExists(id: sid)
                guard !Task.isCancelled else { return }
                exists = found; checkedSession = sid
            }
        }
    }
}

struct BotTaskCard: View {
    let delegationID: String
    @ObservedObject private var store = BotWorkspaceStore.shared
    @State private var showingConversation = false
    var body: some View {
        if let record = store.delegation(delegationID) {
            Button { showingConversation = true } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let bot = store.bot(record.fromBotID) { BotAvatar(profile: bot, size: 28) }
                        Text(record.state.isActive ? "消息来自 \(record.fromName)" : "与 \(record.fromName) 的会话")
                            .font(.headline).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    Text(record.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text(store.statusLabel(for: record))
                        if let count = store.delegationMessageCounts[record.id] { Text("\(count) 条消息") }
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(16)
                    .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
                .sheet(isPresented: $showingConversation) { BotTaskConversation(delegationID: record.id) }
        }
    }
}

struct BotConversationOverview: View {
    @EnvironmentObject private var vm: AIChatViewModel
    @ObservedObject private var store = BotWorkspaceStore.shared
    @State private var selected: Set<Int> = []
    @State private var notice: String?
    @State private var error: String?
    private var bot: BotProfile? { vm.sessionId.flatMap { store.bot(forSession: $0) } }
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
                if let onboarding = bot.onboarding, onboarding.dismissed, !onboarding.selected.isEmpty {
                    Text((onboarding.memorySaved == true ? "已记住：" : "已选择（未写入长期记忆）：") + onboarding.selected.filter { onboarding.options.indices.contains($0) }.map { onboarding.options[$0] }.joined(separator: "、"))
                        .font(.subheadline).foregroundStyle(.secondary).padding(16)
                }
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: error) { _ in resizeOverview() }
        .onChange(of: notice) { _ in resizeOverview() }
    }

    private func resizeOverview() {
        NotificationCenter.default.post(name: .minisAttachmentSizeChanged, object: "bot-overview")
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
                let entry = BotMemoryEntry(id: "onboarding:" + bot.id, owner: "bot:\(bot.id)", content: text, category: "preference", scope: "onboarding",
                    sourceSession: nil, sourceMessage: nil, evidence: "用户在 Bot 引导中明确选择：" + choices.joined(separator: "；"), automatic: false)
                _ = try BotMemoryStore.shared.save(entry, userInitiated: true)
            } catch { self.error = error.localizedDescription; return }
        }
        current.onboarding?.memorySaved = current.memoryEnabled != false
        current.onboarding?.selected = current.memoryEnabled == false ? [] : selected.sorted(); current.onboarding?.dismissed = true
        if !store.save(current) { error = "偏好处理完成，但卡片状态保存失败，请重试。" }
        else if current.memoryEnabled == false { notice = "长期记忆已关闭，本次选择未保存。可以直接开始聊天。" }
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
           let record = store.directDelegation(jobID: callback.jobId, sessionID: callback.childSessionId) {
            BotDelegationLink(record: record, incoming: true).frame(maxWidth: .infinity)
        } else if let sid = vm.sessionId,
                  let record = store.data.delegations.first(where: { $0.childSessionID == sid }), message.role == .user,
                  record.directExecution != true || message.content.hasPrefix("消息来自 \(record.fromName)\n\n") {
            HStack(spacing: 6) {
                if let bot = store.bot(record.fromBotID) { BotAvatar(profile: bot, size: 20) }
                Text("消息来自 \(record.fromName)")
                if record.directExecution != true { Text("· 只读委派消息").foregroundStyle(.secondary) }
            }.font(.caption).padding(.horizontal, 16)
        }
    }
}

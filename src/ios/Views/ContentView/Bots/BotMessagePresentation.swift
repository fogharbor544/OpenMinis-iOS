import Foundation
import SwiftUI
import UIKit

extension AIChatViewModel {
    func canQuoteMessage(_ message: ChatMessage) -> Bool {
        guard let sid = sessionId else { return false }
        return !isHelper && remoteDeviceId == nil && BotWorkspaceStore.shared.owner(forSession: sid)?.delegationID == nil
            && message.persistedMessageID != nil && !message.isCompactedHistory
            && (message.role == .assistant || (message.role == .user && message.agentCallback == nil))
    }
    func quoteMessage(_ message: ChatMessage) {
        guard let sessionID = sessionId, let messageID = message.persistedMessageID,
              !isHelper, BotWorkspaceStore.shared.owner(forSession: sessionID)?.delegationID == nil, !message.isCompactedHistory,
              message.role == .assistant || (message.role == .user && message.agentCallback == nil) else { return }
        let text = message.role == .assistant
            ? message.blocks.filter { $0.kind == .text }.map(\.content).joined(separator: "\n")
            : message.content
        guard !text.isEmpty else { return }
        let author = message.role == .user ? "你" : (BotWorkspaceStore.shared.bot(forSession: sessionID)?.name ?? "OpenMinis")
        pendingQuote = BotMessageQuote(sessionID: sessionID, messageID: messageID, author: author, text: String(text.prefix(12000)))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        NotificationCenter.default.post(name: .botQuoteSelected, object: sessionID)
    }
}

extension Notification.Name { static let botQuoteSelected = Notification.Name("botQuoteSelected") }

struct BotQuoteStrip: View {
    let quote: BotMessageQuote
    var onRemove: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(quote.author).font(.caption.weight(.semibold))
                Text(quote.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("取消引用")
            }
        }.fixedSize(horizontal: false, vertical: true).padding(10)
            .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct BotUnreadDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().frame(height: 0.5)
            Text("新消息").font(.caption.weight(.semibold)).fixedSize()
            Rectangle().frame(height: 0.5)
        }.foregroundStyle(Color.accentColor).padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// These are presentation rows only. They never enter model history or storage.
extension AIChatViewModel {
    func botTimelineMessages(_ raw: [ChatMessage]) -> [ChatMessage] {
        guard !isHelper, let sid = sessionId,
              let owner = BotWorkspaceStore.shared.owner(forSession: sid),
              owner.roomId == nil, owner.delegationID == nil,
              let bot = BotWorkspaceStore.shared.bot(owner.botId) else { return raw }
        let store = BotWorkspaceStore.shared
        let records = store.data.delegations.filter { $0.toBotID == bot.id }.sorted { $0.updatedAt > $1.updatedAt }
        var result = raw
        if bot.introduction != nil || bot.onboarding != nil || !records.isEmpty || bot.isCommander {
            botOverviewMessage.systemIcon = "bot-overview"
            // Include rendering data, not merely a string length, in the height identity.
            let taskRevision = records.prefix(3).map { record in
                [record.id, record.fromName, record.title, record.statusLabel,
                 String((record.result ?? "").prefix(1000))].joined(separator: "|")
            }.joined(separator: "\n")
            let revision = [bot.name, bot.introduction ?? "", String(describing: bot.onboarding),
                            String(describing: bot.memoryEnabled), String(records.count), taskRevision].joined(separator: "\n")
            if botOverviewMessage.content != revision { botOverviewMessage.content = revision }
            result.insert(botOverviewMessage, at: 0)
        }
        guard bot.isCommander else { return result }
        let created = store.data.bots.filter { $0.creationRequestID?.hasPrefix(sid + ":") == true }
        let byRequest = Dictionary(created.compactMap { target in target.creationRequestID.map { ($0, target) } },
                                   uniquingKeysWith: { first, _ in first })
        var inserted = Set<String>()
        result = result.flatMap { message -> [ChatMessage] in
            var rows = [message]
            guard message.role == .assistant else { return rows }
            for block in message.blocks {
                guard let call = block.toolUseId, let target = byRequest[sid + ":" + call],
                      inserted.insert(target.id).inserted else { continue }
                let row = botCreationMessages[target.id] ?? ChatMessage(role: .systemInfo, content: target.name)
                row.systemIcon = "bot-created:" + target.id
                if row.content != target.name { row.content = target.name }
                botCreationMessages[target.id] = row
                rows.append(row)
            }
            return rows
        }
        botCreationMessages = botCreationMessages.filter { inserted.contains($0.key) }
        return result
    }
}

struct BotCreatedCard: View {
    let botID: String
    @ObservedObject private var store = BotWorkspaceStore.shared
    @State private var showingChat = false
    var body: some View {
        if let bot = store.bot(botID) {
            VStack(alignment: .leading, spacing: 8) {
                Text("已创建的 Bot").font(.headline)
                Button { showingChat = true } label: {
                    HStack(spacing: 10) {
                        BotAvatar(profile: bot, size: 28)
                        Text(bot.name).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(16)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
                .overlay {
                    Color.clear.frame(width: 0, height: 0)
                        .sheet(isPresented: $showingChat) { BotOpenedChat(botID: botID) }
                }
        }
    }
}

/// Shared by real cells and first-layout measurement, at the same text size/width.
struct BotTimelineRow: View {
    let message: ChatMessage
    var body: some View {
        Group {
            if message.systemIcon == "bot-overview" { BotConversationOverview() }
            else if let icon = message.systemIcon, icon.hasPrefix("bot-created:") {
                BotCreatedCard(botID: String(icon.dropFirst("bot-created:".count)))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
    static func contains(_ message: ChatMessage) -> Bool {
        message.systemIcon == "bot-overview" || message.systemIcon?.hasPrefix("bot-created:") == true
    }
}

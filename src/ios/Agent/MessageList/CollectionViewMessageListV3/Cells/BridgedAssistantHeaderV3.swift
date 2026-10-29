import SwiftUI

struct BridgedAssistantHeaderV3: View {
    @ObservedObject var message: ChatMessage
    @EnvironmentObject private var vm: AIChatViewModel
    @ObservedObject private var workspace = BotWorkspaceStore.shared
    var maxWidth: CGFloat = 0
    private var bot: BotProfile? { vm.sessionId.flatMap { workspace.bot(forSession: $0) } }
    var body: some View {
        HStack(spacing: 6) {
            if let bot { BotAvatar(profile: bot, size: 22) }
            else { Image(systemName: "sparkles") }
            Text(bot?.name ?? "OpenMinis")
                .font(.body.weight(.semibold))
                .foregroundStyle(ChatColors.primaryText)
        }
        .accessibilityElement(children: .combine)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: maxWidth > 0 ? maxWidth : .infinity, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .opacity(message.isCompactedHistory ? 0.5 : 1.0)
        .accessibilityIdentifier("assistantHeader")
    }
}

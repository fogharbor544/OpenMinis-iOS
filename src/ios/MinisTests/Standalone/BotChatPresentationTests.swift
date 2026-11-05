import Foundation

enum ChatMessageRole { case user, assistant, systemInfo }
struct AssistantBlock { var toolUseId: String? }
final class ChatMessage {
    let id = UUID()
    let timestamp = Date()
    var sourceCreatedAt: Date?
    let role: ChatMessageRole
    var content: String
    var blocks: [AssistantBlock]
    var systemIcon: String?
    init(role: ChatMessageRole, content: String, blocks: [AssistantBlock] = []) {
        self.role = role; self.content = content; self.blocks = blocks
    }
}
@MainActor final class AIChatViewModel {
    var sessionId: String? = "parent"
    var isHelper = false
    let botOverviewMessage = ChatMessage(role: .systemInfo, content: "")
    var botDelegationMessages: [String: ChatMessage] = [:]
    var botCreationMessages: [String: ChatMessage] = [:]
}

@main struct BotChatPresentationTests {
    @MainActor static func main() {
        let store = BotWorkspaceStore.shared
        var commander = store.bot(BotProfile.commanderID)!
        commander.sessionId = "parent"; commander.conversationIds = ["parent", "other-parent"]
        precondition(store.save(commander))
        var target = store.newBot(); target.name = "配置助手"; target.introduction = "我来处理配置。"
        target.creationRequestID = "parent:create-call"
        target.onboarding = BotOnboarding(question: "关注什么？", options: ["模型", "存储"])
        precondition(store.save(target))
        var data = store.data
        data.sessionOwners["parent"] = BotSessionOwner(botId: commander.id)
        data.sessionOwners["other-parent"] = BotSessionOwner(botId: commander.id)
        data.sessionOwners["private"] = BotSessionOwner(botId: target.id)
        precondition(store.persist(data))
        let user = ChatMessage(role: .user, content: "创建配置助手")
        let tool = ChatMessage(role: .assistant, content: "", blocks: [.init(toolUseId: "create-call")])
        let final = ChatMessage(role: .assistant, content: "已创建配置助手。")
        let vm = AIChatViewModel()
        let first = vm.botTimelineMessages([user, tool, final])
        precondition(first.count == 5)
        precondition(first[0].systemIcon == "bot-overview")
        precondition(first[1] === user && first[2] === tool && first[4] === final)
        precondition(first[3].systemIcon == "bot-created:" + target.id)
        let again = vm.botTimelineMessages([user, tool, final])
        precondition(again[3] === first[3], "Stable card identity across streaming/updates")
        tool.blocks.append(.init(toolUseId: "create-call"))
        precondition(vm.botTimelineMessages([user, tool, final]).count == 5, "Repeated block cannot duplicate creation card")
        vm.sessionId = "other-parent"
        precondition(vm.botTimelineMessages([user, tool, final]).count == 4, "No creation card leaks into another conversation")
        vm.sessionId = "private"
        let before = vm.botTimelineMessages([])
        precondition(before.count == 1 && before[0].systemIcon == "bot-overview")
        let originalRevision = before[0].content
        var task = BotDelegation(id: "task", fromBotID: commander.id, toBotID: target.id,
            fromName: commander.name, toName: target.name, parentSessionID: "parent", toolUseID: "delegate-call",
            title: "检查配置", task: "核查当前配置并报告结果")
        precondition(store.saveDelegation(task))
        let queued = vm.botTimelineMessages([])
        precondition(queued.count == 2 && queued[1].systemIcon == "bot-task:" + task.id)
        precondition(queued[0].content == originalRevision, "Task does not hide in overview")
        let card = queued[1]
        let queuedRevision = card.content
        precondition(queuedRevision.contains(task.title))
        let older = ChatMessage(role: .user, content: "Older private message")
        older.sourceCreatedAt = task.createdAt.addingTimeInterval(-10)
        let newer = ChatMessage(role: .assistant, content: "Newer private reply")
        newer.sourceCreatedAt = task.createdAt.addingTimeInterval(10)
        let timeline = vm.botTimelineMessages([older, newer])
        precondition(timeline.count == 4 && timeline[1] === older && timeline[2] === card && timeline[3] === newer)
        task.state = .completed; task.result = "配置核查完成。"
        precondition(store.saveDelegation(task))
        store.delegationMessageCounts[task.id] = 2
        let completed = vm.botTimelineMessages([older, newer])
        precondition(completed[2] === card && card.content != queuedRevision && card.content.contains("已交付"))
        precondition(vm.botTimelineMessages([older, newer]).count == 4, "Reopening/refresh never duplicates a task")
        target.onboarding?.dismissed = true
        precondition(store.save(target))
        precondition(vm.botTimelineMessages([])[0].content != originalRevision, "Dismissal changes overview revision")
        precondition(store.delegationPreview(botID: target.id)?.contains(commander.name) == true)
        precondition(store.delegationPreview(botID: target.id, after: Date().addingTimeInterval(60)) == nil)
        vm.isHelper = true
        precondition(vm.botTimelineMessages([user, final]).map(\.id) == [user.id, final.id])
        vm.isHelper = false; vm.sessionId = "parent"
        let oldCard = vm.botTimelineMessages([user, tool, final])[3]
        target.name = "设置助手"; precondition(store.save(target))
        let renamed = vm.botTimelineMessages([user, tool, final])[3]
        precondition(renamed === oldCard && renamed.content == "设置助手", "Same-length name edits refresh the card")
        precondition(store.deleteBot(target.id) != nil)
        precondition(vm.botTimelineMessages([user, tool, final]).count == 4)
        precondition(vm.botCreationMessages.isEmpty)
        print("PASS: shipping Bot timeline ordering, stable identity, deduplication, conversation isolation, empty-chat task/result refresh, onboarding dismissal, rename and deletion")
    }
}

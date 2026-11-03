import Foundation
enum ProgrammaticPromptOrigin { case job(jobId: String) }

enum ThinkingLevel { case off }
struct AgentToolDefinition {
    var name: String
    var categoryValues: [String] = []
    var eventKindValues: [String] = []

    init(name: String, categoryValues: [String] = [], eventKindValues: [String] = []) {
        self.name = name
        self.categoryValues = categoryValues
        self.eventKindValues = eventKindValues
    }
}
struct AgentMessage {
    enum Role { case user }
    enum Part { case text(String) }
    var role: Role; var parts: [Part]
}
struct LLMUsage {
    var inputTokens: Int; var outputTokens: Int
    var cacheReadInputTokens: Int? = nil; var cacheCreationInputTokens: Int? = nil
}
enum AgentStreamEvent {
    case toolCallComplete(id: String, name: String, args: [String: Any], metadata: String?)
    case usage(LLMUsage)
}
protocol AgentProvider {
    var defaultMaxTokens: Int { get }
    func streamAgentMessage(messages: [AgentMessage], systemPrompt: String?, tools: [AgentToolDefinition],
                            maxTokens: Int, thinkingLevel: ThinkingLevel) async throws -> AsyncThrowingStream<AgentStreamEvent, Error>
}
final class MemoryReviewProvider: AgentProvider {
    let defaultMaxTokens = 2048
    var calls = 0
    var beforeResponse: (@MainActor () -> Void)?
    func streamAgentMessage(messages: [AgentMessage], systemPrompt: String?, tools: [AgentToolDefinition],
                            maxTokens: Int, thinkingLevel: ThinkingLevel) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        calls += 1
        precondition(tools.map(\.name) == ["memory_write"] && maxTokens <= 1024)
        await beforeResponse?()
        return AsyncThrowingStream { continuation in
            continuation.yield(.usage(LLMUsage(inputTokens: 10, outputTokens: 5)))
            continuation.yield(.toolCallComplete(id: "other", name: "shell_execute", args: ["command": "must not execute"], metadata: nil))
            continuation.yield(.toolCallComplete(id: "note", name: "memory_write", args: ["content": "Prefers source links", "action": "forget", "entry_id": "must not delete"], metadata: nil))
            continuation.finish()
        }
    }
}

final class EventMemoryReviewProvider: AgentProvider {
    let defaultMaxTokens = 2048
    var calls = 0
    func streamAgentMessage(messages: [AgentMessage], systemPrompt: String?, tools: [AgentToolDefinition],
                            maxTokens: Int, thinkingLevel: ThinkingLevel) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        calls += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(.toolCallComplete(id: "event-1", name: "memory_write", args: [
                "content": "决策：保持事件记忆作用域", "category": "event", "event_kind": "decision", "intent": "automatic", "scope": "memory-design"
            ], metadata: nil))
            continuation.yield(.toolCallComplete(id: "event-2", name: "memory_write", args: [
                "content": "交付：事件记忆方案已接入", "category": "event", "event_kind": "delivery", "intent": "automatic", "scope": "memory-design"
            ], metadata: nil))
            continuation.yield(.toolCallComplete(id: "normal", name: "memory_write", args: [
                "content": "偏好：事件摘要要短", "category": "preference", "intent": "automatic", "scope": "writing"
            ], metadata: nil))
            continuation.finish()
        }
    }
}

final class VerificationEventReviewProvider: AgentProvider {
    let defaultMaxTokens = 2048
    var calls = 0
    func streamAgentMessage(messages: [AgentMessage], systemPrompt: String?, tools: [AgentToolDefinition],
                            maxTokens: Int, thinkingLevel: ThinkingLevel) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        calls += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(.toolCallComplete(id: "verification", name: "memory_write", args: [
                "content": "Unverified: release tests", "evidence": "No tool output is available", "category": "event", "event_kind": "verification", "intent": "automatic", "scope": "memory-design"
            ], metadata: nil))
            continuation.finish()
        }
    }
}

@MainActor final class AIChatViewModel {
    struct FileToolResult { let output: String; let success: Bool }
    struct Message {
        enum Role { case user, assistant }
        var id = UUID()
        var historyAnchorId: UUID?
        var role: Role = .user
        var content: String
        var isQueued = false
        var isCompactedHistory = false
    }
    struct History {
        enum Role { case user, assistant }
        var anchorId: UUID; var dbMessageId: String?; var role = Role.user
    }
    var agentHistory: [History] = []
    func loadUser(_ text: String, rowID: String = UUID().uuidString) {
        let anchor = UUID()
        messages = [.init(historyAnchorId: anchor, content: text)]
        agentHistory = [.init(anchorId: anchor, dbMessageId: rowID),
                        .init(anchorId: UUID(), dbMessageId: rowID + "-assistant", role: .assistant)]
    }
    var sessionId: String?
    var helperConfig: String?
    var userDidCancel = false
    var canResume = false
    var botMemoryReviewTask: Task<Void, Never>?
    var botMemoryReviewedSourceID: String?
    var botMemoryEventReviewedSourceID: String?
    var transientNotice: String?
    var sessionInputTokens = 0, sessionOutputTokens = 0, sessionCacheReadTokens = 0, sessionCacheWriteTokens = 0
    func makeAgentTools() -> [AgentToolDefinition] {
        [.init(name: "memory_write",
               categoryValues: ["preference", "fact", "convention", "experience", "event"],
               eventKindValues: ["decision", "delivery", "verification"])]
    }
    var memoryEnabled = true
    var messages: [Message] = []
    var programmaticTurnOrigin: ProgrammaticPromptOrigin?
}

actor ChatStore {
    static let shared = ChatStore()
    var usages: [String: StoredTokenUsage] = [:]
    func addAuxiliaryUsage(_ usage: StoredTokenUsage, messageID: String, sessionID: String) -> Bool {
        var stored = usages[messageID] ?? StoredTokenUsage(inputTokens: 100, outputTokens: 20, cacheCreationTokens: 0, cacheReadTokens: 0, latestContextTokens: 120)
        stored.addAuxiliaryUsage(usage); usages[messageID] = stored
        return true
    }
    func storedUsage(_ id: String) -> StoredTokenUsage? { usages[id] }
}

@main struct BotMemoryRuntimeTests {
    @MainActor static func main() async throws {
        let workspace = BotWorkspaceStore.shared
        var a = BotProfile(name: "A"); a.sessionId = "private-a"
        var b = BotProfile(name: "B"); b.sessionId = "private-b"
        precondition(workspace.save(a) && workspace.save(b))
        var room = BotRoom(name: "Group", members: [a.id, b.id])
        room.sessions = [a.id: "group-a"]
        room.messages = [BotRoomMessage(speaker: String(localized: "You"), text: "I always prefer diagrams")]
        precondition(workspace.save(room))
        var initial = workspace.data
        initial.sessionOwners = [
            "private-a": BotSessionOwner(botId: a.id),
            "private-b": BotSessionOwner(botId: b.id),
            "group-a": BotSessionOwner(botId: a.id, roomId: room.id)
        ]
        precondition(workspace.persist(initial))
        let temporaryChat = AIChatViewModel(); temporaryChat.sessionId = "temporary"
        precondition(temporaryChat.botMemoryFragment() == nil)
        precondition(!temporaryChat.executeBotMemoryGet("{}").success)
        let vm = AIChatViewModel(); vm.sessionId = "private-a"
        let words = "I always prefer concise answers"
        vm.loadUser(words, rowID: "original-row")
        let args: [String: String] = ["action": "save", "content": "Prefers concise answers", "evidence": words,
            "intent": "automatic", "category": "preference", "scope": "writing"]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self)
        let result = vm.executeBotMemoryWrite(json)
        precondition(result.success)
        let saved = try BotMemoryStore.shared.visible(to: "bot:\(a.id)")
        precondition(saved.count == 1 && saved[0].content == "Prefers concise answers")
        let other = AIChatViewModel(); other.sessionId = "private-b"
        precondition(!other.executeBotMemoryGet("{}").output.contains("Prefers concise answers"))
        let group = AIChatViewModel(); group.sessionId = "group-a"
        group.programmaticTurnOrigin = .job(jobId: "bot-room-\(room.id)")
        precondition(group.botMemorySource?.text == "I always prefer diagrams")
        group.programmaticTurnOrigin = .job(jobId: "unrelated-schedule")
        precondition(group.botMemorySource == nil)
        group.programmaticTurnOrigin = nil
        group.loadUser("I usually use clear charts")
        precondition(group.botMemorySource?.text == "I usually use clear charts")
        precondition(!group.executeBotMemoryGet("{}").output.contains("Prefers concise answers"))
        try BotMemoryStore.shared.setGrants(id: saved[0].id, owner: saved[0].owner, grants: ["room:\(room.id)"])
        precondition(group.executeBotMemoryGet("{}").output.contains("Prefers concise answers"))
        try BotMemoryStore.shared.forget(id: saved[0].id, owner: saved[0].owner)
        precondition(!group.executeBotMemoryGet("{}").output.contains("Prefers concise answers"))
        vm.loadUser(words, rowID: "original-row") // New UI anchor, same persisted row.
        precondition(!vm.executeBotMemoryWrite(json).success)
        let explicitWords = "Remember I always prefer concise answers"
        let explicitArgs = "{\"action\":\"save\",\"content\":\"I always prefer concise answers\",\"evidence\":\"I always prefer concise answers\",\"intent\":\"explicit\",\"category\":\"preference\",\"scope\":\"writing\"}"
        vm.loadUser(explicitWords, rowID: "explicit-original")
        precondition(vm.executeBotMemoryWrite(explicitArgs).success)
        let explicitSaved = try BotMemoryStore.shared.visible(to: "bot:\(a.id)").first!
        try BotMemoryStore.shared.forget(id: explicitSaved.id, owner: explicitSaved.owner)
        vm.loadUser(explicitWords, rowID: "explicit-original")
        precondition(!vm.executeBotMemoryWrite(explicitArgs).success)
        vm.loadUser(explicitWords, rowID: "explicit-new")
        precondition(vm.executeBotMemoryWrite(explicitArgs).success)
        // Ordinary save does not depend on current-user quotes or durable-keyword gates.
        vm.loadUser("The migration is ready for review")
        let note = "{\"content\":\"Project migration ready for review\"}"
        precondition(vm.executeBotMemoryWrite(note).success)
        precondition(vm.botMemoryFragment()?.contains("Project migration ready for review") == true)
        vm.loadUser("Unrelated new question")
        precondition(vm.botMemoryFragment()?.contains("Project migration ready for review") == true)
        precondition(!vm.executeBotMemoryWrite("{\"action\":\"replace\",\"entry_id\":\"missing\",\"content\":\"changed\"}").success)
        precondition(!vm.executeBotMemoryWrite("{\"action\":\"forget\",\"entry_id\":\"missing\"}").success)
        precondition(!vm.executeBotMemoryWrite("{\"content\":\"password is secret\"}").success)
        let memoryTools = vm.makeAgentTools()
        precondition(memoryTools.contains { $0.categoryValues.contains("event") })
        precondition(memoryTools.contains { $0.eventKindValues == ["decision", "delivery", "verification"] })
        vm.loadUser("Remember that we decided to use scoped memories", rowID: "event-source")
        let eventJSON = "{\"action\":\"save\",\"content\":\"决策：Bot 继续使用作用域记忆\",\"category\":\"event\",\"event_kind\":\"decision\",\"intent\":\"explicit\",\"scope\":\"memory-design\"}"
        precondition(vm.executeBotMemoryWrite(eventJSON).success)
        let savedEvent = try BotMemoryStore.shared.visible(to: "bot:\(a.id)").last { $0.category == "event" }!
        precondition(savedEvent.eventKind == "decision" && savedEvent.sourceMessage == "event-source")
        precondition(!vm.executeBotMemoryWrite("{\"action\":\"save\",\"content\":\"Bad event\",\"category\":\"event\",\"event_kind\":\"milestone\"}").success)
        precondition(!vm.executeBotMemoryWrite("{\"action\":\"save\",\"content\":\"普通记忆\",\"category\":\"fact\",\"event_kind\":\"decision\"}").success)
        vm.messages = [.init(content: explicitWords)] // Provenance is optional for a new note.
        precondition(vm.botMemorySource == nil)
        vm.programmaticTurnOrigin = .job(jobId: "scheduled-job")
        precondition(vm.botMemorySource == nil)
        precondition(vm.executeBotMemoryWrite("{\"content\":\"Verified scheduled task outcome\",\"category\":\"experience\"}").success)
        vm.programmaticTurnOrigin = nil
        // A completed answer without a memory call gets one bounded, read-only
        // selection request. Candidate actions are normalized to additive saves.
        let reviewer = MemoryReviewProvider()
        vm.loadUser("I prefer source links in research replies", rowID: "review-source")
        vm.scheduleBotMemoryReview(provider: reviewer)
        await vm.botMemoryReviewTask?.value
        precondition(reviewer.calls == 1)
        precondition(vm.executeBotMemoryGet("{}").output.contains("Prefers source links"))
        precondition(vm.transientNotice?.contains("已记住") == true)
        precondition(vm.sessionInputTokens == 10 && vm.sessionOutputTokens == 5)
        let storedUsage = await ChatStore.shared.storedUsage("review-source-assistant")!
        precondition(storedUsage.inputTokens == 100 && storedUsage.latestContextTokens == 120)
        precondition(storedUsage.billedUsage.inputTokens == 110 && storedUsage.billedUsage.outputTokens == 25)
        precondition(!BotMemoryStore.shared.hasPendingReviews)
        vm.scheduleBotMemoryReview(provider: reviewer)
        precondition(vm.botMemoryReviewTask == nil && reviewer.calls == 1, "One review per persisted user source")
        precondition(vm.botMemoryEventReviewedSourceID == "review-source")
        vm.loadUser("The actual password is sensitive", rowID: "secret-source")
        vm.scheduleBotMemoryReview(provider: reviewer)
        precondition(vm.botMemoryReviewTask == nil && reviewer.calls == 1)
        vm.loadUser("I prefer API key storage in Keychain", rowID: "safe-review-source")
        reviewer.beforeResponse = { vm.loadUser("A newer message", rowID: "new-source") }
        vm.transientNotice = nil
        vm.scheduleBotMemoryReview(provider: reviewer)
        await vm.botMemoryReviewTask?.value
        precondition(vm.transientNotice == nil, "Stale review cannot save into a newer turn")
        let staleUsage = await ChatStore.shared.storedUsage("safe-review-source-assistant")
        precondition(staleUsage?.auxiliaryInputTokens == 10, "Already reported usage survives a stale source guard")
        reviewer.beforeResponse = nil
        // Ordinary tool-written preferences must not make the final review skip an event.
        vm.loadUser("Remember that summaries should stay short for event reviews", rowID: "event-review-source")
        precondition(vm.executeBotMemoryWrite("{\"action\":\"save\",\"content\":\"偏好：事件摘要要短\",\"category\":\"preference\",\"intent\":\"explicit\",\"scope\":\"writing\"}").success)
        let eventReviewer = EventMemoryReviewProvider()
        vm.scheduleBotMemoryReview(provider: eventReviewer,
                                  assistantSnapshot: (id: "event-review-source-assistant",
                                                      text: "Bot report: event memory integration delivered"))
        await vm.botMemoryReviewTask?.value
        precondition(eventReviewer.calls == 1)
        let eventRows = try BotMemoryStore.shared.visible(to: "bot:\(a.id)").filter { $0.category == "event" }
        precondition(eventRows.filter { $0.sourceMessage == "event-review-source" }.count == 1)
        try check(BotMemoryStore.shared.visible(to: "bot:\(a.id)").contains { $0.content == "偏好：事件摘要要短" && $0.sourceMessage == "event-review-source" })
        precondition(vm.botMemoryEventReviewedSourceID == "event-review-source")
        try check(BotMemoryStore.shared.visible(to: "bot:\(a.id)").contains {
            $0.sourceMessage == "event-review-source" && $0.sourceAssistantMessageID == "event-review-source-assistant"
        })
        // Assistant-supplied credentials never reach the review request.
        vm.loadUser("Review this assistant result", rowID: "secret-assistant-source")
        vm.scheduleBotMemoryReview(provider: reviewer,
                                  assistantSnapshot: (id: "secret-assistant-source-assistant",
                                                      text: "password=tiny-secret-value"))
        precondition(vm.botMemoryReviewTask == nil && reviewer.calls == 2)
        // Generated evidence and negative wording cannot promote a report to independent verification.
        vm.loadUser("User confirmed the verification result", rowID: "verification-source")
        let verificationReviewer = VerificationEventReviewProvider()
        vm.scheduleBotMemoryReview(provider: verificationReviewer,
                                  assistantSnapshot: (id: "verification-source-assistant",
                                                      text: "No evidence of verification"))
        await vm.botMemoryReviewTask?.value
        precondition(verificationReviewer.calls == 1)
        try check(BotMemoryStore.shared.visible(to: "bot:\(a.id)").contains {
            $0.sourceMessage == "verification-source" && $0.eventKind == "verification" &&
            $0.content == "Bot report (not independently verified): Unverified: release tests" &&
            $0.evidence == "Assistant final reply; not independently verified"
        })
        vm.helperConfig = "specialist"
        vm.scheduleBotMemoryReview(provider: reviewer)
        precondition(vm.botMemoryReviewTask == nil && reviewer.calls == 2)
        vm.helperConfig = nil
        vm.loadUser("I prefer concise replies", rowID: "cancelled-review")
        vm.scheduleBotMemoryReview(provider: reviewer)
        let cancelledReview = vm.botMemoryReviewTask
        cancelledReview?.cancel()
        await cancelledReview?.value
        precondition(reviewer.calls == 2, "Cancelled review must not open a provider request")
        vm.memoryEnabled = false
        vm.loadUser("I prefer metric units", rowID: "disabled-review")
        vm.scheduleBotMemoryReview(provider: reviewer)
        precondition(vm.botMemoryReviewTask == nil && reviewer.calls == 2)
        precondition(vm.botMemoryFragment() == nil && !vm.executeBotMemoryGet("{}").success)
        // Persist ownership before deletion, as session creation does in production.
        var data = workspace.data
        data.sessionOwners = ["private-a": BotSessionOwner(botId: a.id)]
        precondition(workspace.persist(data))
        workspace.deleteBot(a.id)
        precondition(vm.botMemoryOwner != nil && !vm.botMemoryAvailable)
        precondition(!vm.executeBotMemoryGet("{}").success)
        print("PASS: runtime owner isolation, group opt-in sharing, summarized proactive saves, optional provenance, reload tombstones, scheduled notes, bounded automatic review, usage, stale-source and cancellation gates, toggle and deleted-owner refusal")
    }
}

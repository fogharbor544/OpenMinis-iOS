import Foundation
enum ProgrammaticPromptOrigin { case job(jobId: String) }

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
    struct History { var anchorId: UUID; var dbMessageId: String? }
    var agentHistory: [History] = []
    func loadUser(_ text: String, rowID: String = UUID().uuidString) {
        let anchor = UUID()
        messages = [.init(historyAnchorId: anchor, content: text)]
        agentHistory = [.init(anchorId: anchor, dbMessageId: rowID)]
    }
    var sessionId: String?
    var memoryEnabled = true
    var messages: [Message] = []
    var programmaticTurnOrigin: ProgrammaticPromptOrigin?
}

@main struct BotMemoryRuntimeTests {
    @MainActor static func main() throws {
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
        let args: [String: String] = ["action": "save", "content": "An unsupported inference", "evidence": words,
            "intent": "automatic", "category": "preference", "scope": "writing"]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self)
        let result = vm.executeBotMemoryWrite(json)
        precondition(result.success)
        let saved = try BotMemoryStore.shared.visible(to: "bot:\(a.id)")
        precondition(saved.count == 1 && saved[0].content == words)
        let other = AIChatViewModel(); other.sessionId = "private-b"
        precondition(!other.executeBotMemoryGet("{}").output.contains(words))
        let group = AIChatViewModel(); group.sessionId = "group-a"
        group.programmaticTurnOrigin = .job(jobId: "bot-room-\(room.id)")
        precondition(group.botMemorySource?.text == "I always prefer diagrams")
        group.programmaticTurnOrigin = .job(jobId: "unrelated-schedule")
        precondition(group.botMemorySource == nil)
        group.programmaticTurnOrigin = nil
        group.loadUser("I usually use clear charts")
        precondition(group.botMemorySource?.text == "I usually use clear charts")
        precondition(!group.executeBotMemoryGet("{}").output.contains(words))
        try BotMemoryStore.shared.setGrants(id: saved[0].id, owner: saved[0].owner, grants: ["room:\(room.id)"])
        precondition(group.executeBotMemoryGet("{}").output.contains(words))
        try BotMemoryStore.shared.forget(id: saved[0].id, owner: saved[0].owner)
        precondition(!group.executeBotMemoryGet("{}").output.contains(words))
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
        vm.messages = [.init(content: explicitWords)] // No durable identity yet.
        precondition(vm.botMemorySource == nil)
        vm.programmaticTurnOrigin = .job(jobId: "scheduled-job")
        precondition(vm.botMemorySource == nil && !vm.executeBotMemoryWrite(json).success)
        vm.programmaticTurnOrigin = nil
        vm.memoryEnabled = false
        precondition(vm.botMemoryFragment() == nil && !vm.executeBotMemoryGet("{}").success)
        // Persist ownership before deletion, as session creation does in production.
        var data = workspace.data
        data.sessionOwners = ["private-a": BotSessionOwner(botId: a.id)]
        precondition(workspace.persist(data))
        workspace.deleteBot(a.id)
        precondition(vm.botMemoryOwner != nil && !vm.botMemoryAvailable)
        precondition(!vm.executeBotMemoryGet("{}").success)
        print("PASS: runtime owner isolation, group opt-in sharing, quote-only automatic saves, reload tombstones, generated-input refusal, toggle and deleted-owner refusal")
    }
}

import Foundation

@MainActor final class AIChatViewModel {
    struct FileToolResult { let output: String; let success: Bool }
    struct Message {
        enum Role { case user, assistant }
        var id = UUID()
        var role: Role = .user
        var content: String
        var isQueued = false
        var isCompactedHistory = false
    }
    var sessionId: String?
    var memoryEnabled = true
    var messages: [Message] = []
    var programmaticTurnOrigin: String?
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
        let vm = AIChatViewModel(); vm.sessionId = "private-a"
        let words = "I always prefer concise answers"
        vm.messages = [.init(content: words)]
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
        precondition(!group.executeBotMemoryGet("{}").output.contains(words))
        try BotMemoryStore.shared.setGrants(id: saved[0].id, owner: saved[0].owner, grants: ["room:\(room.id)"])
        precondition(group.executeBotMemoryGet("{}").output.contains(words))
        try BotMemoryStore.shared.forget(id: saved[0].id, owner: saved[0].owner)
        precondition(!group.executeBotMemoryGet("{}").output.contains(words))
        vm.messages = [.init(content: words)] // New UI UUID, same persisted source text.
        precondition(!vm.executeBotMemoryWrite(json).success)
        vm.programmaticTurnOrigin = "scheduled-job"
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

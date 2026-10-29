import Foundation

struct TestSession { let id: String }
actor ChatStore {
    static let shared = ChatStore()
    var sessions: [String: TestSession] = [:]
    func getSession(_ id: String) -> TestSession? { sessions[id] }
    func createSession(modelId: String, title: String, source: String) -> TestSession {
        let session = TestSession(id: UUID().uuidString)
        sessions[session.id] = session
        return session
    }
    func remove(_ id: String) { sessions[id] = nil }
    func count() -> Int { sessions.count }
    func getMemoryEnabled(sessionId: String) -> Bool { false }
}
struct TestModel { let id = "model" }
struct TestEntry { let model = TestModel() }
struct TestGroup { let id: String }
struct SessionModelBinding {
    enum Source { case group(groupId: String, resolvedEntryId: String) }
    let sessionId: String
    let primarySource: Source
}
@MainActor final class ProviderConfigStore {
    static let shared = ProviderConfigStore()
    var defaultPrimaryGroupId: String? = "default"
    var bindings: [String: SessionModelBinding] = [:]
    func group(for id: String) -> TestGroup? { ["default", "alternate"].contains(id) ? TestGroup(id: id) : nil }
    func entry(for id: String) -> TestEntry? { TestEntry() }
    func setBinding(_ binding: SessionModelBinding, for id: String) { bindings[id] = binding }
}
@MainActor enum ModelGroupRouter {
    static func resolve(group: TestGroup, sessionId: String, store: ProviderConfigStore) -> String? { group.id + "-entry" }
}
struct TestCapability { let id: String }
@MainActor final class SkillStore {
    static let shared = SkillStore()
    let skills = [TestCapability(id: "skill")]
    var choices: [String: Bool] = [:]
    func setSessionOverride(skillId: String, sessionId: String, enabled: Bool) { choices[sessionId + skillId] = enabled }
    func isEnabledForSession(_ id: String, sessionId: String) -> Bool { choices[sessionId + id] ?? true }
}
@MainActor final class MCPStore {
    static let shared = MCPStore()
    let servers = [TestCapability(id: "server")]
    var choices: [String: Bool] = [:]
    func setSessionOverride(serverId: String, sessionId: String, enabled: Bool) { choices[sessionId + serverId] = enabled }
    func isEnabledForSession(_ id: String, sessionId: String) -> Bool { choices[sessionId + id] ?? true }
}
@main struct BotSessionBindings {
    @MainActor static func main() async throws {
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        let store = BotWorkspaceStore(fileURL: file)
        let bot = BotProfile(name: "Assistant")
        precondition(store.save(bot))
        let privateID = try await store.session(botID: bot.id)
        let reopened = try await store.session(botID: bot.id)
        precondition(privateID == reopened)
        let initialCount = await ChatStore.shared.count()
        precondition(initialCount == 1)
        let reloaded = BotWorkspaceStore(fileURL: file)
        let restored = try await reloaded.session(botID: bot.id)
        precondition(restored == privateID)
        SkillStore.shared.setSessionOverride(skillId: "skill", sessionId: privateID, enabled: false)
        MCPStore.shared.setSessionOverride(serverId: "server", sessionId: privateID, enabled: false)
        let room = BotRoom(name: "Team", members: [bot.id])
        precondition(store.save(room))
        let groupID = try await store.session(botID: bot.id, roomID: room.id)
        precondition(groupID != privateID)
        precondition(store.bot(bot.id)?.skillOverrides != nil)
        precondition(store.bot(bot.id)?.connectorOverrides != nil)
        SkillStore.shared.setSessionOverride(skillId: "skill", sessionId: privateID, enabled: true)
        let sameGroup = try await store.session(botID: bot.id, roomID: room.id)
        precondition(sameGroup == groupID)
        var edited = store.bot(bot.id)!
        edited.modelGroupId = "alternate"
        precondition(store.save(edited))
        for id in [privateID, groupID] {
            guard case .group(let group, let entry) = ProviderConfigStore.shared.bindings[id]?.primarySource else {
                fatalError("Missing binding")
            }
            precondition(group == "default" && entry == "default-entry")
        }
        await ChatStore.shared.remove(privateID)
        let replacement = try await store.session(botID: bot.id)
        precondition(replacement != privateID && store.bot(bot.id)?.sessionId == replacement)
        let freshTask = try await store.session(botID: bot.id, newConversation: true)
        precondition(freshTask != replacement && store.bot(bot.id)?.sessionId == freshTask)
        precondition(store.bot(bot.id)?.conversationIds.contains(replacement) == true)
        precondition(store.bot(forSession: replacement)?.id == bot.id)
        let selected = await store.selectConversation(replacement, botID: bot.id)
        precondition(selected)
        let deletedSelected = await store.selectConversation(privateID, botID: bot.id)
        precondition(!deletedSelected && store.bot(bot.id)?.sessionId == replacement)
        let resumed = try await store.session(botID: bot.id)
        precondition(resumed == replacement)
        let restoredWorkspace = BotWorkspaceStore(fileURL: file)
        precondition(restoredWorkspace.owner(forSession: freshTask)?.botId == bot.id)
        store.deleteBot(bot.id)
        precondition(store.owner(forSession: freshTask)?.botId == bot.id)
        let preserved = await ChatStore.shared.getSession(groupID)
        precondition(preserved != nil)
        let invalid = BotProfile(name: "No model", modelGroupId: "missing")
        precondition(store.save(invalid))
        do {
            _ = try await store.session(botID: invalid.id)
            fatalError("Invalid model group was accepted")
        } catch BotWorkspaceError.noModel {}
        print("PASS: shipping Bot session reuse/reload, isolated group sessions, skill/MCP inheritance, model rebinding, deleted-session recovery and history preservation")
    }
}

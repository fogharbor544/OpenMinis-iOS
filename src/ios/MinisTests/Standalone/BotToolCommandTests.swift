import Foundation

enum AgentParamType { case string, array }
indirect enum AgentSchemaNode {
    case string(description: String?, enumValues: [String]? = nil)
    case array(description: String?, items: AgentSchemaNode, minItems: Int? = nil, maxItems: Int? = nil)
}
struct AgentToolParam {
    var type: AgentParamType; var description: String
    var enumValues: [String]? = nil; var schema: AgentSchemaNode? = nil
}
struct AgentToolDefinition {
    var name: String; var description: String; var parameters: [String: AgentToolParam]; var required: [String]
}
@MainActor final class AgentJobRegistry {
    static let shared = AgentJobRegistry()
    static let maxQueuedDelegationsPerParent = 16
    var cancelled: [String] = []
    func cancel(jobId: String, reason: String) { cancelled.append(jobId) }
}
@MainActor final class BotTeamRuntime {
    static let shared = BotTeamRuntime()
    var starts = 0
    var steers: [(String, String)] = []
    var stops: [String] = []
    func steer(_ id: String, message: String) -> Bool { steers.append((id, message)); return true }
    func stopExecution(_ id: String, reason: String) { stops.append(id) }
    func start() { starts += 1 }
}
struct AgentCallback {
    enum Kind { case finished }
    var kind: Kind; var jobId: String; var childSessionId: String?
    var body = ""
    static func parse(_ text: String) -> AgentCallback? { nil }
}
@MainActor final class AIChatViewModel {
    enum ToolSwitch { case agents }
    static var agentsEnabled = true
    var botResultDeliveries: [String: Date] = [:]
    var userDidCancel = false
    var canResume = false
    var sessionId: String?; var isHelper = false; var programmaticTurnOrigin: String?
    var helperConfig: String?
    var steers: [[String: Any]] = []
    static func toolEnabled(_ value: ToolSwitch) -> Bool { agentsEnabled }
    static func jsonString(_ value: [String: Any]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self) }
    func executeAgentStatus(args: [String: Any]) -> (output: String, success: Bool) { steers.append(args); return ("steered", true) }
}

@main struct BotToolCommandTests {
    @MainActor static func main() throws {
        func object(_ response: (output: String, success: Bool)) throws -> [String: Any] {
            precondition(response.success, response.output)
            return try JSONSerialization.jsonObject(with: Data(response.output.utf8)) as! [String: Any]
        }
        let store = BotWorkspaceStore.shared
        var commander = store.bot(BotProfile.commanderID)!
        commander.sessionId = "parent"; commander.conversationIds = ["parent", "other-parent"]
        precondition(store.save(commander))
        var workspace = store.data
        workspace.sessionOwners["parent"] = BotSessionOwner(botId: commander.id)
        workspace.sessionOwners["other-parent"] = BotSessionOwner(botId: commander.id)
        precondition(store.persist(workspace))
        let vm = AIChatViewModel(); vm.sessionId = "parent"
        precondition(vm.commanderPolicy.contains("bot_create") && vm.commanderPolicy.contains("bot_task"))
        precondition(AIChatViewModel.botTaskTool.parameters["action"]?.enumValues?.contains("list") == true)
        let fixedPolicy = vm.commanderPolicy
        let emptyList = try object(vm.executeBotTask(["action": "list"], toolUseID: "list-empty"))
        precondition((emptyList["bots"] as! [[String: String]]).isEmpty)
        var fixtures: [BotProfile] = []
        for index in 0..<24 {
            var bot = store.newBot(); bot.name = "Specialist \(index)"
            bot.instructions = String(repeating: "FULL_PRIVATE_INSTRUCTIONS", count: 400)
            if index != 0 { bot.introduction = "Quoted \"intro\"\n" + String(repeating: "👩‍💻", count: 200) }
            precondition(store.save(bot)); fixtures.append(bot)
        }
        precondition(vm.commanderPolicy == fixedPolicy, "Adding specialist instructions must not change Commander rules")
        let beforeList = store.data
        let startsBeforeList = BotTeamRuntime.shared.starts
        let manyList = try object(vm.executeBotTask(["action": "list"], toolUseID: "list-many"))
        let listed = manyList["bots"] as! [[String: String]]
        precondition(listed.count == fixtures.count && listed.allSatisfy { Set($0.keys) == ["bot_id", "name", "introduction"] })
        precondition(listed.allSatisfy { $0["bot_id"] != commander.id && $0["introduction"]!.count <= 160 })
        precondition(listed.first?["bot_id"] == fixtures[0].id && listed.first?["introduction"] == "")
        precondition(listed[1]["introduction"] == String(fixtures[1].introduction!.prefix(160)))
        precondition(listed[1]["name"] == fixtures[1].name)
        precondition(store.data == beforeList && BotTeamRuntime.shared.starts == startsBeforeList, "Discovery must be read-only")
        fixtures[0].name = "Renamed specialist"; fixtures[0].introduction = "Updated summary"
        precondition(store.save(fixtures[0]))
        precondition(store.deleteBot(fixtures.removeLast().id) != nil)
        let refreshedList = try object(vm.executeBotTask(["action": "list"], toolUseID: "list-refreshed"))
        let refreshed = refreshedList["bots"] as! [[String: String]]
        precondition(refreshed.count == fixtures.count && refreshed.first?["name"] == "Renamed specialist")
        precondition(refreshed.first?["introduction"] == "Updated summary" && vm.commanderPolicy == fixedPolicy)
        for bot in fixtures { precondition(store.deleteBot(bot.id) != nil) }
        let clearedList = try object(vm.executeBotTask(["action": "list"], toolUseID: "list-cleared"))
        precondition((clearedList["bots"] as! [[String: String]]).isEmpty && vm.commanderPolicy == fixedPolicy)
        let config: [String: Any] = ["name": "核查助手", "instructions": "Verify original sources and report uncertainty.",
            "introduction": "我会核对来源。", "question": "常查什么？", "options": ["新闻", "价格", "政策", "技术"], "avatar_id": "mint-otter"]
        let created = try object(vm.executeBotCreate(config, toolUseID: "create-call"))
        let id = created["bot_id"] as! String
        let createdList = try object(vm.executeBotTask(["action": "list"], toolUseID: "list-created"))
        precondition((createdList["bots"] as! [[String: String]]).first?["bot_id"] == id)
        precondition(vm.commanderPolicy == fixedPolicy)
        precondition(store.bot(id)?.onboarding?.options.count == 4 && store.bot(id)?.avatarPresetID == "mint-otter")
        var edited = store.bot(id)!; edited.instructions = "User's revised instructions"; precondition(store.save(edited))
        let retried = try object(vm.executeBotCreate(config, toolUseID: "create-call"))
        precondition(retried["bot_id"] as? String == id && store.data.bots.count == 2 && store.bot(id)?.instructions == edited.instructions)
        let other = AIChatViewModel(); other.sessionId = "other-parent"
        let separate = try object(other.executeBotCreate(config, toolUseID: "create-call"))
        precondition(separate["bot_id"] as? String != id && store.data.bots.count == 3)
        var invalid = config; invalid["unexpected"] = true
        precondition(!vm.executeBotCreate(invalid, toolUseID: "invalid").success)
        invalid = config; invalid["options"] = ["same", "same"]
        precondition(!vm.executeBotCreate(invalid, toolUseID: "duplicate-options").success)
        invalid = config; invalid["avatar_id"] = "unknown-franchise"
        precondition(!vm.executeBotCreate(invalid, toolUseID: "unknown-avatar").success)
        let task: [String: Any] = ["action": "delegate", "bot_id": id, "task": "核查公开来源", "tool_title": "核查"]
        let delegated = try object(vm.executeBotTask(task, toolUseID: "delegate-call"))
        let delegationID = delegated["delegation_id"] as! String
        let starts = BotTeamRuntime.shared.starts
        _ = try object(vm.executeBotTask(task, toolUseID: "delegate-call"))
        precondition(store.data.delegations.count == 1 && BotTeamRuntime.shared.starts == starts)
        let originalTime = store.delegation(delegationID)!.createdAt
        let follow: [String: Any] = ["action": "follow_up", "delegation_id": delegationID, "message": "只查最近七天"]
        _ = try object(vm.executeBotTask(follow, toolUseID: "queued-context"))
        let updated = store.delegation(delegationID)!
        precondition(updated.task.contains("只查最近七天") && updated.createdAt == originalTime && updated.reworkCount == 0)
        _ = try object(vm.executeBotTask(follow, toolUseID: "queued-context"))
        precondition(store.delegation(delegationID)?.task == updated.task)
        precondition(!vm.executeBotTask(["action": "complete", "delegation_id": delegationID], toolUseID: "early-complete").success)
        precondition(!other.executeBotTask(["action": "cancel", "delegation_id": delegationID], toolUseID: "wrong-parent").success)
        precondition(other.executeBotTask(["action": "status", "delegation_id": delegationID], toolUseID: "other-status").output == "[]")
        precondition(!vm.executeBotTask(["action": "delegate", "bot_id": commander.id, "task": "recursive"], toolUseID: "recursive").success)
        precondition(store.bindDelegation(delegationID, childSessionID: "bot-conversation"))
        precondition(vm.executeBotTask(follow, toolUseID: "running-context").success)
        precondition(BotTeamRuntime.shared.steers.count == 1 && store.delegation(delegationID)?.toolUseHistory?.contains("running-context") == true)
        precondition(store.delegation(delegationID)?.jobID == nil && store.delegation(delegationID)?.directExecution == true)
        var record = store.delegation(delegationID)!; record.state = .reviewing; record.result = "Partial result"
        precondition(store.saveDelegation(record))
        _ = try object(vm.executeBotTask(follow, toolUseID: "rework"))
        precondition(store.delegation(delegationID)?.reworkCount == 1 && store.delegation(delegationID)?.state == .queued)
        precondition(store.delegation(delegationID)?.toolUseHistory?.contains("delegate-call") == true)
        record = store.delegation(delegationID)!; record.state = .reviewing; precondition(store.saveDelegation(record))
        precondition(!vm.executeBotTask(follow, toolUseID: "second-rework").success)
        _ = try object(vm.executeBotTask(["action": "complete", "delegation_id": delegationID], toolUseID: "reviewed"))
        precondition(store.delegation(delegationID)?.state == .reviewing)
        record = store.delegation(delegationID)!; record.state = .interrupted; precondition(store.saveDelegation(record))
        let resume: [String: Any] = ["action": "resume", "delegation_id": delegationID]
        vm.programmaticTurnOrigin = "old callback"
        precondition(!vm.executeBotTask(resume, toolUseID: "resume").success)
        vm.programmaticTurnOrigin = nil
        let resumed = try object(vm.executeBotTask(resume, toolUseID: "resume"))
        let newID = resumed["delegation_id"] as! String
        precondition(newID != delegationID && store.delegation(newID)?.resumesDelegationID == delegationID && store.delegation(newID)?.childSessionID == nil)
        _ = try object(vm.executeBotTask(resume, toolUseID: "resume"))
        precondition(store.data.delegations.count == 2)
        _ = try object(vm.executeBotTask(["action": "cancel", "delegation_id": newID], toolUseID: "cancel"))
        precondition(store.delegation(newID)?.state == .cancelled)
        for index in 0...AgentJobRegistry.maxQueuedDelegationsPerParent {
            let queued = vm.executeBotTask(task, toolUseID: "capacity-" + String(index))
            precondition(queued.success == (index < AgentJobRegistry.maxQueuedDelegationsPerParent))
        }
        precondition(vm.executeBotTask(task, toolUseID: "capacity-0").success)
        precondition(vm.executeBotTask(["action": "list"], toolUseID: "list-full-queue").success)
        BotRestoreControl.isRestoring = true
        precondition(!vm.executeBotTask(["action": "list"], toolUseID: "list-restoring").success)
        precondition(!vm.executeBotCreate(config, toolUseID: "restoring").success && !vm.executeBotTask(task, toolUseID: "restoring").success)
        BotRestoreControl.isRestoring = false
        AIChatViewModel.agentsEnabled = false
        precondition(!vm.executeBotTask(["action": "list"], toolUseID: "list-disabled").success)
        precondition(!vm.commanderPolicy.contains("bot_create") && !vm.commanderPolicy.contains("bot_task") && !vm.commanderPolicy.contains("subagent_task"))
        precondition(vm.commanderPolicy.contains("disabled"))
        let targetVM = AIChatViewModel(); targetVM.sessionId = "bot-conversation"
        precondition(!targetVM.executeBotTask(["action": "list"], toolUseID: "list-specialist").success)
        precondition(targetVM.botDelegationPolicy.contains("Helper delegation is disabled") && !targetVM.botDelegationPolicy.contains("subagent_task"))
        precondition(!vm.executeBotCreate(config, toolUseID: "disabled").success && !vm.executeBotTask(task, toolUseID: "disabled").success)
        AIChatViewModel.agentsEnabled = true; vm.isHelper = true
        precondition(!targetVM.executeBotTask(["action": "list"], toolUseID: "list-specialist-enabled").success)
        precondition(!vm.executeBotTask(["action": "list"], toolUseID: "list-helper").success)
        precondition(vm.commanderPolicy.isEmpty)
        precondition(!vm.executeBotCreate(config, toolUseID: "helper").success && !vm.executeBotTask(task, toolUseID: "helper").success)
        print("PASS: fixed Commander rules, read-only compact Bot discovery/CRUD/Unicode/boundaries, shipping Bot command creation/idempotence, validation, parent isolation, queued/running follow-up, one rework, review completion, explicit new resume attempts and disabled/helper boundaries")
    }
}

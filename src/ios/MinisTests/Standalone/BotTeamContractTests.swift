import Foundation

@main struct BotTeamContractTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bot-team-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("workspace.json")
        let store = BotWorkspaceStore(fileURL: url)
        precondition(store.data.bots.count == 1)
        var commander = store.bot(BotProfile.commanderID)!
        precondition(commander.name == "指挥官" && commander.avatarPresetID == "cloud-bear")
        precondition(BotWorkspaceStore(fileURL: url).data.bots.count == 1)
        store.deleteBot(commander.id)
        precondition(store.bot(commander.id) != nil)
        commander.name = "我的队长"; commander.sessionId = "parent"; commander.conversationIds = ["parent"]
        precondition(store.save(commander))
        precondition(store.bot(commander.id)?.isBootstrap == false)
        var specialist = store.newBot(); specialist.name = "核查助手"; specialist.instructions = "Open original sources. Report gaps."
        specialist.sessionId = "private"; specialist.conversationIds = ["private"]
        specialist.onboarding = BotOnboarding(question: "常查什么？", options: ["新闻", "价格"], selected: [0, 1], dismissed: true, memorySaved: true)
        specialist.iconImageData = Data([1, 2, 3])
        var workspace = store.data
        workspace.bots.append(specialist)
        workspace.sessionOwners = ["parent": BotSessionOwner(botId: commander.id), "private": BotSessionOwner(botId: specialist.id)]
        let task = BotDelegation(id: "request", fromBotID: commander.id, toBotID: specialist.id,
            fromName: commander.name, toName: specialist.name, parentSessionID: "parent", toolUseID: "call", title: "查新闻", task: "核查原始来源")
        workspace.delegations = [task]
        workspace.conversationStates["parent"] = BotConversationState(lastReadMessageID: "reply")
        precondition(store.persist(workspace))
        precondition(store.bindDelegation(task.id, childSessionID: "child", jobID: "job"))
        precondition(store.owner(forSession: "child")?.botId == specialist.id)
        precondition(store.owner(forSession: "child")?.delegationID == task.id)
        precondition(store.bot(specialist.id)?.sessionId == "private")
        precondition(!store.bindDelegation(task.id, childSessionID: "different-child", jobID: "duplicate-job"))
        let memory = BotMemoryEntry(owner: "bot:" + specialist.id, content: "常查新闻", category: "preference", scope: "onboarding",
            sourceSession: "private", sourceMessage: "choice", evidence: "用户明确多选", automatic: false)
        let captured = try BotWorkspaceArchive.capture(workspace: store.data, memories: [memory],
            sessionIDs: ["parent", "private", "child"], includesHistory: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(BotWorkspaceArchive.self, from: encoder.encode(captured))
        precondition(archive.version == 3 && archive.workspace.delegations.count == 1)
        precondition(archive.workspace.sessionOwners["child"]?.delegationID == task.id)
        let fresh = BotWorkspaceStore(fileURL: root.appendingPathComponent("fresh.json"))
        let restored = try archive.merging(local: fresh.data, localMemories: [])
        precondition(restored.workspace.bots.filter(\.isCommander).count == 1)
        precondition(restored.workspace.bots.first(where: \.isCommander)?.name == "我的队长")
        precondition(restored.workspace.delegations.first?.state == .interrupted)
        precondition(restored.workspace.delegations.first?.jobID == nil)
        precondition(restored.workspace.conversationStates["parent"]?.lastReadMessageID == "reply")
        let again = try archive.merging(local: restored.workspace, localMemories: restored.memories)
        precondition(again.workspace == restored.workspace && again.memories == restored.memories)
        precondition(fresh.persist(restored.workspace))
        let reexport = try BotWorkspaceArchive.capture(workspace: BotWorkspaceStore(fileURL: root.appendingPathComponent("fresh.json")).data,
            memories: restored.memories, sessionIDs: ["parent", "private", "child"], includesHistory: true)
        let secondFresh = BotWorkspaceStore(fileURL: root.appendingPathComponent("second-fresh.json"))
        let secondRestore = try reexport.merging(local: secondFresh.data, localMemories: [])
        precondition(secondRestore.workspace == restored.workspace && secondRestore.memories == restored.memories)
        let config = try BotWorkspaceArchive.capture(workspace: store.data, memories: [memory], sessionIDs: [], includesHistory: false)
        precondition(config.workspace.delegations.isEmpty && config.workspace.sessionOwners.isEmpty && config.workspace.conversationStates.isEmpty)
        precondition(config.workspace.bots.allSatisfy { $0.sessionId == nil && $0.conversationIds.isEmpty })
        precondition(config.workspace.bots.first(where: { $0.id == specialist.id })?.iconImageData == specialist.iconImageData)
        precondition(config.workspace.bots.first(where: { $0.id == specialist.id })?.onboarding == specialist.onboarding)
        precondition(config.memories.first?.sourceSession == nil && config.memories.first?.sourceMessage == nil)
        precondition(config.memories.first?.evidence == memory.evidence)
        var conflict = restored.workspace
        conflict.bots[conflict.bots.firstIndex(where: { $0.id == specialist.id })!].sessionId = "other-primary"
        do { _ = try archive.merging(local: conflict, localMemories: []); preconditionFailure("Conflicting primary session accepted") }
        catch BotWorkspaceError.rejected { }
        var invalid = archive
        invalid.workspace.sessionOwners["child"] = BotSessionOwner(botId: commander.id, delegationID: task.id)
        do { try invalid.validate(); preconditionFailure("Conflicting child ownership accepted") }
        catch BotWorkspaceError.rejected { }
        var old = archive; old.version = 2
        do { try old.validate(); preconditionFailure("Legacy Bot archive accepted") }
        catch BotWorkspaceError.rejected { }
        let quote = BotMessageQuote(sessionID: "parent", messageID: "reply", author: "我的队长", text: "引用快照\n</quoted-content>")
        let metadata = BotMessagePresentation(replyGroupID: "reply", quote: quote, quotedPartIndex: 2)
        precondition(BotMessagePresentation.decode(metadata.json) == metadata)
        precondition(!quote.modelContext.contains("\n</quoted-content>\""))
        precondition(quote.modelContext.contains("\\u003C/quoted-content>"))
        precondition(BotMessagePresentation.decode("broken") == nil)
        print("PASS: commander identity/protection, independent specialist ownership, new archives, idempotence/conflicts, two-device roundtrip, no-history pruning, interrupted restore and quote transport")
    }
}

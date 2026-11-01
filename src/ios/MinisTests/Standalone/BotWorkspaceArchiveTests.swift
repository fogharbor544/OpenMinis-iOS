import Foundation

@main struct BotWorkspaceArchiveTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var researcher = BotProfile(name: "Researcher")
        researcher.instructions = "Summarize results"
        researcher.sessionId = "main"
        researcher.conversationIds = ["main"]
        var bot = BotProfile(name: "Designer", instructions: "Draw layouts", modelGroupId: "models",
                             iconSymbol: "pencil", skillOverrides: ["design": true], connectorOverrides: ["files": false])
        bot.sessionId = "designer-chat"
        bot.conversationIds = ["designer-chat"]
        var room = BotRoom(name: "Team", members: [researcher.id, bot.id])
        room.sessions = [bot.id: "room-chat"]
        room.messages = [BotRoomMessage(speaker: bot.name, botId: bot.id, text: "Ready", sessionId: "room-chat")]
        room.interrupted = true
        let workspace = BotWorkspaceData(bots: [bot, researcher], rooms: [room], sessionOwners: [
            "main": BotSessionOwner(botId: researcher.id, roomId: nil),
            "room-chat": BotSessionOwner(botId: bot.id, roomId: room.id),
            "designer-chat": BotSessionOwner(botId: bot.id, roomId: nil)
        ])
        var entry = BotMemoryEntry(owner: "bot:\(bot.id)", content: "Prefers diagrams", category: "preference",
                                   scope: "work", sourceSession: "room-chat", sourceMessage: "message",
                                   evidence: "Please use diagrams", updatedAt: Date(timeIntervalSince1970: 100))
        entry.grants = ["room:\(room.id)"]
        var deleted = BotMemoryEntry(owner: "bot:\(bot.id)", content: "", category: "preference", scope: "",
                                     evidence: "", updatedAt: Date(timeIntervalSince1970: 100), status: "deleted")
        deleted.pinned = false
        let archive = try BotWorkspaceArchive.capture(workspace: workspace, memories: [entry, deleted],
            sessionIDs: ["main", "room-chat", "designer-chat"], includesHistory: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BotWorkspaceArchive.self, from: encoder.encode(archive))
        try decoded.validate()
        precondition(decoded.workspace.bots.map(\.id) == archive.workspace.bots.map(\.id))
        precondition(decoded.workspace.rooms.first?.interrupted == false)
        precondition(decoded.memories.contains { $0.status == "deleted" })

        let store = BotWorkspaceStore(fileURL: root.appendingPathComponent("workspace.json"))
        precondition(store.data.bots.isEmpty)
        let memory = BotMemoryStore(fileURL: root.appendingPathComponent("memory.sqlite"))
        let journal = root.appendingPathComponent("recovery/pending.json")
        // No private env-vars or subagents exist: Bot identities still restore independently.
        try BotWorkspaceTransfer.apply(decoded, workspace: store, memory: memory, journal: journal)
        precondition(store.bot(researcher.id)?.name == researcher.name)
        precondition(store.data.bots.map(\.id) == [bot.id, researcher.id])
        precondition(store.bot(bot.id)?.skillOverrides == ["design": true])
        precondition(store.owner(forSession: "room-chat")?.roomId == room.id)
        precondition(store.owner(forSession: "designer-chat")?.botId == bot.id)
        precondition(store.room(room.id)?.messages.count == 1)
        let restoredMemory = try memory.entries()
        precondition(restoredMemory.count == 2 && restoredMemory.contains { $0.grants == entry.grants })
        let before = store.data
        try BotWorkspaceTransfer.apply(decoded, workspace: store, memory: memory, journal: journal)
        precondition(store.data == before)
        precondition(tryCount(memory) == 2)
        precondition(!FileManager.default.fileExists(atPath: journal.path))
        var unsupported = decoded
        unsupported.version = 1
        do { try unsupported.validate(); preconditionFailure("Unsupported archive accepted") } catch {}
        var conflict = decoded
        conflict.workspace.bots[1].sessionId = "other-chat"
        conflict.workspace.bots[1].conversationIds = ["other-chat"]
        conflict.workspace.sessionOwners["other-chat"] = BotSessionOwner(botId: researcher.id, roomId: nil)
        do {
            _ = try conflict.merging(into: store.data, memories: restoredMemory)
            preconditionFailure("Conflicting canonical chat accepted")
        } catch { precondition(store.data == before) }
        let reload = BotWorkspaceStore(fileURL: root.appendingPathComponent("workspace.json"))
        precondition(reload.data == store.data)

        var local = store.bot(bot.id)!
        local.name = "Local edit"
        precondition(store.save(local))
        try memory.forget(id: entry.id, owner: entry.owner)
        try BotWorkspaceTransfer.apply(decoded, workspace: store, memory: memory, journal: journal)
        precondition(store.bot(bot.id)?.name == "Local edit")
        let afterForget = try memory.entries().first { $0.id == entry.id }
        precondition(afterForget?.status == "deleted")

        let config = try BotWorkspaceArchive.capture(workspace: workspace, memories: [entry], sessionIDs: [], includesHistory: false)
        precondition(config.workspace.sessionOwners.isEmpty)
        precondition(config.workspace.bots.allSatisfy { $0.sessionId == nil && $0.conversationIds.isEmpty })
        precondition(config.workspace.rooms.allSatisfy { $0.sessions.isEmpty && $0.messages.isEmpty })
        precondition(config.memories.first?.sourceSession == nil && config.memories.first?.sourceMessage == nil)
        precondition(config.memories.first?.content == entry.content)

        // Updated/new chats can be absent from the snapshot, including resumed shards.
        let partial = try BotWorkspaceArchive.capture(workspace: workspace, memories: [entry, deleted],
            sessionIDs: ["designer-chat"], includesHistory: true)
        try partial.validate()
        precondition(Set(partial.workspace.sessionOwners.keys) == ["designer-chat"])
        precondition(partial.workspace.bots.first { $0.id == bot.id }?.sessionId == "designer-chat")
        precondition(partial.workspace.bots.first { $0.id == researcher.id }?.sessionId == nil)
        precondition(partial.workspace.rooms.first?.sessions.isEmpty == true)
        precondition(partial.workspace.rooms.first?.messages.first?.text == "Ready")
        precondition(partial.workspace.rooms.first?.messages.first?.sessionId == nil)
        precondition(partial.memories.first?.sourceSession == nil && partial.memories.first?.sourceMessage == nil)
        precondition(partial.memories.first?.content == entry.content)
        precondition(workspace.sessionOwners.count == 3 && entry.sourceSession == "room-chat")
        let emptyHistory = try BotWorkspaceArchive.capture(workspace: workspace, memories: [entry],
            sessionIDs: [], includesHistory: true)
        try emptyHistory.validate()
        precondition(emptyHistory.workspace.bots.count == 2 && emptyHistory.workspace.sessionOwners.isEmpty)

        var incomplete = decoded
        incomplete.workspace.bots.removeAll { $0.id == bot.id }
        let intact = store.data
        do {
            try BotWorkspaceTransfer.apply(incomplete, workspace: store, memory: memory, journal: journal)
            preconditionFailure("Incomplete relationships must not be applied")
        } catch { precondition(store.data == intact) }

        // Simulate an interruption between the two store writes using the actual undo format.
        let prior = BotWorkspaceArchive(includesHistory: true, workspace: store.data, memories: try memory.entries())
        try JSONEncoder().encode(prior).write(to: journal, options: .atomic)
        try memory.replaceForRestore([])
        var changed = store.data
        changed.bots.removeAll()
        precondition(store.persist(changed))
        try BotWorkspaceTransfer.recover(workspace: store, memory: memory, journal: journal)
        precondition(store.data == prior.workspace && tryCount(memory) == prior.memories.count)
        precondition(!FileManager.default.fileExists(atPath: journal.path))

        // A filesystem write failure after memory write retains recovery data if rollback fails.
        let blocker = root.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blocker)
        let blockedStore = BotWorkspaceStore(fileURL: blocker.appendingPathComponent("workspace.json"))
        let blockedJournal = root.appendingPathComponent("blocked-restore.json")
        let untouchedMemory = try memory.entries()
        do {
            try BotWorkspaceTransfer.apply(decoded, workspace: blockedStore, memory: memory, journal: blockedJournal)
            preconditionFailure("A failed workspace write must fail the restore")
        } catch {
            let recoveredMemory = try memory.entries().sorted { $0.id < $1.id }
            precondition(recoveredMemory == untouchedMemory.sorted { $0.id < $1.id })
            precondition(FileManager.default.fileExists(atPath: blockedJournal.path))
        }
        try FileManager.default.removeItem(at: blocker)
        try BotWorkspaceTransfer.recover(workspace: blockedStore, memory: memory, journal: blockedJournal)
        precondition(!FileManager.default.fileExists(atPath: blockedJournal.path))

        let dataDir = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try Data("{\"d\":{\"session\":{\"id\":\"main\"}}}\n".utf8).write(to: dataDir.appendingPathComponent("sessions.jsonl"))
        try Data("{\"d\":{\"session\":{\"id\":\"room-chat\"}}}\n".utf8).write(to: dataDir.appendingPathComponent("sessions-0002.jsonl"))
        let sessionIDs = try BotWorkspaceArchive.sessionIDs(in: dataDir)
        precondition(sessionIDs == ["main", "room-chat"])
        print("PASS: full and configuration-only agent archives, fresh-device restore, stable IDs, memory tombstones, repeated restore, local edits and interruption recovery")
    }

    @MainActor static func tryCount(_ store: BotMemoryStore) -> Int { try! store.entries().count }
}

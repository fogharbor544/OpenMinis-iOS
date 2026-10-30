import Foundation

/// A versioned, logical snapshot; SQLite files, credentials and running jobs are not portable.
struct BotWorkspaceArchive: Codable, Equatable {
    var version = 2
    var includesHistory: Bool
    var workspace: BotWorkspaceData
    var memories: [BotMemoryEntry]

    static func read(from url: URL) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Self.self, from: Data(contentsOf: url))
        try archive.validate()
        return archive
    }

    /// Read the actual exported parent rows, including resumed JSONL shards.
    static func sessionIDs(in directory: URL) throws -> Set<String> {
        struct Row: Decodable {
            struct Payload: Decodable {
                struct Session: Decodable { var id: String }
                var session: Session
            }
            var d: Payload
        }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent == "sessions.jsonl" || ($0.lastPathComponent.hasPrefix("sessions-") && $0.pathExtension == "jsonl") }
        var ids: Set<String> = []
        for url in urls {
            for line in try Data(contentsOf: url).split(separator: 0x0A) where !line.isEmpty {
                ids.insert(try JSONDecoder().decode(Row.self, from: Data(line)).d.session.id)
            }
        }
        return ids
    }

    static func capture(workspace: BotWorkspaceData, memories: [BotMemoryEntry],
                        sessionIDs: Set<String>, includesHistory: Bool) throws -> Self {
        var result = Self(includesHistory: includesHistory, workspace: workspace, memories: memories)
        let bots = Set(workspace.bots.map(\.id))
        let rooms = Set(workspace.rooms.map(\.id))
        result.workspace.sessionOwners = workspace.sessionOwners.filter { sid, owner in
            includesHistory && sessionIDs.contains(sid) && bots.contains(owner.botId)
                && (owner.roomId == nil || rooms.contains(owner.roomId!))
        }
        let sessions = Set(result.workspace.sessionOwners.keys)
        for i in result.workspace.bots.indices {
            if let sid = result.workspace.bots[i].sessionId, !sessions.contains(sid) {
                result.workspace.bots[i].sessionId = nil
            }
            result.workspace.bots[i].conversationIds.removeAll { !sessions.contains($0) }
        }
        for i in result.workspace.rooms.indices {
            result.workspace.rooms[i].members.removeAll { !bots.contains($0) }
            result.workspace.rooms[i].sessions = result.workspace.rooms[i].sessions.filter { sessions.contains($0.value) }
            result.workspace.rooms[i].interrupted = false
            if !includesHistory { result.workspace.rooms[i].messages = [] }
            for j in result.workspace.rooms[i].messages.indices {
                if let sid = result.workspace.rooms[i].messages[j].sessionId, !sessions.contains(sid) {
                    result.workspace.rooms[i].messages[j].sessionId = nil
                }
                if let bot = result.workspace.rooms[i].messages[j].botId, !bots.contains(bot) {
                    result.workspace.rooms[i].messages[j].botId = nil
                }
            }
        }
        let owners = Set(bots.map { "bot:\($0)" } + rooms.map { "room:\($0)" })
        result.memories = memories.filter { owners.contains($0.owner) }
        for i in result.memories.indices {
            result.memories[i].grants.removeAll { !owners.contains($0) }
            if !includesHistory || result.memories[i].sourceSession.map({ !sessions.contains($0) }) == true {
                result.memories[i].sourceSession = nil
                result.memories[i].sourceMessage = nil
            }
        }
        try result.validate()
        return result
    }

    func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw BotWorkspaceError.rejected(message) }
        }
        try require(version == 2, "Unsupported agent archive version.")
        let bots = Set(workspace.bots.map(\.id)), rooms = Set(workspace.rooms.map(\.id))
        try require(bots.count == workspace.bots.count && rooms.count == workspace.rooms.count,
                    "Duplicate agent or group IDs in the archive.")
        try require(Set(memories.map(\.id)).count == memories.count, "Duplicate memory IDs in the archive.")
        for (sid, owner) in workspace.sessionOwners {
            try require(includesHistory && !sid.isEmpty && bots.contains(owner.botId), "Invalid conversation ownership.")
            if let room = owner.roomId {
                try require(workspace.rooms.contains { $0.id == room && $0.members.contains(owner.botId) },
                            "Conversation references a missing group member.")
            }
        }
        for bot in workspace.bots {
            try require(!bot.id.isEmpty && !bot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "An agent has no ID or name.")
            for sid in bot.conversationIds + (bot.sessionId.map { [$0] } ?? []) {
                try require(workspace.sessionOwners[sid] == BotSessionOwner(botId: bot.id, roomId: nil),
                            "Agent conversation ownership does not match.")
            }
        }
        for room in workspace.rooms {
            try require(!room.id.isEmpty && !room.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "A group has no ID or name.")
            try require(Set(room.members).isSubset(of: bots), "A group references a missing agent.")
            for (bot, sid) in room.sessions {
                try require(room.members.contains(bot) && workspace.sessionOwners[sid] == BotSessionOwner(botId: bot, roomId: room.id),
                            "Group conversation ownership does not match.")
            }
            try require(includesHistory || room.messages.isEmpty, "A configuration archive contains group history.")
            for message in room.messages {
                if let bot = message.botId { try require(bots.contains(bot), "A group message references a missing agent.") }
                if let sid = message.sessionId { try require(workspace.sessionOwners[sid] != nil, "A group message references a missing conversation.") }
            }
        }
        let owners = Set(bots.map { "bot:\($0)" } + rooms.map { "room:\($0)" })
        for memory in memories {
            try require(owners.contains(memory.owner) && Set(memory.grants).isSubset(of: owners),
                        "Memory references a missing owner or grant recipient.")
            if let sid = memory.sourceSession {
                try require(workspace.sessionOwners[sid] != nil, "Memory references a missing conversation.")
            }
        }
    }

    /// Same-ID local configuration wins.
    /// Memory uses its own clock, including deleted/forgotten entries.
    func merging(into local: BotWorkspaceData, memories localMemories: [BotMemoryEntry]) throws -> Self {
        try validate()
        if local.rooms.isEmpty && local.sessionOwners.isEmpty && localMemories.isEmpty,
           local.bots.isEmpty {
            // A fresh install has no user ordering to preserve, including Bot order.
            var restored = self
            for i in restored.workspace.rooms.indices { restored.workspace.rooms[i].interrupted = false }
            restored.memories.sort { $0.id < $1.id }
            return restored
        }
        var next = local
        for incoming in workspace.bots {
            if let index = next.bots.firstIndex(where: { $0.id == incoming.id }) {
                if let existing = next.bots[index].sessionId, let restored = incoming.sessionId,
                   existing != restored {
                    throw BotWorkspaceError.rejected("同一 Bot 已绑定其他聊天，请在干净环境恢复。")
                }
                if next.bots[index].sessionId == nil { next.bots[index].sessionId = incoming.sessionId }
                for sid in incoming.conversationIds where !next.bots[index].conversationIds.contains(sid) {
                    next.bots[index].conversationIds.append(sid)
                }
            } else { next.bots.append(incoming) }
        }
        for incoming in workspace.rooms {
            if let index = next.rooms.firstIndex(where: { $0.id == incoming.id }) {
                let localRoom = next.rooms[index]
                guard Set(incoming.members) == Set(localRoom.members) else {
                    throw BotWorkspaceError.rejected("A group with the same ID has different local members. Restore on an empty device instead.")
                }
                for (bot, sid) in incoming.sessions {
                    if let existing = next.rooms[index].sessions[bot], existing != sid {
                        throw BotWorkspaceError.rejected("同一群组成员已绑定其他聊天，请在干净环境恢复。")
                    }
                    next.rooms[index].sessions[bot] = sid
                }
                let ids = Set(localRoom.messages.map(\.id))
                next.rooms[index].messages += incoming.messages.filter { !ids.contains($0.id) }
                next.rooms[index].messages.sort { $0.date < $1.date }
            } else {
                var restored = incoming
                restored.interrupted = false
                next.rooms.append(restored)
            }
        }
        for (sid, owner) in workspace.sessionOwners {
            if let existing = next.sessionOwners[sid], existing != owner {
                throw BotWorkspaceError.rejected("A conversation already belongs to a different local agent.")
            }
            next.sessionOwners[sid] = owner
        }
        var entries = Dictionary(uniqueKeysWithValues: localMemories.map { ($0.id, $0) })
        for incoming in memories {
            if let local = entries[incoming.id] {
                guard local.owner == incoming.owner else {
                    throw BotWorkspaceError.rejected("A memory ID already belongs to a different local owner.")
                }
                if local.updatedAt >= incoming.updatedAt { continue }
            }
            entries[incoming.id] = incoming
        }
        return Self(includesHistory: true, workspace: next,
                    memories: entries.values.sorted { $0.id < $1.id })
    }
}

/// A durable undo record covers both stores, including interruption between their writes.
@MainActor enum BotWorkspaceTransfer {
    static var recoveryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BotWorkspaceRestore/pending.json")
    }

    static func recover(workspace: BotWorkspaceStore, memory: BotMemoryStore, journal: URL) throws {
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        let prior = try JSONDecoder().decode(BotWorkspaceArchive.self, from: Data(contentsOf: journal))
        try memory.replaceForRestore(prior.memories)
        guard workspace.persist(prior.workspace) else { throw BotWorkspaceError.storage }
        try FileManager.default.removeItem(at: journal)
    }

    static func apply(_ incoming: BotWorkspaceArchive, workspace: BotWorkspaceStore,
                      memory: BotMemoryStore, journal: URL) throws {
        try recover(workspace: workspace, memory: memory, journal: journal)
        let prior = BotWorkspaceArchive(includesHistory: true, workspace: try workspace.dataForBackup(), memories: try memory.entries())
        let merged = try incoming.merging(into: prior.workspace, memories: prior.memories)
        if merged.workspace == prior.workspace && merged.memories == prior.memories { return }
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(prior).write(to: journal, options: .atomic)
        do {
            try memory.replaceForRestore(merged.memories)
            guard workspace.persist(merged.workspace) else { throw BotWorkspaceError.storage }
            try FileManager.default.removeItem(at: journal)
        } catch {
            // Leave the undo file in place if rollback itself fails, for launch-time recovery.
            try recover(workspace: workspace, memory: memory, journal: journal)
            throw error
        }
    }
}

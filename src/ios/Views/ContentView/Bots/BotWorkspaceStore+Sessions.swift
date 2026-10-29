import Foundation

extension BotWorkspaceStore {
    func adoptLegacyMemorySetting(for sessionID: String) async {
        guard let owner = owner(forSession: sessionID) else { return }
        if let roomID = owner.roomId {
            guard let room = room(roomID), room.memoryEnabled == nil else { return }
            let value = await ChatStore.shared.getMemoryEnabled(sessionId: room.sessions.values.sorted().first ?? sessionID)
            guard var current = self.room(roomID), current.memoryEnabled == nil else { return }
            current.memoryEnabled = value
            _ = save(current)
        } else {
            guard let bot = bot(owner.botId), bot.memoryEnabled == nil else { return }
            let value = await ChatStore.shared.getMemoryEnabled(sessionId: bot.sessionId ?? sessionID)
            guard var current = self.bot(owner.botId), current.memoryEnabled == nil else { return }
            current.memoryEnabled = value
            _ = save(current)
        }
    }

    func copyCapabilities(to sessionID: String, from sourceID: String) {
        guard owner(forSession: sessionID) == nil else { return }
        for skill in SkillStore.shared.skills {
            SkillStore.shared.setSessionOverride(skillId: skill.id, sessionId: sessionID,
                enabled: SkillStore.shared.isEnabledForSession(skill.id, sessionId: sourceID))
        }
        for server in MCPStore.shared.servers {
            MCPStore.shared.setSessionOverride(serverId: server.id, sessionId: sessionID,
                enabled: MCPStore.shared.isEnabledForSession(server.id, sessionId: sourceID))
        }
    }

    func selectConversation(_ id: String, botID: String) async -> Bool {
        guard await ChatStore.shared.getSession(id) != nil else { return false }
        guard owner(forSession: id)?.botId == botID, owner(forSession: id)?.roomId == nil,
              let index = data.bots.firstIndex(where: { $0.id == botID }) else { return false }
        var next = data
        next.bots[index].sessionId = id
        return persist(next)
    }

    /// Creates only a normal ChatStore session; model/tools/streaming remain owned by the existing runtime.
    func session(botID: String, roomID: String? = nil, newConversation: Bool = false) async throws -> String {
        guard let profile = bot(botID) else { throw BotWorkspaceError.missingBot }
        if profile.skillOverrides == nil || profile.connectorOverrides == nil {
            var updated = profile
            if let sid = profile.sessionId {
                if updated.skillOverrides == nil { updated.skillOverrides = Dictionary(uniqueKeysWithValues: SkillStore.shared.skills.map { ($0.id, SkillStore.shared.isEnabledForSession($0.id, sessionId: sid)) }) }
                if updated.connectorOverrides == nil { updated.connectorOverrides = Dictionary(uniqueKeysWithValues: MCPStore.shared.servers.map { ($0.id, MCPStore.shared.isEnabledForSession($0.id, sessionId: sid)) }) }
            } else {
                updated.skillOverrides = updated.skillOverrides ?? [:]
                updated.connectorOverrides = updated.connectorOverrides ?? [:]
            }
            guard save(updated) else { throw BotWorkspaceError.storage }
        }
        let saved = roomID.flatMap { room($0)?.sessions[botID] } ?? (roomID == nil ? profile.sessionId : nil)
        if !newConversation, let saved, await ChatStore.shared.getSession(saved) != nil { return saved }
        let providers = ProviderConfigStore.shared
        guard let groupID = profile.modelGroupId ?? providers.defaultPrimaryGroupId,
              let group = providers.group(for: groupID),
              let entryID = ModelGroupRouter.resolve(group: group, sessionId: saved ?? botID, store: providers),
              let entry = providers.entry(for: entryID) else { throw BotWorkspaceError.noModel }
        let title = roomID.flatMap { room($0)?.name }.map { "\($0) · \(profile.name)" } ?? profile.name
        let session = await ChatStore.shared.createSession(modelId: entry.model.id, title: title, source: "bot")
        providers.setBinding(SessionModelBinding(sessionId: session.id, primarySource: .group(groupId: groupID, resolvedEntryId: entryID)), for: session.id)
        var next = data
        next.sessionOwners[session.id] = BotSessionOwner(botId: botID, roomId: roomID)
        if let roomID, let index = next.rooms.firstIndex(where: { $0.id == roomID }) {
            next.rooms[index].sessions[botID] = session.id
        } else if roomID == nil, let index = next.bots.firstIndex(where: { $0.id == botID }) {
            var ids = next.bots[index].conversationIds
            if !ids.contains(session.id) { ids.append(session.id) }
            next.bots[index].conversationIds = ids
            next.bots[index].sessionId = session.id
        } else { throw BotWorkspaceError.missingBot }
        guard persist(next) else { throw BotWorkspaceError.storage }
        return session.id
    }

}

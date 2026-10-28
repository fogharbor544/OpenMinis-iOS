import Foundation

extension BotWorkspaceStore {
    /// Creates only a normal ChatStore session; model/tools/streaming remain owned by the existing runtime.
    func session(botID: String, roomID: String? = nil, newConversation: Bool = false) async throws -> String {
        guard let profile = bot(botID) else { throw BotWorkspaceError.missingBot }
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
        if next.sessionOwners == nil { next.sessionOwners = [:] }
        next.sessionOwners?[session.id] = BotSessionOwner(botId: botID, roomId: roomID)
        if let roomID, let index = next.rooms.firstIndex(where: { $0.id == roomID }) {
            next.rooms[index].sessions[botID] = session.id
            // Group sessions inherit this Bot's current skill and MCP choices, not its private messages.
            if let privateSession = profile.sessionId {
                for skill in SkillStore.shared.skills {
                    SkillStore.shared.setSessionOverride(skillId: skill.id, sessionId: session.id,
                        enabled: SkillStore.shared.isEnabledForSession(skill.id, sessionId: privateSession))
                }
                for server in MCPStore.shared.servers {
                    MCPStore.shared.setSessionOverride(serverId: server.id, sessionId: session.id,
                        enabled: MCPStore.shared.isEnabledForSession(server.id, sessionId: privateSession))
                }
            }
        } else if roomID == nil, let index = next.bots.firstIndex(where: { $0.id == botID }) {
            var ids = next.bots[index].conversationIds ?? [profile.sessionId].compactMap { $0 }
            if !ids.contains(session.id) { ids.append(session.id) }
            next.bots[index].conversationIds = ids
            next.bots[index].sessionId = session.id
            if let previous = profile.sessionId {
                for skill in SkillStore.shared.skills {
                    SkillStore.shared.setSessionOverride(skillId: skill.id, sessionId: session.id,
                        enabled: SkillStore.shared.isEnabledForSession(skill.id, sessionId: previous))
                }
                for server in MCPStore.shared.servers {
                    MCPStore.shared.setSessionOverride(serverId: server.id, sessionId: session.id,
                        enabled: MCPStore.shared.isEnabledForSession(server.id, sessionId: previous))
                }
            }
        } else { throw BotWorkspaceError.missingBot }
        guard persist(next) else { throw BotWorkspaceError.storage }
        return session.id
    }

    func applyModel(for profile: BotProfile) {
        guard let groupID = profile.modelGroupId ?? ProviderConfigStore.shared.defaultPrimaryGroupId,
              let group = ProviderConfigStore.shared.group(for: groupID) else { return }
        let sessions = (profile.conversationIds ?? [profile.sessionId].compactMap { $0 }) + data.rooms.compactMap { $0.sessions[profile.id] }
        for sessionID in sessions {
            if let entryID = ModelGroupRouter.resolve(group: group, sessionId: sessionID, store: .shared) {
                ProviderConfigStore.shared.setBinding(SessionModelBinding(sessionId: sessionID,
                    primarySource: .group(groupId: groupID, resolvedEntryId: entryID)), for: sessionID)
            }
        }
    }
}

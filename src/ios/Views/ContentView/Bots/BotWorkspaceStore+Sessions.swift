import Foundation

extension BotWorkspaceStore {
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

    /// Creates only a normal ChatStore session; model/tools/streaming remain owned by the existing runtime.
    func session(botID: String, roomID: String? = nil) async throws -> String {
        guard !BotRestoreControl.isRestoring else { throw BotWorkspaceError.rejected("正在恢复 Bot 数据，请稍后再打开会话。") }
        let key = roomID.map { "room:\($0):\(botID)" } ?? "bot:\(botID)"
        if let pending = pendingSessions[key] { return try await pending.value }
        let task = Task { @MainActor in try await self.prepareSession(botID: botID, roomID: roomID) }
        pendingSessions[key] = task
        defer { pendingSessions[key] = nil }
        return try await task.value
    }

    private func prepareSession(botID: String, roomID: String?) async throws -> String {
        guard !isDeleting(botID: botID),
              !(roomID.map(isDeleting(roomID:)) ?? false) else {
            throw BotWorkspaceError.rejected("This Bot or group is being deleted.")
        }
        guard let profile = bot(botID) else { throw BotWorkspaceError.missingBot }
        let saved = roomID.flatMap { room($0)?.sessions[botID] } ?? (roomID == nil ? profile.sessionId : nil)
        if let saved, await ChatStore.shared.getSession(saved) != nil {
            guard !isDeleting(botID: botID),
                  !(roomID.map(isDeleting(roomID:)) ?? false),
                  bot(botID) != nil,
                  roomID.map({ room($0)?.members.contains(botID) == true }) ?? true else {
                throw BotWorkspaceError.missingBot
            }
            return saved
        }
        let providers = ProviderConfigStore.shared
        guard let groupID = profile.modelGroupId ?? providers.defaultPrimaryGroupId,
              let group = providers.group(for: groupID),
              let entryID = ModelGroupRouter.resolve(group: group, sessionId: saved ?? botID, store: providers),
              let entry = providers.entry(for: entryID) else { throw BotWorkspaceError.noModel }
        let title = roomID.flatMap { room($0)?.name }.map { "\($0) · \(profile.name)" } ?? profile.name
        let session = await ChatStore.shared.createSession(modelId: entry.model.id, title: title, source: "bot")
        // The Bot/room may have been removed while createSession was suspended.
        // Never bind a new ChatStore row to a deleted owner; remove it instead.
        guard !isDeleting(botID: botID),
              !(roomID.map(isDeleting(roomID:)) ?? false),
              bot(botID) != nil,
              roomID.map({ room($0)?.members.contains(botID) == true }) ?? true else {
            await ChatStore.shared.deleteSession(session.id)
            throw BotWorkspaceError.missingBot
        }
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
        guard persist(next) else {
            providers.removeBinding(for: session.id)
            providers.removeInferenceConfig(for: session.id)
            await ChatStore.shared.deleteSession(session.id)
            throw BotWorkspaceError.storage
        }
        return session.id
    }

    /// A normal, target-owned Bot conversation. It is linked from the target's
    /// incoming-task hint, not added to its private chats or the commander's helpers.
    func prepareDelegationSession(_ record: BotDelegation) async throws -> (id: String, created: Bool) {
        guard !BotRestoreControl.isRestoring, let profile = bot(record.toBotID) else { throw BotWorkspaceError.missingBot }
        guard !isDeleting(botID: profile.id),
              !isDeletingParentRoom(of: record.parentSessionID) else {
            throw BotWorkspaceError.rejected("This Bot or group is being deleted.")
        }
        if record.directExecution == true, let sid = record.childSessionID, await ChatStore.shared.getSession(sid) != nil,
           owner(forSession: sid) == BotSessionOwner(botId: profile.id, delegationID: record.id) {
            guard !isDeleting(botID: profile.id),
                  !isDeletingParentRoom(of: record.parentSessionID),
                  bot(profile.id) != nil else {
                throw BotWorkspaceError.missingBot
            }
            return (sid, false)
        }
        let providers = ProviderConfigStore.shared
        guard let groupID = profile.modelGroupId ?? providers.defaultPrimaryGroupId,
              let group = providers.group(for: groupID),
              let entryID = ModelGroupRouter.resolve(group: group, sessionId: record.id, store: providers),
              let entry = providers.entry(for: entryID) else { throw BotWorkspaceError.noModel }
        let session = await ChatStore.shared.createSession(modelId: entry.model.id,
            title: "\(record.fromName) ↔ \(profile.name) · \(record.title)", source: "bot")
        guard !isDeleting(botID: profile.id),
              !isDeletingParentRoom(of: record.parentSessionID),
              bot(profile.id) != nil,
              delegation(record.id)?.state == .queued else {
            await ChatStore.shared.deleteSession(session.id)
            throw BotWorkspaceError.rejected("This Bot task was cancelled while its conversation was being created.")
        }
        providers.setBinding(SessionModelBinding(sessionId: session.id,
            primarySource: .group(groupId: groupID, resolvedEntryId: entryID)), for: session.id)
        return (session.id, true)
    }

}

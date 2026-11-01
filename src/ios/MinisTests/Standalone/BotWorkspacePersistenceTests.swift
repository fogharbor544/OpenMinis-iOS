import Foundation

@main
struct BotWorkspacePersistenceTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("workspace.json")
        let store = BotWorkspaceStore(fileURL: file)
        precondition(store.newBot().avatarPresetID == "pikachu")
        var first = store.newBot(); first.name = "First"
        precondition(store.save(first))
        precondition(store.newBot().avatarPresetID == "bulbasaur")
        store.deleteBot(first.id)
        let old = try JSONDecoder().decode(BotProfile.self, from: Data("{\"id\":\"legacy\",\"name\":\"Legacy\",\"instructions\":\"\",\"conversationIds\":[],\"iconSymbol\":\"terminal.fill\"}".utf8))
        precondition(old.avatarPresetID == nil && old.iconSymbol == "terminal.fill")
        var preview = old
        let original = BotAvatarChoice(profile: old)
        preview.avatarPresetID = "eevee"; preview.iconSymbol = "bubble.left.fill"
        precondition(old.avatarPresetID == nil) // draft/cancel leaves the source unchanged
        var confirmed = old
        BotAvatarChoice(profile: preview).apply(to: &confirmed)
        precondition(confirmed.avatarPresetID == "eevee" && confirmed.name == old.name)
        original.apply(to: &confirmed)
        precondition(confirmed == old)
        let roundTrip = try JSONDecoder().decode(BotProfile.self, from: JSONEncoder().encode(preview))
        precondition(roundTrip == preview)
        let researcher = BotProfile(name: "Researcher", instructions: "Find evidence")
        let reviewer = BotProfile(name: "Reviewer", instructions: "Check claims")
        precondition(store.save(researcher))
        precondition(store.save(reviewer))
        var room = BotRoom(name: "Team", members: [researcher.id, reviewer.id])
        room.sessions[researcher.id] = "group-session"
        precondition(store.save(room))
        var owned = store.data
        owned.sessionOwners["group-session"] = BotSessionOwner(botId: researcher.id, roomId: room.id)
        precondition(store.persist(owned))
        precondition(store.append(BotRoomMessage(speaker: "Researcher", botId: researcher.id, text: "Evidence", sessionId: "group-session"), to: room.id))
        let reload = BotWorkspaceStore(fileURL: file)
        precondition(reload.data.bots.count == 2)
        precondition(reload.room(room.id)?.members == [researcher.id, reviewer.id])
        precondition(reload.room(room.id)?.messages.first?.text == "Evidence")
        precondition(reload.bot(forSession: "group-session")?.id == researcher.id)
        precondition(reload.owner(forSession: "group-session")?.roomId == room.id)
        precondition(reload.inheritOwner(for: "group-copy", from: "group-session"))
        precondition(reload.owner(forSession: "group-copy")?.roomId == room.id)
        precondition(!reload.inheritOwner(for: "unowned-copy", from: "missing"))
        precondition(reload.setMemoryEnabled(false, forSession: "group-session"))
        precondition(!reload.memoryEnabled(forSession: "group-copy"))
        precondition(BotWorkspaceStore(fileURL: file).room(room.id)?.memoryEnabled == false)
        var configured = reload.bot(researcher.id)!
        configured.skillOverrides = ["skill": false]
        configured.connectorOverrides = ["connector": false]
        configured.memoryEnabled = true
        precondition(reload.save(configured))
        let settingsReload = BotWorkspaceStore(fileURL: file)
        precondition(settingsReload.bot(forSession: "group-copy")?.skillOverrides?["skill"] == false)
        precondition(settingsReload.bot(forSession: "group-session")?.connectorOverrides?["connector"] == false)
        precondition(!settingsReload.memoryEnabled(forSession: "group-session"))
        reload.deleteBot(researcher.id)
        precondition(!reload.inheritOwner(for: "deleted-bot-copy", from: "group-session"))
        precondition(BotWorkspaceStore(fileURL: file).owner(forSession: "group-session")?.botId == researcher.id)
        precondition(reload.room(room.id)?.members == [reviewer.id])
        precondition(reload.room(room.id)?.messages.first?.speaker == "Researcher")
        precondition(reload.room(room.id)?.sessions[researcher.id] == "group-session")
        var duplicate = room
        duplicate.members = [reviewer.id, reviewer.id]
        precondition(!reload.save(duplicate))
        precondition(reload.setRoundActive(true, roomID: room.id))
        precondition(BotWorkspaceStore(fileURL: file).room(room.id)?.interrupted == true)
        let corrupt = root.appendingPathComponent("corrupt.json")
        try Data("invalid-json".utf8).write(to: corrupt)
        let broken = BotWorkspaceStore(fileURL: corrupt)
        precondition(!broken.save(reviewer))
        let preserved = try String(contentsOf: corrupt, encoding: .utf8)
        precondition(preserved == "invalid-json")
        let icons = BotWorkspaceStore(fileURL: root.appendingPathComponent("icons.json"))
        for index in BotAvatarPreset.all.indices {
            var bot = icons.newBot()
            bot.name = "Bot \(index)"
            precondition(!icons.data.bots.contains { $0.avatarPresetID == bot.avatarPresetID })
            precondition(icons.save(bot))
        }
        var custom = icons.newBot()
        custom.name = "Custom"
        custom.iconImageData = Data([1, 2, 3]); custom.avatarPresetID = nil
        precondition(icons.save(custom))
        let restoredIcons = BotWorkspaceStore(fileURL: root.appendingPathComponent("icons.json"))
        precondition(restoredIcons.bot(custom.id)?.iconImageData == Data([1, 2, 3]))
        precondition(Set(restoredIcons.data.bots.compactMap(\.avatarPresetID)).count == BotAvatarPreset.all.count)
        let team = BotWorkspaceStore(fileURL: root.appendingPathComponent("fresh.json"))
        precondition(team.data.bots.isEmpty)
        let emptyReload = BotWorkspaceStore(fileURL: root.appendingPathComponent("fresh.json"))
        precondition(emptyReload.data.bots.isEmpty)
        var specialist = BotProfile(name: "Reviewer", instructions: "Review changes")
        precondition(team.save(specialist))
        specialist.name = "My reviewer"
        precondition(team.save(specialist))
        let savedTeam = BotWorkspaceStore(fileURL: root.appendingPathComponent("fresh.json"))
        precondition(savedTeam.data.bots == [specialist])
        savedTeam.deleteBot(specialist.id)
        precondition(savedTeam.data.bots.isEmpty)
        precondition(savedTeam.save(reviewer))
        precondition(savedTeam.capabilitySessionID(for: "ordinary-helper", parentSessionID: "parent-chat") == "parent-chat")
        precondition(savedTeam.capabilitySessionID(for: "normal-chat", parentSessionID: nil) == "normal-chat")
        precondition(savedTeam.capabilitySessionID(for: nil, parentSessionID: nil) == nil)
        precondition(settingsReload.capabilitySessionID(for: "group-session", parentSessionID: "parent") == "group-session")

        var portable = reviewer
        portable.instructions = "Review the output"
        portable.modelGroupId = "review-models"
        portable.skillOverrides = ["docs": true]
        portable.connectorOverrides = ["files": false]
        portable.memoryEnabled = false
        portable.sessionId = "source-private-chat"
        portable.conversationIds = ["source-private-chat", "source-old-chat"]
        portable.pinnedAt = Date()
        precondition(savedTeam.save(portable))
        let payload = try savedTeam.capabilityOwnerJSON(for: portable.id)
        precondition(payload != nil && !payload!.contains("source-private-chat"))
        let globalPayload = try savedTeam.capabilityOwnerJSON(for: nil)
        precondition(globalPayload == nil)

        let destinationURL = root.appendingPathComponent("capability-destination.json")
        let destination = BotWorkspaceStore(fileURL: destinationURL)
        try destination.restoreCapabilityOwner(botID: portable.id, json: payload)
        try destination.restoreCapabilityOwner(botID: portable.id, json: payload)
        precondition(destination.data.bots.count == 1)
        let restored = BotWorkspaceStore(fileURL: destinationURL).bot(portable.id)!
        precondition(restored.name == portable.name && restored.instructions == portable.instructions)
        precondition(restored.modelGroupId == portable.modelGroupId)
        precondition(restored.skillOverrides == portable.skillOverrides && restored.connectorOverrides == portable.connectorOverrides)
        precondition(restored.memoryEnabled == false)
        precondition(restored.sessionId == nil && restored.conversationIds.isEmpty && restored.pinnedAt == nil)
        precondition(destination.data.sessionOwners.isEmpty && destination.data.rooms.isEmpty)

        let unbound = BotWorkspaceStore(fileURL: root.appendingPathComponent("unbound-owner.json"))
        let unsanitized = String(decoding: try JSONEncoder().encode(portable), as: UTF8.self)
        try unbound.restoreCapabilityOwner(botID: portable.id, json: unsanitized)
        precondition(unbound.bot(portable.id)?.sessionId == nil)
        precondition(unbound.bot(portable.id)?.conversationIds.isEmpty == true)
        precondition(unbound.bot(portable.id)?.pinnedAt == nil)
        precondition(unbound.data.sessionOwners.isEmpty)

        var local = restored
        local.name = "Locally edited"
        local.sessionId = "destination-chat"
        precondition(destination.save(local))
        try destination.restoreCapabilityOwner(botID: portable.id, json: payload)
        precondition(destination.bot(portable.id)?.name == local.name)
        precondition(destination.bot(portable.id)?.sessionId == local.sessionId)
        // An old package needs no snapshot when its owner is already on this device.
        try destination.restoreCapabilityOwner(botID: portable.id, json: nil)
        try destination.restoreCapabilityOwner(botID: nil, json: nil)
        do {
            try destination.restoreCapabilityOwner(botID: "missing-owner", json: nil)
            preconditionFailure("A missing owner must not be reported as restored")
        } catch { precondition(destination.bot("missing-owner") == nil) }
        do {
            try destination.restoreCapabilityOwner(botID: "different-owner", json: payload)
            preconditionFailure("A snapshot must match the capability owner")
        } catch { precondition(destination.bot("different-owner") == nil) }
        do {
            try destination.restoreCapabilityOwner(botID: "missing-owner", json: "not JSON")
            preconditionFailure("An invalid owner snapshot must fail")
        } catch { precondition(destination.bot("missing-owner") == nil) }
        do {
            try broken.restoreCapabilityOwner(botID: portable.id, json: payload)
            preconditionFailure("An unreadable workspace must not accept imported owners")
        } catch { precondition(broken.bot(portable.id) == nil) }
        print("PASS: Bot/room persistence, order, session mapping, deletion preservation, interrupted rounds and corrupt-store protection")
    }
}

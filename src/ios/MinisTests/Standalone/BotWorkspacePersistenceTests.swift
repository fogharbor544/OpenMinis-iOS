import Foundation

@main
struct BotWorkspacePersistenceTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("workspace.json")
        let store = BotWorkspaceStore(fileURL: file, seedCommander: false)
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
        let reload = BotWorkspaceStore(fileURL: file, seedCommander: false)
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
        precondition(BotWorkspaceStore(fileURL: file, seedCommander: false).room(room.id)?.memoryEnabled == false)
        var configured = reload.bot(researcher.id)!
        configured.skillOverrides = ["skill": false]
        configured.connectorOverrides = ["connector": false]
        configured.memoryEnabled = true
        precondition(reload.save(configured))
        let settingsReload = BotWorkspaceStore(fileURL: file, seedCommander: false)
        precondition(settingsReload.bot(forSession: "group-copy")?.skillOverrides?["skill"] == false)
        precondition(settingsReload.bot(forSession: "group-session")?.connectorOverrides?["connector"] == false)
        precondition(!settingsReload.memoryEnabled(forSession: "group-session"))
        precondition(reload.deleteBot(researcher.id) != nil)
        precondition(!reload.inheritOwner(for: "deleted-bot-copy", from: "group-session"))
        precondition(reload.owner(forSession: "group-session") == nil)
        precondition(reload.owner(forSession: "group-copy") == nil)
        precondition(BotWorkspaceStore(fileURL: file, seedCommander: false).owner(forSession: "group-session") == nil)
        precondition(reload.room(room.id)?.members == [reviewer.id])
        precondition(reload.room(room.id)?.messages.isEmpty == true)
        precondition(reload.room(room.id)?.sessions[researcher.id] == nil)
        precondition(!reload.append(BotRoomMessage(speaker: researcher.name, botId: researcher.id,
                                                    text: "late", sessionId: "group-session"), to: room.id))
        precondition(!reload.updateConversation("group-session") { $0.lastReadMessageID = "late" })
        var disposableRoom = BotRoom(name: "Disposable", members: [reviewer.id])
        disposableRoom.sessions[reviewer.id] = "room-delete-session"
        precondition(reload.save(disposableRoom))
        var roomOwned = reload.data
        roomOwned.sessionOwners["room-delete-session"] = BotSessionOwner(
            botId: reviewer.id, roomId: disposableRoom.id)
        roomOwned.conversationStates["room-delete-session"] = BotConversationState()
        precondition(reload.persist(roomOwned))
        precondition(reload.sessionIDsOwned(byRoom: disposableRoom.id) == Set(["room-delete-session"]))
        precondition(reload.deleteRoom(disposableRoom.id) != nil)
        precondition(reload.room(disposableRoom.id) == nil)
        precondition(reload.owner(forSession: "room-delete-session") == nil)
        precondition(reload.data.conversationStates["room-delete-session"] == nil)
        var worker = BotProfile(name: "Worker")
        precondition(reload.save(worker))
        var taskRoom = BotRoom(name: "Task Group", members: [reviewer.id])
        taskRoom.sessions[reviewer.id] = "task-parent"
        precondition(reload.save(taskRoom))
        let task = BotDelegation(id: "room-task", fromBotID: reviewer.id, toBotID: worker.id,
            fromName: reviewer.name, toName: worker.name, parentSessionID: "task-parent",
            toolUseID: "call", title: "Task", task: "Do it")
        var taskData = reload.data
        taskData.sessionOwners["task-parent"] = BotSessionOwner(botId: reviewer.id, roomId: taskRoom.id)
        taskData.sessionOwners["task-child"] = BotSessionOwner(botId: worker.id, delegationID: task.id)
        var boundTask = task
        boundTask.childSessionID = "task-child"
        taskData.delegations = [boundTask]
        precondition(reload.persist(taskData))
        precondition(reload.sessionIDsOwned(byRoom: taskRoom.id).contains("task-child"))
        precondition(reload.deleteRoom(taskRoom.id) != nil)
        precondition(reload.owner(forSession: "task-parent") == nil)
        precondition(reload.owner(forSession: "task-child") == nil)
        precondition(reload.delegation(task.id) == nil)
        var mixedRoom = BotRoom(name: "Mixed", members: [reviewer.id])
        mixedRoom.sessions[reviewer.id] = "mixed-group"
        mixedRoom.messages = [BotRoomMessage(speaker: reviewer.name, botId: reviewer.id,
                                              text: "linked", sessionId: "worker-private")]
        precondition(reload.save(mixedRoom))
        var mixedData = reload.data
        mixedData.sessionOwners["worker-private"] = BotSessionOwner(botId: worker.id)
        precondition(reload.persist(mixedData))
        precondition(!reload.sessionIDsOwned(byRoom: mixedRoom.id).contains("worker-private"))
        precondition(reload.deleteRoom(mixedRoom.id) != nil)
        precondition(reload.owner(forSession: "worker-private")?.botId == worker.id)
        var legacyRoom = BotRoom(name: "Legacy", members: [reviewer.id])
        legacyRoom.messages = [BotRoomMessage(speaker: reviewer.name, botId: reviewer.id,
                                             text: "old", sessionId: "legacy-bot-session")]
        precondition(reload.save(legacyRoom))
        precondition(reload.sessionIDsOwned(byBot: reviewer.id).contains("legacy-bot-session"))
        precondition(reload.deleteRoom(legacyRoom.id) != nil)
        var duplicate = room
        duplicate.members = [reviewer.id, reviewer.id]
        precondition(!reload.save(duplicate))
        precondition(reload.setRoundActive(true, roomID: room.id))
        precondition(BotWorkspaceStore(fileURL: file, seedCommander: false).room(room.id)?.interrupted == true)
        let corrupt = root.appendingPathComponent("corrupt.json")
        try Data("invalid-json".utf8).write(to: corrupt)
        let broken = BotWorkspaceStore(fileURL: corrupt, seedCommander: false)
        precondition(!broken.save(reviewer))
        let preserved = try String(contentsOf: corrupt, encoding: .utf8)
        precondition(preserved == "invalid-json")
        let icons = BotWorkspaceStore(fileURL: root.appendingPathComponent("icons.json"), seedCommander: false)
        for index in BotProfile.builtinIcons.indices {
            var bot = icons.newBot()
            bot.name = "Bot \(index)"
            precondition(!icons.data.bots.contains { $0.iconSymbol == bot.iconSymbol })
            precondition(icons.save(bot))
        }
        var custom = icons.newBot()
        custom.name = "Custom"
        custom.iconImageData = Data([1, 2, 3])
        precondition(icons.save(custom))
        let restoredIcons = BotWorkspaceStore(fileURL: root.appendingPathComponent("icons.json"), seedCommander: false)
        precondition(restoredIcons.bot(custom.id)?.iconImageData == Data([1, 2, 3]))
        precondition(Set(restoredIcons.data.bots.compactMap(\.iconSymbol)).count == BotProfile.builtinIcons.count)
        let team = BotWorkspaceStore(fileURL: root.appendingPathComponent("fresh.json"), seedCommander: false)
        precondition(team.data.bots.isEmpty)
        let emptyReload = BotWorkspaceStore(fileURL: root.appendingPathComponent("fresh.json"), seedCommander: false)
        precondition(emptyReload.data.bots.isEmpty)
        var specialist = BotProfile(name: "Reviewer", instructions: "Review changes")
        precondition(team.save(specialist))
        specialist.name = "My reviewer"
        precondition(team.save(specialist))
        let savedTeam = BotWorkspaceStore(fileURL: root.appendingPathComponent("fresh.json"), seedCommander: false)
        precondition(savedTeam.data.bots == [specialist])
        precondition(savedTeam.deleteBot(specialist.id) != nil)
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
        let destination = BotWorkspaceStore(fileURL: destinationURL, seedCommander: false)
        try destination.restoreCapabilityOwner(botID: portable.id, json: payload)
        try destination.restoreCapabilityOwner(botID: portable.id, json: payload)
        precondition(destination.data.bots.count == 1)
        let restored = BotWorkspaceStore(fileURL: destinationURL, seedCommander: false).bot(portable.id)!
        precondition(restored.name == portable.name && restored.instructions == portable.instructions)
        precondition(restored.modelGroupId == portable.modelGroupId)
        precondition(restored.skillOverrides == portable.skillOverrides && restored.connectorOverrides == portable.connectorOverrides)
        precondition(restored.memoryEnabled == false)
        precondition(restored.sessionId == nil && restored.conversationIds.isEmpty && restored.pinnedAt == nil)
        precondition(destination.data.sessionOwners.isEmpty && destination.data.rooms.isEmpty)

        let unbound = BotWorkspaceStore(fileURL: root.appendingPathComponent("unbound-owner.json"), seedCommander: false)
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

        // Unread-state saves come from SwiftUI's synchronous value-update phase.
        // They must not wait behind a long snapshot-lock holder on another
        // thread; doing so kept the main run loop pinned until watchdog kill.
        let unreadURL = root.appendingPathComponent("unread-state.json")
        let unreadStore = BotWorkspaceStore(fileURL: unreadURL, seedCommander: false)
        precondition(unreadStore.save(reviewer))
        let lockHeld = DispatchSemaphore(value: 0)
        let releaseLock = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            BotDataSnapshotLock.lock.lock()
            lockHeld.signal()
            _ = releaseLock.wait(timeout: .now() + 2)
            BotDataSnapshotLock.lock.unlock()
        }
        precondition(lockHeld.wait(timeout: .now() + 2) == .success)
        let updateStarted = Date()
        precondition(unreadStore.updateConversation("destination-chat") { $0.lastReadMessageID = "latest" })
        let elapsed = Date().timeIntervalSince(updateStarted)
        precondition(elapsed < 0.2, "conversation state update blocked on snapshot lock")
        releaseLock.signal()

        let written = DispatchGroup()
        written.enter()
        DispatchQueue.global().async {
            defer { written.leave() }
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                let raw = try? Data(contentsOf: unreadURL)
                let workspace = raw.flatMap { try? JSONDecoder().decode(BotWorkspaceData.self, from: $0) }
                if workspace?.conversationStates["destination-chat"]?.lastReadMessageID == "latest" { return }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        precondition(written.wait(timeout: .now() + 3) == .success)
        let persistedData = try Data(contentsOf: unreadURL)
        let persistedWorkspace = try JSONDecoder().decode(BotWorkspaceData.self, from: persistedData)
        precondition(persistedWorkspace.conversationStates["destination-chat"]?.lastReadMessageID == "latest")
        print("PASS: Bot/room persistence, order, session mapping, deletion cleanup, interrupted rounds and corrupt-store protection")
    }
}

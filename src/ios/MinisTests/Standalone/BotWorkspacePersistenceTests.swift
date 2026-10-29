import Foundation

@main
struct BotWorkspacePersistenceTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("workspace.json")
        let store = BotWorkspaceStore(fileURL: file)
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
        let restoredIcons = BotWorkspaceStore(fileURL: root.appendingPathComponent("icons.json"))
        precondition(restoredIcons.bot(custom.id)?.iconImageData == Data([1, 2, 3]))
        precondition(Set(restoredIcons.data.bots.compactMap(\.iconSymbol)).count == BotProfile.builtinIcons.count)
        print("PASS: Bot/room persistence, order, session mapping, deletion preservation, interrupted rounds and corrupt-store protection")
    }
}

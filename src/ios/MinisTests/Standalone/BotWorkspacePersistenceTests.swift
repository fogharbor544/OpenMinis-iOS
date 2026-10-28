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
        precondition(store.append(BotRoomMessage(speaker: "Researcher", botId: researcher.id, text: "Evidence", sessionId: "group-session"), to: room.id))
        let reload = BotWorkspaceStore(fileURL: file)
        precondition(reload.data.bots.count == 2)
        precondition(reload.room(room.id)?.members == [researcher.id, reviewer.id])
        precondition(reload.room(room.id)?.messages.first?.text == "Evidence")
        precondition(reload.bot(forSession: "group-session")?.id == researcher.id)
        reload.deleteBot(researcher.id)
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
        print("PASS: Bot/room persistence, order, session mapping, deletion preservation, interrupted rounds and corrupt-store protection")
    }
}

import Foundation

@main struct BotWorkspaceSearchTests {
    static func main() {
        let bot = BotProfile(name: "Research", sessionId: "private")
        let second = BotProfile(name: "Writer", sessionId: "writer")
        var room = BotRoom(name: "Team", members: [bot.id, second.id])
        room.messages = [BotRoomMessage(speaker: "User", text: String(repeating: "x", count: 200) + "needle evidence")]
        var data = BotWorkspaceData(bots: [bot, second], rooms: [room], sessionOwners: [
            "private": BotSessionOwner(botId: bot.id),
            "writer": BotSessionOwner(botId: second.id),
            "member": BotSessionOwner(botId: bot.id, roomId: room.id),
            "old": BotSessionOwner(botId: bot.id),
            "deleted": BotSessionOwner(botId: "missing")])
        let name = BotWorkspaceSearch.matches(data: data, terms: ["research"], hits: [])
        precondition(name.bots.count == 1 && name.bots[bot.id] != nil && name.rooms.isEmpty)
        let hits = [BotWorkspaceSearch.Hit(sessionID: "private", snippet: "newest"),
                    .init(sessionID: "private", snippet: "duplicate"),
                    .init(sessionID: "member", snippet: "group tool"),
                    .init(sessionID: "old", snippet: "hidden"),
                    .init(sessionID: "deleted", snippet: "deleted"),
                    .init(sessionID: "unknown", snippet: "unknown")]
        let messages = BotWorkspaceSearch.matches(data: data, terms: ["needle"], hits: hits)
        precondition(messages.bots == [bot.id: "newest"])
        precondition(messages.rooms.count == 1 && messages.rooms[room.id]!.contains("needle"))
        precondition(messages.rooms[room.id]!.count <= 120)
        let empty = BotWorkspaceSearch.matches(data: data, terms: [], hits: hits)
        precondition(empty.bots.isEmpty && empty.rooms.isEmpty)
        data.rooms = []
        let deleted = BotWorkspaceSearch.matches(data: data, terms: ["needle"], hits: hits)
        precondition(deleted.rooms.isEmpty)
        print("PASS: Bot/group names, message ownership, deduplication, matching snippets and deleted targets")
    }
}

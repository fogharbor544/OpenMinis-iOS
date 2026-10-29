import SwiftUI

enum SessionCategory {
    static let all: [(key: String, label: String, icon: String, color: Color)] = [
        ("code",         "Code",         "terminal.fill",               .orange),
        ("writing",      "Writing",      "doc.text.fill",               .blue),
        ("research",     "Research",     "globe.americas.fill",         .teal),
        ("analysis",     "Analysis",     "chart.pie.fill",              .indigo),
        ("creative",     "Creative",     "paintbrush.pointed.fill",     .pink),
        ("chat",         "Chat",         "bubble.left.fill",            .green),
        ("math",         "Math",         "number.circle.fill",          .purple),
        ("translation",  "Translation",  "character.bubble",            .cyan),
        ("health",       "Health",       "heart.fill",                  .red),
        ("finance",      "Finance",      "banknote.fill",               .mint),
        ("travel",       "Travel",       "map.fill",                    .orange),
        ("education",    "Education",    "book.closed.fill",            .blue),
        ("design",       "Design",       "paintpalette.fill",           .pink),
        ("productivity", "Productivity", "calendar.badge.checkmark",    .yellow),
        ("support",      "Support",      "gearshape.fill",              .brown),
        ("other",        "Other",        "square.grid.2x2.fill",       .gray),
    ]

}


struct BotProfile: Identifiable, Codable {
    var id = UUID().uuidString
    var name: String
    var instructions = ""
    var modelGroupId: String?
    var sessionId: String?
    var conversationIds: [String] = []
    var iconSymbol: String?
    var iconImageData: Data?
    var skillOverrides: [String: Bool]?
    var connectorOverrides: [String: Bool]?
    var memoryEnabled: Bool?

    static let builtinIcons = SessionCategory.all.map(\.icon)
}

struct BotSessionOwner: Codable {
    var botId: String
    var roomId: String?
    var memoryKey: String { roomId.map { "room:\($0)" } ?? "bot:\(botId)" }
}

struct BotRoomMessage: Identifiable, Codable {
    var id = UUID()
    var speaker: String
    var botId: String?
    var text: String
    var date = Date()
    var sessionId: String?
}

struct BotRoom: Identifiable, Codable {
    var id = UUID().uuidString
    var name: String
    var members: [String]
    var sessions: [String: String] = [:]
    var messages: [BotRoomMessage] = []
    var interrupted = false
    var memoryEnabled: Bool?
}

struct BotWorkspaceData: Codable {
    var bots: [BotProfile] = []
    var rooms: [BotRoom] = []
    var sessionOwners: [String: BotSessionOwner] = [:]
}

@MainActor
final class BotWorkspaceStore: ObservableObject {
    static let shared = BotWorkspaceStore()
    @Published private(set) var data = BotWorkspaceData()
    @Published var errorMessage: String?
    var pendingSessions: [String: Task<String, Error>] = [:]
    private let fileURL: URL
    private var unreadable = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MinisChat/bot-workspace.json")
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                data = try JSONDecoder().decode(BotWorkspaceData.self, from: Data(contentsOf: self.fileURL))
            }
        } catch { unreadable = true; errorMessage = error.localizedDescription }
    }

    func bot(_ id: String) -> BotProfile? { data.bots.first { $0.id == id } }
    func room(_ id: String) -> BotRoom? { data.rooms.first { $0.id == id } }

    func newBot() -> BotProfile {
        let counts = Dictionary(grouping: data.bots.filter { $0.iconImageData == nil },
                                by: { $0.iconSymbol ?? "sparkles" }).mapValues(\.count)
        let symbol = BotProfile.builtinIcons.min { counts[$0, default: 0] < counts[$1, default: 0] }
        return BotProfile(name: "", iconSymbol: symbol, skillOverrides: [:], connectorOverrides: [:], memoryEnabled: true)
    }

    func bot(forSession id: String) -> BotProfile? {
        owner(forSession: id).flatMap { bot($0.botId) }
    }

    func owner(forSession id: String) -> BotSessionOwner? {
        data.sessionOwners[id]
    }

    func memoryEnabled(forSession id: String) -> Bool {
        guard let owner = owner(forSession: id), let bot = bot(owner.botId) else { return false }
        if let roomID = owner.roomId { return room(roomID).map { $0.memoryEnabled ?? true } ?? false }
        return bot.memoryEnabled ?? true
    }

    @discardableResult
    func setMemoryEnabled(_ enabled: Bool, forSession id: String) -> Bool {
        guard let owner = owner(forSession: id) else { return false }
        if let roomID = owner.roomId, var room = room(roomID) {
            room.memoryEnabled = enabled
            return save(room)
        }
        guard owner.roomId == nil, var bot = bot(owner.botId) else { return false }
        bot.memoryEnabled = enabled
        return save(bot)
    }

    /// Copies keep their source's Bot and memory boundary, including group scope.
    @discardableResult
    func inheritOwner(for sessionID: String, from sourceID: String) -> Bool {
        guard let owner = owner(forSession: sourceID),
              let index = data.bots.firstIndex(where: { $0.id == owner.botId }),
              owner.roomId == nil || room(owner.roomId!) != nil else { return false }
        var next = data
        next.sessionOwners[sessionID] = owner
        if owner.roomId == nil && !next.bots[index].conversationIds.contains(sessionID) {
            next.bots[index].conversationIds.append(sessionID)
        }
        return persist(next)
    }

    @discardableResult
    func save(_ profile: BotProfile) -> Bool {
        var profile = profile
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.name.isEmpty else { return false }
        var next = data
        if let index = next.bots.firstIndex(where: { $0.id == profile.id }) { next.bots[index] = profile }
        else { next.bots.append(profile) }
        return persist(next)
    }

    @discardableResult
    func save(_ room: BotRoom) -> Bool {
        guard !room.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !room.members.isEmpty, Set(room.members).count == room.members.count,
              room.members.allSatisfy({ bot($0) != nil }) else { return false }
        var next = data
        if let index = next.rooms.firstIndex(where: { $0.id == room.id }) { next.rooms[index] = room }
        else { next.rooms.append(room) }
        return persist(next)
    }

    func deleteBot(_ id: String) {
        var next = data
        next.bots.removeAll { $0.id == id }
        for index in next.rooms.indices { next.rooms[index].members.removeAll { $0 == id } }
        _ = persist(next) // ChatStore conversations and room history remain available.
    }

    func deleteRoom(_ id: String) {
        var next = data
        next.rooms.removeAll { $0.id == id }
        _ = persist(next)
    }

    @discardableResult
    func append(_ message: BotRoomMessage, to roomID: String) -> Bool {
        var next = data
        guard let index = next.rooms.firstIndex(where: { $0.id == roomID }) else { return false }
        next.rooms[index].messages.append(message)
        return persist(next)
    }

    @discardableResult
    func setRoundActive(_ active: Bool, roomID: String) -> Bool {
        var next = data
        guard let index = next.rooms.firstIndex(where: { $0.id == roomID }) else { return false }
        next.rooms[index].interrupted = active
        return persist(next)
    }

    func persist(_ next: BotWorkspaceData) -> Bool {
        guard !unreadable else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            data = next
            errorMessage = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }


}

enum BotWorkspaceError: LocalizedError {
    case missingBot, botRequired, noModel, storage, busy, rejected(String)
    var errorDescription: String? {
        switch self {
        case .missingBot: return String(localized: "This Bot or group no longer exists.")
        case .botRequired: return String(localized: "Choose a Bot before starting a conversation")
        case .noModel: return String(localized: "Configure an available model group before starting this Bot.")
        case .storage: return String(localized: "Unable to save the Bot workspace.")
        case .busy: return String(localized: "This Bot is already working. Wait or stop its current turn.")
        case .rejected(let reason): return reason
        }
    }
}


/// Search results belong to Bots or groups, never to the hidden runtime sessions.
enum BotWorkspaceSearch {
    struct Hit { let sessionID: String; let snippet: String }

    static func matches(data: BotWorkspaceData, terms: [String], hits: [Hit]) -> (bots: [String: String], rooms: [String: String]) {
        guard !terms.isEmpty else { return ([:], [:]) }
        func contains(_ text: String) -> Bool {
            terms.contains { text.localizedCaseInsensitiveContains($0) }
        }
        var bots: [String: String] = [:]
        var rooms: [String: String] = [:]
        for bot in data.bots where contains(bot.name) { bots[bot.id] = "" }
        for room in data.rooms {
            if contains(room.name) { rooms[room.id] = "" }
            if let message = room.messages.last(where: { contains($0.text) }) {
                // Keep the matched term visible even in a long group message.
                let range = terms.compactMap { message.text.range(of: $0, options: .caseInsensitive) }.first
                let start = range.map { message.text.index($0.lowerBound, offsetBy: -18, limitedBy: message.text.startIndex) ?? message.text.startIndex } ?? message.text.startIndex
                rooms[room.id] = String(message.text[start...].prefix(120))
            }
        }
        for hit in hits {
            guard let owner = data.sessionOwners[hit.sessionID] else { continue }
            if let roomID = owner.roomId {
                guard data.rooms.contains(where: { $0.id == roomID }) else { continue }
                if rooms[roomID] == nil || rooms[roomID] == "" { rooms[roomID] = hit.snippet }
            } else {
                guard data.bots.contains(where: { $0.id == owner.botId && $0.sessionId == hit.sessionID }) else { continue }
                if bots[owner.botId] == nil || bots[owner.botId] == "" { bots[owner.botId] = hit.snippet }
            }
        }
        return (bots, rooms)
    }
}

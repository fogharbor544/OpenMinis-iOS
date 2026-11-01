import SwiftUI

enum BotDataSnapshotLock { static let lock = NSRecursiveLock() }
@MainActor enum BotRestoreControl { static var isRestoring = false }

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


struct BotProfile: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var instructions = ""
    var modelGroupId: String?
    var sessionId: String?
    var conversationIds: [String] = []
    var iconSymbol: String?
    var iconImageData: Data?
    var avatarPresetID: String?
    var avatarResourceVersion: Int? = 1
    var introduction: String?
    var onboarding: BotOnboarding?
    var creationRequestID: String?
    var isBootstrap: Bool?
    var skillOverrides: [String: Bool]? = [:]
    var connectorOverrides: [String: Bool]? = [:]
    var memoryEnabled: Bool? = true
    /// Non-nil while pinned to the top of the home list; the date orders pinned rows.
    var pinnedAt: Date?

    static let builtinIcons = SessionCategory.all.map(\.icon)
    static let commanderID = "builtin-commander"
    var originalAvatar: BotAvatarPreset? {
        guard avatarResourceVersion == nil || avatarResourceVersion == 1 else { return nil }
        return BotAvatarPreset.find(avatarPresetID)
    }
    var isCommander: Bool { id == Self.commanderID }
}

struct BotOnboarding: Codable, Equatable {
    var question: String
    var options: [String]
    var selected: [Int] = []
    var dismissed = false
    var memorySaved: Bool? = nil
}

struct BotAvatarPreset: Identifiable, Equatable {
    let id: String
    let name: String
    var coverAsset: String { "BotAvatar-" + id + "-atlas" }
    var atlasAsset: String { "BotAvatar-" + id + "-atlas" }
    static let all: [BotAvatarPreset] = [
        .init(id: "cloud-bear", name: "云朵小熊"), .init(id: "mint-otter", name: "薄荷水獭"),
        .init(id: "cream-sheep", name: "奶油小羊"), .init(id: "star-owl", name: "星空猫头鹰"),
        .init(id: "peach-rabbit", name: "蜜桃垂耳兔"), .init(id: "amber-fox", name: "琥珀小狐狸"),
        .init(id: "rice-seal", name: "糯米小海豹"), .init(id: "berry-capybara", name: "莓果水豚"),
        .init(id: "grape-raccoon", name: "葡萄小浣熊"), .init(id: "rain-duck", name: "雨滴小鸭"),
        .init(id: "fluff-alpaca", name: "绒球羊驼"), .init(id: "moon-cat", name: "月牙小猫")
    ]
    static func find(_ id: String?) -> Self? { all.first { $0.id == id } }
}

struct BotAvatarChoice: Equatable {
    var presetID: String?
    var symbol: String?
    var imageData: Data?
    init(profile: BotProfile) { presetID = profile.avatarPresetID; symbol = profile.iconSymbol; imageData = profile.iconImageData }
    func apply(to profile: inout BotProfile) {
        profile.avatarPresetID = presetID; profile.avatarResourceVersion = presetID == nil ? nil : 1
        profile.iconSymbol = symbol; profile.iconImageData = imageData
    }
}

enum BotDelegationState: String, Codable {
    case queued, running, reviewing, completed, failed, cancelled, interrupted, takingOver
    var isActive: Bool { self == .queued || self == .running }
    var label: String {
        switch self {
        case .queued: return "排队中"
        case .running: return "执行中"
        case .reviewing: return "待核查"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已停止"
        case .interrupted: return "已中断"
        case .takingOver: return "指挥官接管"
        }
    }
}

struct BotDelegation: Identifiable, Codable, Equatable {
    var id: String
    var fromBotID: String
    var toBotID: String
    var fromName: String
    var toName: String
    var parentSessionID: String
    var childSessionID: String?
    var toolUseID: String
    var jobID: String?
    var title: String
    var task: String
    var state: BotDelegationState = .queued
    var result: String?
    var createdAt = Date()
    var updatedAt = Date()
    var followUpSent = false
    var reworkCount = 0
    var resumesDelegationID: String? = nil
    var toolUseHistory: [String]? = nil
    var statusLabel: String { state == .running && followUpSent ? "已追问，等待进展" : state.label }

}

struct BotMessageQuote: Codable, Equatable, Hashable {
    var sessionID: String
    var messageID: String
    var author: String
    var text: String
}

struct BotConversationState: Codable, Equatable {
    var lastReadMessageID: String?
}

struct BotSessionOwner: Codable, Equatable {
    var botId: String
    var roomId: String?
    var delegationID: String?
    var memoryKey: String { roomId.map { "room:\($0)" } ?? "bot:\(botId)" }
}

struct BotRoomMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var speaker: String
    var botId: String?
    var text: String
    var date = Date()
    var sessionId: String?
}

struct BotRoom: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var members: [String]
    var sessions: [String: String] = [:]
    var messages: [BotRoomMessage] = []
    var interrupted = false
    var memoryEnabled: Bool? = true
    var pinnedAt: Date?
}

struct BotWorkspaceData: Codable, Equatable {
    var bots: [BotProfile] = []
    var rooms: [BotRoom] = []
    var sessionOwners: [String: BotSessionOwner] = [:]
    var delegations: [BotDelegation] = []
    var conversationStates: [String: BotConversationState] = [:]

    init(bots: [BotProfile] = [], rooms: [BotRoom] = [], sessionOwners: [String: BotSessionOwner] = [:],
         delegations: [BotDelegation] = [], conversationStates: [String: BotConversationState] = [:]) {
        self.bots = bots; self.rooms = rooms; self.sessionOwners = sessionOwners
        self.delegations = delegations; self.conversationStates = conversationStates
    }
    enum CodingKeys: String, CodingKey { case bots, rooms, sessionOwners, delegations, conversationStates }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bots = try c.decode([BotProfile].self, forKey: .bots)
        rooms = try c.decode([BotRoom].self, forKey: .rooms)
        sessionOwners = try c.decode([String: BotSessionOwner].self, forKey: .sessionOwners)
        delegations = try c.decodeIfPresent([BotDelegation].self, forKey: .delegations) ?? []
        conversationStates = try c.decodeIfPresent([String: BotConversationState].self, forKey: .conversationStates) ?? [:]
    }
}

@MainActor
final class BotWorkspaceStore: ObservableObject {
    static let shared = BotWorkspaceStore()
    @Published private(set) var data = BotWorkspaceData()
    @Published var errorMessage: String?
    var pendingSessions: [String: Task<String, Error>] = [:]
    private let fileURL: URL
    private var unreadable = false

    init(fileURL: URL? = nil, seedCommander: Bool = true) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                data = try JSONDecoder().decode(BotWorkspaceData.self, from: Data(contentsOf: self.fileURL))
            }
        } catch { unreadable = true; errorMessage = error.localizedDescription }
        if seedCommander && !unreadable {
            var next = data
            for i in next.delegations.indices where next.delegations[i].state.isActive {
                next.delegations[i].state = .interrupted
            }
            if !next.bots.contains(where: \.isCommander) {
                var commander = BotProfile(id: BotProfile.commanderID, name: "指挥官")
                commander.avatarPresetID = "cloud-bear"
                commander.isBootstrap = true
                commander.introduction = "你好，我是指挥官。你可以直接告诉我目标，我会处理任务、协调专职 Bot，并核查结果。"
                next.bots.insert(commander, at: 0)
            }
            if next != data { _ = persist(next) }
        }
    }

    func bot(_ id: String) -> BotProfile? { data.bots.first { $0.id == id } }
    func room(_ id: String) -> BotRoom? { data.rooms.first { $0.id == id } }

    func dataForBackup() throws -> BotWorkspaceData {
        guard !unreadable else { throw BotWorkspaceError.storage }
        return data
    }

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MinisChat/bot-workspace.json")
    }

    /// Owner lookup for nonisolated shell paths (env injection). Reads the
    /// persisted file, which `persist` writes before publishing `data`.
    nonisolated static func ownerBotIdSync(forSession sessionId: String) -> String? {
        struct Owners: Decodable { var sessionOwners: [String: BotSessionOwner] = [:] }
        guard let raw = try? Data(contentsOf: defaultFileURL),
              let decoded = try? JSONDecoder().decode(Owners.self, from: raw) else { return nil }
        return decoded.sessionOwners[sessionId]?.botId
    }

    func setPinned(_ pinned: Bool, botID: String) {
        guard var bot = bot(botID) else { return }
        bot.pinnedAt = pinned ? Date() : nil
        _ = save(bot)
    }

    func setPinned(_ pinned: Bool, roomID: String) {
        guard var room = room(roomID) else { return }
        room.pinnedAt = pinned ? Date() : nil
        _ = save(room)
    }

    func newBot() -> BotProfile {
        let counts = Dictionary(grouping: data.bots.filter { $0.iconImageData == nil },
                                by: { $0.iconSymbol ?? "sparkles" }).mapValues(\.count)
        let symbol = BotProfile.builtinIcons.min { counts[$0, default: 0] < counts[$1, default: 0] }
        var profile = BotProfile(name: "", iconSymbol: symbol, skillOverrides: [:], connectorOverrides: [:], memoryEnabled: true)
        let avatarCounts = Dictionary(grouping: data.bots.compactMap(\.avatarPresetID), by: { $0 }).mapValues(\.count)
        profile.avatarPresetID = BotAvatarPreset.all.min { avatarCounts[$0.id, default: 0] < avatarCounts[$1.id, default: 0] }?.id
        return profile
    }

    func bot(forSession id: String) -> BotProfile? {
        owner(forSession: id).flatMap { bot($0.botId) }
    }

    func owner(forSession id: String) -> BotSessionOwner? {
        data.sessionOwners[id]
    }

    /// Bot and group sessions own their capabilities; helpers inherit the parent.
    func capabilitySessionID(for sessionID: String?, parentSessionID: String?) -> String? {
        if let sessionID, owner(forSession: sessionID) != nil { return sessionID }
        return parentSessionID ?? sessionID
    }

    /// A scoped capability carries its owner's configuration, never its chat history.
    func capabilityOwnerJSON(for botID: String?) throws -> String? {
        guard let botID else { return nil }
        guard var profile = bot(botID) else { throw BotWorkspaceError.missingBot }
        profile.sessionId = nil
        profile.conversationIds = []
        profile.pinnedAt = nil
        return String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
    }

    /// Seed only missing identities. Restoring a capability must not overwrite a local Bot.
    func restoreCapabilityOwner(botID: String?, json: String?) throws {
        guard let botID, bot(botID) == nil else { return }
        guard let json else {
            throw BotWorkspaceError.rejected("The private capability's Bot is missing. Export it again from its source device with the Bot configuration included.")
        }
        var profile = try JSONDecoder().decode(BotProfile.self, from: Data(json.utf8))
        guard profile.id == botID, !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BotWorkspaceError.rejected("The private capability's Bot configuration does not match its owner.")
        }
        profile.sessionId = nil
        profile.conversationIds = []
        profile.pinnedAt = nil
        guard save(profile) else { throw BotWorkspaceError.storage }
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
        guard !BotRestoreControl.isRestoring else { return false }
        var profile = profile
        if profile.isCommander { profile.isBootstrap = false }
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.name.isEmpty else { return false }
        var next = data
        if let index = next.bots.firstIndex(where: { $0.id == profile.id }) { next.bots[index] = profile }
        else { next.bots.append(profile) }
        return persist(next)
    }

    @discardableResult
    func save(_ room: BotRoom) -> Bool {
        guard !BotRestoreControl.isRestoring else { return false }
        guard !room.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !room.members.isEmpty, Set(room.members).count == room.members.count,
              room.members.allSatisfy({ bot($0) != nil }) else { return false }
        var next = data
        if let index = next.rooms.firstIndex(where: { $0.id == room.id }) { next.rooms[index] = room }
        else { next.rooms.append(room) }
        return persist(next)
    }

    func deleteBot(_ id: String) {
        guard !BotRestoreControl.isRestoring else { return }
        guard id != BotProfile.commanderID else { return }
        var next = data
        next.bots.removeAll { $0.id == id }
        for index in next.rooms.indices { next.rooms[index].members.removeAll { $0 == id } }
        _ = persist(next) // ChatStore conversations and room history remain available.
    }

    func delegation(_ id: String) -> BotDelegation? { data.delegations.first { $0.id == id } }

    @discardableResult
    func saveDelegation(_ record: BotDelegation) -> Bool {
        var next = data
        if let index = next.delegations.firstIndex(where: { $0.id == record.id }) { next.delegations[index] = record }
        else { next.delegations.append(record) }
        return persist(next)
    }

    @discardableResult
    func bindDelegation(_ id: String, childSessionID: String, jobID: String) -> Bool {
        guard var record = delegation(id), record.state == .queued, bot(record.toBotID) != nil else { return false }
        record.childSessionID = childSessionID; record.jobID = jobID
        record.state = .running; record.updatedAt = Date()
        var next = data
        next.sessionOwners[childSessionID] = BotSessionOwner(botId: record.toBotID, delegationID: id)
        guard let index = next.delegations.firstIndex(where: { $0.id == id }) else { return false }
        next.delegations[index] = record
        return persist(next)
    }

    @discardableResult
    func updateConversation(_ sessionID: String, _ change: (inout BotConversationState) -> Void) -> Bool {
        var next = data
        var state = next.conversationStates[sessionID] ?? BotConversationState()
        change(&state); next.conversationStates[sessionID] = state
        return next == data || persist(next)
    }

    func latestDelegation(botID: String) -> BotDelegation? {
        data.delegations.filter { $0.toBotID == botID }.max { $0.updatedAt < $1.updatedAt }
    }
    func delegationPreview(botID: String, after date: Date? = nil) -> String? {
        guard let record = latestDelegation(botID: botID), date.map({ record.updatedAt >= $0 }) ?? true else { return nil }
        let direction = record.state == .reviewing || record.state == .completed ? "已回复 \(record.fromName)" : "来自 \(record.fromName)"
        return "\(direction) · \(record.statusLabel)：\(record.title)"
    }

    func deleteRoom(_ id: String) {
        guard !BotRestoreControl.isRestoring else { return }
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
        BotDataSnapshotLock.lock.lock()
        defer { BotDataSnapshotLock.lock.unlock() }
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

import Foundation
import SwiftUI
import SQLite3
import CryptoKit

struct BotMemoryEntry: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var owner: String
    var content: String
    var category: String
    var scope: String
    var sourceSession: String?
    var sourceMessage: String?
    var evidence: String
    var createdAt = Date()
    var updatedAt = Date()
    var status = "active"
    var automatic = false
    var pinned = false
    var grants: [String] = []
    var fingerprint = ""
    var replaces: String?
}

enum BotMemoryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

/// Kept outside the shell-mounted legacy memory directory. Entries, not derived summaries,
/// are authoritative. Tombstones prevent old evidence from recreating forgotten facts.
@MainActor final class BotMemoryStore: ObservableObject {
    static let shared = BotMemoryStore()
    @Published private(set) var revision = 0
    @Published var errorMessage: String?
    @Published private(set) var lastSaved: BotMemoryEntry?
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(fileURL: URL? = nil) {
        let url = fileURL ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MinisBotMemory/entries.sqlite")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                throw BotMemoryError.invalid("Unable to open Bot memory database.")
            }
            try execute("CREATE TABLE IF NOT EXISTS memories (id TEXT PRIMARY KEY, owner TEXT NOT NULL, payload TEXT NOT NULL)")
            try execute("CREATE INDEX IF NOT EXISTS memory_owner ON memories(owner)")
            try execute("PRAGMA secure_delete=ON")
        } catch { errorMessage = error.localizedDescription }
    }

    deinit { if let db { sqlite3_close(db) } }

    private func execute(_ sql: String) throws {
        guard let db, sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw BotMemoryError.invalid("Unable to update Bot memory database.")
        }
    }

    func entries() throws -> [BotMemoryEntry] {
        guard let db else { throw BotMemoryError.invalid("Bot memory is unavailable.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM memories", -1, &statement, nil) == SQLITE_OK else {
            throw BotMemoryError.invalid("Unable to read Bot memories.")
        }
        defer { sqlite3_finalize(statement) }
        var result: [BotMemoryEntry] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
                throw BotMemoryError.invalid("Unable to read Bot memories.")
            }
            result.append(try JSONDecoder().decode(BotMemoryEntry.self, from: Data(String(cString: value).utf8)))
        }
    }

    private func write(_ entry: BotMemoryEntry) throws {
        guard let db else { throw BotMemoryError.invalid("Bot memory is unavailable.") }
        let payload = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO memories(id,owner,payload) VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK else {
            throw BotMemoryError.invalid("Unable to save Bot memory.")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, entry.id, -1, transient)
        sqlite3_bind_text(statement, 2, entry.owner, -1, transient)
        sqlite3_bind_text(statement, 3, payload, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw BotMemoryError.invalid("Unable to save Bot memory.") }
    }

    /// The transfer journal coordinates this transaction with the workspace file.
    func replaceForRestore(_ snapshot: [BotMemoryEntry]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM memories")
            for entry in snapshot { try write(entry) }
            try execute("COMMIT")
        } catch {
            try execute("ROLLBACK")
            throw error
        }
        lastSaved = nil
        revision += 1
    }

    static func fingerprint(_ text: String) -> String {
        let normalized = text.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func containsSecret(_ text: String) -> Bool {
        let pattern = #"(?i)(password|passwd|api[ _-]?key|secret[ _-]?key|access[ _-]?token|验证码|密码|私钥|密钥|助记词|one[ -]?time code|BEGIN .*PRIVATE KEY|\bsk-[A-Za-z0-9]{12,})"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    @discardableResult
    func save(_ draft: BotMemoryEntry, replacing id: String? = nil, userInitiated: Bool = false) throws -> BotMemoryEntry {
        var entry = draft
        entry.content = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.scope = entry.scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.owner.isEmpty, !entry.content.isEmpty, entry.content.count <= 2000,
              !entry.scope.isEmpty, entry.scope.count <= 160, entry.evidence.count <= 2000,
              ["preference", "fact", "convention", "experience"].contains(entry.category),
              !Self.containsSecret(entry.content), !Self.containsSecret(entry.scope), !Self.containsSecret(entry.evidence)
        else { throw BotMemoryError.invalid("Use one concise memory without passwords, codes or secrets (up to 2000 characters; scope up to 160).") }
        entry.fingerprint = Self.fingerprint(entry.content)
        let all = try entries().filter { $0.owner == entry.owner }
        if let duplicate = all.first(where: { $0.id != id && $0.status == "active" && $0.fingerprint == entry.fingerprint && $0.scope == entry.scope }) {
            guard id == nil else { throw BotMemoryError.invalid("An identical memory already exists. Delete the obsolete entry instead of creating a duplicate correction.") }
            return duplicate
        }
        if !userInitiated, all.contains(where: {
            $0.status != "active" && ($0.fingerprint == entry.fingerprint ||
                (entry.sourceMessage != nil && $0.sourceMessage == entry.sourceMessage && $0.sourceSession == entry.sourceSession))
        }) { throw BotMemoryError.invalid("This memory or its source was forgotten/replaced. Only an explicit user action can save it again.") }
        var previous: BotMemoryEntry?
        if let id {
            guard userInitiated, let old = all.first(where: { $0.id == id && $0.status == "active" }) else {
                throw BotMemoryError.invalid("Replacing memory requires an explicit user correction and a valid entry ID.")
            }
            previous = old
            entry.replaces = id
        }
        try execute("BEGIN IMMEDIATE")
        do {
            if var old = previous { old.status = "replaced"; old.updatedAt = Date(); old.grants = []; try write(old) }
            try write(entry)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        revision += 1
        lastSaved = entry
        return entry
    }

    func forget(id: String, owner: String) throws {
        let owned = try entries().filter { $0.owner == owner }
        guard let entry = owned.first(where: { $0.id == id && $0.status == "active" }) else {
            throw BotMemoryError.invalid("Memory entry not found.")
        }
        // Forget the superseded versions too; only fingerprints/source keys remain
        // as suppression markers, never a hidden plaintext archive of the forgotten fact.
        var lineage = [entry]
        var previous = entry.replaces
        while let key = previous, let old = owned.first(where: { $0.id == key }), !lineage.contains(where: { $0.id == key }) {
            lineage.append(old); previous = old.replaces
        }
        try execute("BEGIN IMMEDIATE")
        do {
            for var version in lineage {
                version.status = "deleted"; version.content = ""; version.scope = ""; version.evidence = ""; version.grants = []; version.updatedAt = Date()
                try write(version)
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        if lastSaved?.id == id { lastSaved = nil }
        revision += 1
    }

    func forgetOwner(_ owner: String) throws {
        let owned = try entries().filter { $0.owner == owner }
        try execute("BEGIN IMMEDIATE")
        do {
            for var entry in owned {
                entry.status = "deleted"; entry.content = ""; entry.scope = ""; entry.evidence = ""; entry.grants = []; entry.updatedAt = Date()
                try write(entry)
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        if lastSaved?.owner == owner { lastSaved = nil }
        revision += 1
    }

    func setGrants(id: String, owner: String, grants: [String]) throws {
        guard var entry = try entries().first(where: { $0.id == id && $0.owner == owner && $0.status == "active" }) else {
            throw BotMemoryError.invalid("Memory entry not found.")
        }
        entry.grants = Array(Set(grants)).sorted(); entry.updatedAt = Date()
        try write(entry); revision += 1
    }

    func visible(to owner: String) throws -> [BotMemoryEntry] {
        try entries().filter { $0.status == "active" && ($0.owner == owner || $0.grants.contains(owner)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Match the original daily-log injection without reopening shared Markdown storage.
    /// Visibility is resolved first, so date grouping cannot leak private Bot memories.
    func recentContext(owner: String, now: Date = Date(), dateCalendar: Calendar = .current) throws -> String {
        let entries = try visible(to: owner).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
        func line(_ entry: BotMemoryEntry) -> String {
            "[\(entry.id)] [\(entry.category); \(entry.scope)] \(entry.content)"
        }
        var sections: [String] = []
        let pinned = entries.filter(\.pinned)
        if !pinned.isEmpty { sections.append("Pinned:\n" + pinned.map(line).joined(separator: "\n")) }
        let today = dateCalendar.startOfDay(for: now)
        guard let start = dateCalendar.date(byAdding: .day, value: -29, to: today) else { return sections.joined(separator: "\n\n") }
        let recent = entries.filter { !$0.pinned && $0.createdAt >= start && $0.createdAt <= now }
        let days = Dictionary(grouping: recent) { dateCalendar.startOfDay(for: $0.createdAt) }
        let formatter = DateFormatter()
        formatter.calendar = dateCalendar; formatter.timeZone = dateCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        for day in days.keys.sorted(by: >).prefix(3) {
            let lines = (days[day] ?? []).map(line).joined(separator: "\n").components(separatedBy: .newlines)
            sections.append("\(formatter.string(from: day)):\n" + lines.prefix(200).joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    func recall(owner: String, query: String, limit: Int = 8, budget: Int = 4000) throws -> String {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        // CJK questions often have no spaces; two-character shingles avoid treating the
        // entire question as one exact-match keyword. No embedding service is required.
        let cjk = Array(query.unicodeScalars.filter { (0x3400...0x9fff).contains(Int($0.value)) }.map(String.init))
        let shingles = cjk.count > 1 ? (0..<(cjk.count - 1)).map { cjk[$0] + cjk[$0 + 1] } : []
        let keywords = Array(Set(terms + shingles))
        var ranked: [(entry: BotMemoryEntry, score: Int)] = []
        for entry in try visible(to: owner) {
            let haystack = (entry.content + " " + entry.scope).lowercased()
            var score = entry.pinned ? 100 : 0
            for keyword in keywords where haystack.contains(keyword) { score += 1 }
            if query.isEmpty || score > 0 { ranked.append((entry: entry, score: score)) }
        }
        ranked.sort { left, right in
            if left.score != right.score { return left.score > right.score }
            return left.entry.updatedAt > right.entry.updatedAt
        }
        var output = ""
        for (entry, _) in ranked.prefix(limit) {
            let line = "[\(entry.id)] [\(entry.category); \(entry.scope)] \(entry.content)\n"
            guard output.count + line.count <= budget else { continue }
            output += line
        }
        return output
    }
}

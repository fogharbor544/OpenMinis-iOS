import Foundation
import SQLite3

enum BotDataSnapshotLock { static let lock = NSRecursiveLock() }
actor ChatStore {
    var db: OpaquePointer?
    var dirty: [String] = []
    init(fileURL: URL) {
        precondition(sqlite3_open(fileURL.path, &db) == SQLITE_OK)
        let schema = "CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, model_id TEXT); CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, session_id TEXT, role TEXT, token_usage TEXT, updated_at REAL, created_at REAL, model_id TEXT, model_display_name TEXT, provider_type TEXT);"
        precondition(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    }
    deinit { sqlite3_close(db) }
    func bindOptionalText(_ statement: OpaquePointer?, index: Int32, value: String?) {
        if let value { value.withCString { _ = sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) } }
        else { sqlite3_bind_null(statement, index) }
    }
    func markDirty(recordType: String, recordId: String) { dirty.append(recordId) }
    func seed(_ usage: StoredTokenUsage) throws {
        precondition(sqlite3_exec(db, "INSERT INTO sessions VALUES ('s', 'model');", nil, nil, nil) == SQLITE_OK)
        var statement: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, "INSERT INTO messages VALUES ('reply', 's', 'assistant', ?, 0, 1000, 'model', 'Model', 'provider')", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        bindOptionalText(statement, index: 1, value: String(decoding: try JSONEncoder().encode(usage), as: UTF8.self))
        precondition(sqlite3_step(statement) == SQLITE_DONE)
    }
    func stored() throws -> StoredTokenUsage {
        var statement: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, "SELECT token_usage FROM messages WHERE id = 'reply'", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        precondition(sqlite3_step(statement) == SQLITE_ROW)
        guard let payload = sqlite3_column_text(statement, 0) else { fatalError("Missing usage JSON") }
        return try JSONDecoder().decode(StoredTokenUsage.self, from: Data(String(cString: payload).utf8))
    }
    func messageCount() -> Int {
        var statement: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM messages", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        precondition(sqlite3_step(statement) == SQLITE_ROW)
        return Int(sqlite3_column_int(statement, 0))
    }
}
@main struct AuxiliaryUsagePersistenceTests {
    static func main() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aux-usage-" + UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ChatStore(fileURL: url)
        let primary = StoredTokenUsage(inputTokens: 100, outputTokens: 20, cacheCreationTokens: 4, cacheReadTokens: 3, latestContextTokens: 120, estimatedRequestTokens: 115, calibrationModelId: "model")
        try await store.seed(primary)
        let auxiliary = StoredTokenUsage(inputTokens: 10, outputTokens: 5, cacheCreationTokens: 2, cacheReadTokens: 1, latestContextTokens: nil)
        let saved = await store.addAuxiliaryUsage(auxiliary, messageID: "reply", sessionID: "s")
        precondition(saved)
        let wrongSession = await store.addAuxiliaryUsage(auxiliary, messageID: "reply", sessionID: "another")
        let missing = await store.addAuxiliaryUsage(auxiliary, messageID: "deleted", sessionID: "s")
        precondition(!wrongSession && !missing)
        let reopened = ChatStore(fileURL: url)
        let loaded = try await reopened.stored()
        precondition(loaded.inputTokens == 100 && loaded.outputTokens == 20)
        precondition(loaded.latestContextTokens == 120 && loaded.estimatedRequestTokens == 115 && loaded.calibrationModelId == "model")
        precondition(loaded.billedUsage.inputTokens == 110 && loaded.billedUsage.outputTokens == 25)
        precondition(loaded.billedUsage.cacheCreationTokens == 6 && loaded.billedUsage.cacheReadTokens == 4)
        let records = await reopened.fetchUsageStats()
        precondition(records.count == 2 && records.reduce(0) { $0 + $1.usage.inputTokens } == 110)
        precondition(records.allSatisfy { $0.modelId == "model" && $0.hasSnapshot })
        let count = await reopened.messageCount()
        precondition(count == 1, "Accounting must not create a chat message")
        let roundtrip = try JSONDecoder().decode(StoredTokenUsage.self, from: JSONEncoder().encode(loaded))
        precondition(roundtrip == loaded, "Sync/archive JSON preserves auxiliary accounting")
        let legacy = try JSONDecoder().decode(StoredTokenUsage.self, from: Data(#"{"inputTokens":7,"outputTokens":3,"cacheCreationTokens":0,"cacheReadTokens":0}"#.utf8))
        precondition(legacy.billedUsage.inputTokens == 7 && legacy.auxiliaryUsage == nil)
        print("PASS: shipping SQLite auxiliary billing survives reload/JSON, leaves context calibration unchanged, preserves model attribution, avoids chat rows and refuses missing/wrong-session writes")
    }
}

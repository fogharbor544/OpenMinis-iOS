import Foundation
import SQLite3

enum BackupFormat { static let current = "minisbak/4" }
actor ChatStore {
    let db: OpaquePointer?
    var invalidations = 0
    init(url: URL, readOnly: Bool = false) {
        var connection: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        precondition(sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK)
        db = connection
    }
    deinit { sqlite3_close(db) }
    func invalidateSessionListCache() { invalidations += 1 }
    func execute(_ sql: String) {
        precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, String(cString: sqlite3_errmsg(db)))
    }
    func value(_ sql: String) -> String {
        var statement: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        precondition(sqlite3_step(statement) == SQLITE_ROW)
        return String(cString: sqlite3_column_text(statement, 0))
    }
}

@main struct BotFrozenSnapshotTests {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let liveURL = root.appendingPathComponent("live.sqlite")
        let live = ChatStore(url: liveURL)
        await live.execute("PRAGMA journal_mode=WAL; CREATE TABLE messages (id TEXT PRIMARY KEY, content TEXT); CREATE TABLE message_presentation (message_id TEXT PRIMARY KEY, payload TEXT); INSERT INTO messages VALUES ('before', 'frozen'); INSERT INTO message_presentation VALUES ('before', 'quote-and-group');")
        let store = BotWorkspaceStore.shared
        var commander = store.bot(BotProfile.commanderID)!
        commander.sessionId = "parent"; commander.conversationIds = ["parent"]
        precondition(store.save(commander))
        var specialist = store.newBot(); specialist.name = "Frozen name"
        specialist.sessionId = "private"; specialist.conversationIds = ["private"]
        precondition(store.save(specialist))
        var graph = store.data
        graph.sessionOwners = ["parent": BotSessionOwner(botId: commander.id), "private": BotSessionOwner(botId: specialist.id)]
        graph.delegations = [BotDelegation(id: "handoff", fromBotID: commander.id, toBotID: specialist.id,
            fromName: commander.name, toName: specialist.name, parentSessionID: "parent", toolUseID: "call", title: "Work", task: "Brief")]
        precondition(store.persist(graph))
        precondition(store.bindDelegation("handoff", childSessionID: "hidden-child", jobID: "live-job"))
        let memory = BotMemoryEntry(owner: "bot:" + specialist.id, content: "Frozen preference", category: "preference", scope: "onboarding", evidence: "Explicit user choice")
        try BotMemoryStore.shared.replaceForRestore([memory])
        let snapshot = BotBackupSnapshot(directory: root.appendingPathComponent("frozen"))
        let date = try snapshot.capture(sourceDatabase: liveURL, resuming: false, includesHistory: true)
        await live.execute("INSERT INTO messages VALUES ('after', 'live-only'); DELETE FROM message_presentation;")
        specialist.name = "Changed later"; precondition(store.save(specialist))
        try BotMemoryStore.shared.replaceForRestore([])
        let resumedDate = try snapshot.capture(sourceDatabase: liveURL, resuming: true, includesHistory: true)
        precondition(resumedDate == date)
        let frozen = ChatStore(url: snapshot.databaseURL, readOnly: true)
        let journalMode = await frozen.value("PRAGMA journal_mode")
        precondition(journalMode == "delete", "A frozen export must not need WAL sidecar files")
        let count = await frozen.value("SELECT count(*) FROM messages")
        let metadata = await frozen.value("SELECT payload FROM message_presentation WHERE message_id='before'")
        precondition(count == "1" && metadata == "quote-and-group")
        for suffix in ["-wal", "-shm"] {
            precondition(!FileManager.default.fileExists(atPath: snapshot.databaseURL.path + suffix))
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(BotWorkspaceArchive.self, from: Data(contentsOf: snapshot.archiveURL))
        precondition(archive.workspace.bots.first(where: { $0.id == specialist.id })?.name == "Frozen name")
        precondition(archive.workspace.sessionOwners["hidden-child"]?.delegationID == "handoff" && archive.memories.count == 1 && archive.memories[0].content == memory.content)
        try await live.restoreGraphDatabase(from: snapshot.databaseURL)
        let restoredCount = await live.value("SELECT count(*) FROM messages")
        let restoredMetadata = await live.value("SELECT payload FROM message_presentation WHERE message_id='before'")
        let invalidations = await live.invalidations
        precondition(restoredCount == "1" && restoredMetadata == metadata && invalidations == 1)
        let invalid = root.appendingPathComponent("corrupt.sqlite")
        try Data("not a SQLite database".utf8).write(to: invalid)
        do { try await live.restoreGraphDatabase(from: invalid); preconditionFailure("Corrupt rollback checkpoint accepted") }
        catch BotWorkspaceError.storage { }
        let afterFailure = await live.value("SELECT content FROM messages WHERE id='before'")
        precondition(afterFailure == "frozen")
        do { _ = try snapshot.capture(sourceDatabase: nil, resuming: true, includesHistory: false); preconditionFailure("Mixed snapshot options accepted") }
        catch BotWorkspaceError.storage { }
        let unfinished = BotBackupSnapshot(directory: root.appendingPathComponent("unfinished"))
        do { _ = try unfinished.capture(sourceDatabase: liveURL, resuming: true, includesHistory: true); preconditionFailure("Incomplete snapshot resumed from live data") }
        catch BotWorkspaceError.rejected { }
        let config = BotBackupSnapshot(directory: root.appendingPathComponent("config-only"))
        _ = try config.capture(sourceDatabase: nil, resuming: false, includesHistory: false)
        precondition(!FileManager.default.fileExists(atPath: config.databaseURL.path))
        let configArchive = try decoder.decode(BotWorkspaceArchive.self, from: Data(contentsOf: config.archiveURL))
        let pruned = try BotWorkspaceArchive.capture(workspace: configArchive.workspace, memories: configArchive.memories, sessionIDs: [], includesHistory: false)
        precondition(pruned.workspace.delegations.isEmpty && pruned.workspace.sessionOwners.isEmpty)
        print("PASS: shipping SQLite WAL snapshot, stable resume, frozen workspace/memory/hidden ownership, metadata preservation, live-connection rollback, corrupt rollback rejection and configuration-only snapshot")
    }
}

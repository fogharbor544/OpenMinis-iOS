import Foundation
import SQLite3

/// Shared only by synchronous persistence boundaries; never held across an await.
/// An independent SQLite connection lets the main actor capture the graph without
/// waiting for another actor while holding this lock.
struct BotBackupSnapshot {
    let directory: URL
    var databaseURL: URL { directory.appendingPathComponent("chat.sqlite") }
    var archiveURL: URL { directory.appendingPathComponent("agents.json") }
    var markerURL: URL { directory.appendingPathComponent("ready.json") }
    struct Marker: Codable { var format: String; var capturedAt: Date; var includesHistory: Bool }

    @MainActor func capture(sourceDatabase: URL?, resuming: Bool, includesHistory: Bool) throws -> Date {
        if FileManager.default.fileExists(atPath: markerURL.path) {
            let marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: markerURL))
            guard marker.format == BackupFormat.current,
                  (!includesHistory || FileManager.default.fileExists(atPath: databaseURL.path)),
                  marker.includesHistory == includesHistory,
                  FileManager.default.fileExists(atPath: archiveURL.path) else { throw BotWorkspaceError.storage }
            return marker.capturedAt
        }
        guard !resuming else {
            throw BotWorkspaceError.rejected("备份快照未完成或版本不支持，请新建备份；不会混用当前数据继续旧快照。")
        }
        BotDataSnapshotLock.lock.lock()
        defer { BotDataSnapshotLock.lock.unlock() }
        guard BotWorkspaceStore.shared.pendingSessions.isEmpty else { throw BotWorkspaceError.rejected("请等待 Bot 会话创建完成后再备份。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = Date()
        let archive = BotWorkspaceArchive(includesHistory: true,
            workspace: try BotWorkspaceStore.shared.dataForBackup(), memories: try BotMemoryStore.shared.entries())
        if includesHistory {
            guard let sourceDatabase else { throw BotWorkspaceError.storage }
            try Self.copyDatabase(from: sourceDatabase, to: databaseURL)
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(archive).write(to: archiveURL, options: .atomic)
        try JSONEncoder().encode(Marker(format: BackupFormat.current, capturedAt: timestamp, includesHistory: includesHistory)).write(to: markerURL, options: .atomic)
        return timestamp
    }

    static func copyDatabase(from source: URL, to target: URL) throws {
        var input: OpaquePointer?
        var output: OpaquePointer?
        defer { sqlite3_close(input); sqlite3_close(output) }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              sqlite3_open(target.path, &output) == SQLITE_OK else { throw BotWorkspaceError.storage }
        sqlite3_busy_timeout(input, 5000); sqlite3_busy_timeout(output, 5000)
        guard let backup = sqlite3_backup_init(output, "main", input, "main") else { throw BotWorkspaceError.storage }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard step == SQLITE_DONE && finish == SQLITE_OK else { throw BotWorkspaceError.storage }
    }
}

extension ChatStore {
    /// Replace contents through SQLite so the actor's open connection remains valid.
    func restoreGraphDatabase(from source: URL) throws {
        BotDataSnapshotLock.lock.lock()
        defer { BotDataSnapshotLock.lock.unlock() }
        var input: OpaquePointer?
        defer { sqlite3_close(input) }
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let backup = sqlite3_backup_init(db, "main", input, "main") else { throw BotWorkspaceError.storage }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard step == SQLITE_DONE && finish == SQLITE_OK else { throw BotWorkspaceError.storage }
        invalidateSessionListCache()
    }
}

/// A durable checkpoint for the related chats + Bot/memory graph. Independent
/// backup categories keep their existing category-level rollback semantics.
@MainActor enum BotGraphRestore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BotGraphRestore", isDirectory: true)
    }
    static var ready: URL { directory.appendingPathComponent("ready") }
    static func begin(databaseURL: URL) async throws {
        guard SessionActivityTracker.shared.activeSessions.isEmpty && !UserAskCenter.shared.hasWaitingCalls && !BotWorkspaceStore.shared.data.delegations.contains(where: { $0.state.isActive || $0.state == .takingOver }), BotRoomRunner.shared.activeRooms.isEmpty,
              !AgentJobRegistry.shared.hasPendingSpecialistStop else { throw BotWorkspaceError.rejected("请等待正在运行或停止中的任务结束。") }
        guard !FileManager.default.fileExists(atPath: ready.path) else {
            throw BotWorkspaceError.rejected("上次 Bot 恢复尚未恢复，请重新启动应用。")
        }
        BotRestoreControl.isRestoring = true
        await SyncCore.shared.holdInboundForBotRestore()
        do { try stageCheckpoint(databaseURL: databaseURL) }
        catch { BotRestoreControl.isRestoring = false; throw error }
    }
    private static func stageCheckpoint(databaseURL: URL) throws {
        BotDataSnapshotLock.lock.lock(); defer { BotDataSnapshotLock.lock.unlock() }
        guard BotWorkspaceStore.shared.pendingSessions.isEmpty else { throw BotWorkspaceError.rejected("请等待 Bot 会话创建完成后再备份。") }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try BotBackupSnapshot.copyDatabase(from: databaseURL, to: directory.appendingPathComponent("chat.sqlite"))
        let prior = BotWorkspaceArchive(includesHistory: true, workspace: try BotWorkspaceStore.shared.dataForBackup(), memories: try BotMemoryStore.shared.entries())
        try JSONEncoder().encode(prior).write(to: directory.appendingPathComponent("agents.json"), options: .atomic)
        try Data("ready".utf8).write(to: ready, options: .atomic)
    }

    static func recover() async throws {
        guard FileManager.default.fileExists(atPath: ready.path) else { return }
        BotRestoreControl.isRestoring = true
        await SyncCore.shared.holdInboundForBotRestore()
        let prior = try JSONDecoder().decode(BotWorkspaceArchive.self, from: Data(contentsOf: directory.appendingPathComponent("agents.json")))
        try await ChatStore.shared.restoreGraphDatabase(from: directory.appendingPathComponent("chat.sqlite"))
        try BotMemoryStore.shared.replaceForRestore(prior.memories)
        guard BotWorkspaceStore.shared.persist(prior.workspace) else { throw BotWorkspaceError.storage }
        try commit()
    }
    static func commit(discardingSessions: Set<String> = []) throws {
        if FileManager.default.fileExists(atPath: ready.path) { try FileManager.default.removeItem(at: ready) }
        UserAskCenter.shared.discardForRestoredSessions(discardingSessions)
        BotRestoreControl.isRestoring = false
        if FileManager.default.fileExists(atPath: directory.path) {
            do { try FileManager.default.removeItem(at: directory) }
            catch { AppLogger(category: "Backup").warning("[Restore] Committed checkpoint cleanup failed: \(error.localizedDescription)") }
        }
    }
}

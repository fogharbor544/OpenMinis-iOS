
import Foundation
import SQLite3
import SwiftAnthropic
import UIKit
import os.log

// MARK: - Sync Support

private let iCloudLogger = AppLogger(category: "iCloud")

extension ChatStore {

    // MARK: - Sync Dirty Tracking

    /// Mark a record as needing sync to iCloud. Only active in DEBUG builds.
    func markDirty(recordType: String, recordId: String, operation: String = "upsert", priority: Int = 0) {
        // DIAG: log every silent early-return so "I added a Skill but
        // no markDirty appears in logs" can be diagnosed without
        // re-instrumenting. Previously both guards returned silently,
        // making it impossible to distinguish "code path not reached"
        // from "user toggled the category off in Settings".
        guard !syncZoneName.isEmpty else {
            iCloudLogger.info("[iCloudTrace] markDirty SKIP type=\(recordType) id=\(recordId.prefix(20)) op=\(operation) reason=zoneEmpty(syncNotInitialized)")
            return
        }
        // User-configurable upload policy: skip categories the user has
        // disabled in iCloud Sync settings (Chat Sessions / Skills /
        // Providers / Environments / Session Files). SyncDeviceV2 is
        // always allowed because peer discovery depends on it.
        guard UploadPolicy.allowsRecordType(recordType) else {
            iCloudLogger.info("[iCloudTrace] markDirty SKIP type=\(recordType) id=\(recordId.prefix(20)) op=\(operation) reason=uploadPolicyDisabled(user-toggled-off-in-Settings)")
            return
        }
        // [T-icloud-record-delete-resurrection] A local op=delete on these
        // types must leave a recent-delete tombstone so an inbound merge that
        // races ahead of the cloud delete (fetchRecentV2 re-pulling the still-
        // live record) can't resurrect it. Session/Message/SessionFile have
        // their own session-level tombstone path (recordDeletedSessionTombstone).
        // [T-sync-message-resurrection] `Message` is on this list so that
        // mergeRemoteMessage can refuse the echo of a just-deleted row (see
        // that function): without a local tombstone, CloudKit handing back
        // the record this device pushed moments before the delete re-inserts
        // the whole turn the user had just retried away.
        if operation == "delete",
           ["Skill", "EnvVarItem", "CompactMarker", "MCPServerItem", "Folder",
            "ProviderInstanceV3", "ProviderModelEntryV3", "ProviderModelGroupV3",
            "ProviderThinkingRuleV3", "SubAgentV3", "Message"].contains(recordType) {
            recordDeletedRecordTombstone(type: recordType, id: recordId)
        }
        if priority == 0 {
            // [T-ios-log-noise-reduction] INFO→DEBUG: per-record markDirty
            // trace (~876 lines/day). The SKIP-reason variants above stay INFO
            // since they indicate sync NOT happening (more diagnostic value).
            iCloudLogger.debug("[iCloudTrace] markDirty type=\(recordType) id=\(recordId.prefix(20)) op=\(operation)")
        }
        let zoneName = syncZoneName
        let now = Date().timeIntervalSince1970
        let sql = """
            INSERT OR REPLACE INTO sync_dirty_records (record_type, record_id, zone_name, operation, priority, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        let syncType = Self.syncRecordType(for: recordType)
        guard Self.v2SyncRecordTypes.contains(syncType) else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (syncType as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (recordId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (zoneName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (operation as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 5, Int32(priority))
            sqlite3_bind_double(stmt, 6, now)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        // Schedule a debounced send so local changes are uploaded promptly
        // without triggering a full sync on every individual write.
        // Skip during agent processing (syncSendDeferred) — flushPendingSyncDirty
        // will trigger a single send when the agent loop finishes.
        if !syncSendDeferred {
            if #available(iOS 17.0, *) {
                Task { @MainActor in
                    // Drive whichever engine the user is currently on.
                    if SyncV2Bootstrap.isEnabled {
                        SyncCore.shared.scheduleSend()
                    }
                }
            }
        }
    }

    private static func syncRecordType(for type: String) -> String {
        switch type {
        case "Session":         return "SessionV2"
        case "Message":         return "MessageV2"
        case "CompactMarker":   return "CompactMarkerV2"
        case "SessionFile":     return "SessionFileV2"
        case "Skill":           return "SkillV2"
        case "SyncDevice":      return "SyncDeviceV2"
        case "Soul":            return "SoulV2"
        case "Folder":          return "FolderV2"
        default:                return type
        }
    }

    /// Force-mark a session and all its messages/compact markers as dirty for iCloud sync.
    func forceMarkSessionDirty(sessionId: String) {
        markDirty(recordType: "Session", recordId: sessionId)
        // Mark all messages in this session as dirty
        let msgSql = "SELECT id FROM messages WHERE session_id = ?"
        var msgStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, msgSql, -1, &msgStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(msgStmt, 1, (sessionId as NSString).utf8String, -1, nil)
            while sqlite3_step(msgStmt) == SQLITE_ROW {
                let msgId = String(cString: sqlite3_column_text(msgStmt, 0))
                markDirty(recordType: "Message", recordId: msgId)
            }
        }
        sqlite3_finalize(msgStmt)
        // Mark compact markers
        let cmSql = "SELECT id FROM compact_markers WHERE session_id = ?"
        var cmStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, cmSql, -1, &cmStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(cmStmt, 1, (sessionId as NSString).utf8String, -1, nil)
            while sqlite3_step(cmStmt) == SQLITE_ROW {
                let cmId = String(cString: sqlite3_column_text(cmStmt, 0))
                markDirty(recordType: "CompactMarker", recordId: cmId)
            }
        }
        sqlite3_finalize(cmStmt)
        // Mark session files (workspace/offloads/attachments)
        scanAndMarkSessionFiles(sessionId: sessionId)
    }

    /// Backfill: merge all remote_sessions and remote_messages into local tables.
    /// Called after code change that introduced mergeRemoteSession, to retroactively merge
    /// data that was fetched before the merge logic existed.
    /// Mark a session as successfully synced to iCloud.
    func markSessionSynced(id: String) {
        let sql = "UPDATE sessions SET last_synced_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    struct DirtyRecord {
        let recordType: String
        let recordId: String
        let zoneName: String
        let operation: String
    }

    fileprivate static let v2SyncRecordTypes: [String] = [
        "SessionV2", "MessageV2", "CompactMarkerV2", "SessionFileV2",
        "FolderV2",
        "SkillV2", "EnvVarItem",
        "EnvVarStateItem",  // [T-envvar-disable]
        "SyncDeviceV2", "SoulV2",
        "ProviderInstanceV3", "ProviderModelEntryV3", "ProviderModelGroupV3",
        // [T-icloud-thinking-rules-sync] Per-rule custom thinking rules. Omitting a
        // type here is the exact failure MCPServersV2 hit below: dirty rows get
        // written but loadDirtyRecords filters them out, so nothing ever uploads
        // and the type fails SILENTLY.
        "ProviderThinkingRuleV3",
        // [T-subagent-own-store] Same rule: omit the type here and its dirty
        // rows are written but filtered out by loadDirtyRecords, so the roster
        // would never upload and the failure would be SILENT.
        "SubAgentV3",
        "MCPServerItem",
    ]

    /// Pre-built SQL IN-list fragment for `v2SyncRecordTypes`. Values
    /// are static identifiers, no user input — safe to interpolate.
    fileprivate static let v2SyncRecordTypesSQL: String =
        v2SyncRecordTypes.map { "'\($0)'" }.joined(separator: ",")

    func dumpAllDirtyTypes() -> [(type: String, count: Int)] {
        var result: [(type: String, count: Int)] = []
        var stmt: OpaquePointer?
        let sql = "SELECT record_type, COUNT(*) FROM sync_dirty_records GROUP BY record_type"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let t = String(cString: sqlite3_column_text(stmt, 0))
                let c = Int(sqlite3_column_int(stmt, 1))
                result.append((t, c))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func loadDirtyRecords(v2Only: Bool = false) -> [DirtyRecord] {
        let whereClause = v2Only ? "WHERE record_type IN (\(Self.v2SyncRecordTypesSQL))" : ""
        let sql = """
            SELECT record_type, record_id, zone_name, operation FROM sync_dirty_records
            \(whereClause)
            ORDER BY priority ASC,
                CASE record_type
                    WHEN 'Session' THEN 0
                    WHEN 'SessionV2' THEN 0
                    WHEN 'Message' THEN 1
                    WHEN 'MessageV2' THEN 1
                    ELSE 2
                END,
                created_at ASC
            LIMIT 100
        """
        var stmt: OpaquePointer?
        var records: [DirtyRecord] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                records.append(DirtyRecord(
                    recordType: String(cString: sqlite3_column_text(stmt, 0)),
                    recordId: String(cString: sqlite3_column_text(stmt, 1)),
                    zoneName: String(cString: sqlite3_column_text(stmt, 2)),
                    operation: String(cString: sqlite3_column_text(stmt, 3))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return records
    }

    func countDirtyRecords() -> (total: Int, byType: [String: Int]) {
        let sql = "SELECT record_type, COUNT(*) FROM sync_dirty_records GROUP BY record_type"
        var stmt: OpaquePointer?
        var byType: [String: Int] = [:]
        var total = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let type = String(cString: sqlite3_column_text(stmt, 0))
                let count = Int(sqlite3_column_int(stmt, 1))
                byType[type] = count
                total += count
            }
        }
        sqlite3_finalize(stmt)
        return (total, byType)
    }

    /// Mark every record belonging to a session — Session itself, all its
    /// Messages, CompactMarkers, and SessionFiles — as dirty so they will
    /// be re-pushed to iCloud on the next send pass. Idempotent. Used by
    /// the user-facing Force Sync action (long-press a message in chat).
    /// Returns total dirty rows added.
    @discardableResult
    func forceSyncSession(_ sessionId: String) -> Int {
        guard !syncZoneName.isEmpty else { return 0 }
        var count = 0
        markDirty(recordType: "Session", recordId: sessionId)
        count += 1
        // Messages
        var mStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id FROM messages WHERE session_id = ?", -1, &mStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(mStmt, 1, (sessionId as NSString).utf8String, -1, nil)
            while sqlite3_step(mStmt) == SQLITE_ROW {
                markDirty(recordType: "Message", recordId: String(cString: sqlite3_column_text(mStmt, 0)))
                count += 1
            }
        }
        sqlite3_finalize(mStmt)
        // CompactMarkers
        var cStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id FROM compact_markers WHERE session_id = ?", -1, &cStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(cStmt, 1, (sessionId as NSString).utf8String, -1, nil)
            while sqlite3_step(cStmt) == SQLITE_ROW {
                markDirty(recordType: "CompactMarker", recordId: String(cString: sqlite3_column_text(cStmt, 0)))
                count += 1
            }
        }
        sqlite3_finalize(cStmt)
        // SessionFiles via the existing scan
        let fileCount = scanAndMarkSessionFiles(sessionId: sessionId, priority: 0)
        count += fileCount
        iCloudLogger.info("[iCloud] forceSyncSession(\(sessionId.prefix(8))) marked \(count) records dirty")
        return count
    }

    /// Outcome of a Force Pull attempt.
    enum ForcePullOutcome {
        /// Cloud returned ≥1 record; local was wiped and replaced. localDeleted
        /// counts messages+markers that existed locally before the swap.
        case applied(pulledFromCloud: Int, localDeleted: Int)
        /// Cloud returned 0 records or threw — local rows are preserved
        /// untouched. The chat view should surface a warning to the user.
        case cloudEmpty
        /// Underlying transport threw an error. Local rows preserved.
        case failed(String)
    }

    /// Reconcile a session against cloud truth.
    ///
    /// New (safe) flow:
    ///   1. Pull from cloud first — does NOT touch local rows yet.
    ///   2. If cloud returned 0 records → bail out, keep local intact,
    ///      surface .cloudEmpty so the UI can warn the user that there
    ///      is no remote copy to fall back to (avoids the "Force Pull
    ///      silently wipes everything" footgun).
    ///   3. If cloud returned ≥1 record → only NOW wipe local rows +
    ///      clear dirty/pushed bookkeeping, then re-emit the cached cloud
    ///      portables through the inbound path so they land in SQLite.
    ///
    /// This means the pull network round-trip happens with local
    /// untouched, and the swap is committed atomically only after we
    /// know cloud has something to give us.
    func forcePullSession(sessionId: String) async -> ForcePullOutcome {
        // PER-SESSION: re-pulls one known session's messages. It cannot add or
        // remove a sidebar row — the session already exists locally, which is
        // what makes a force-pull meaningful.
        invalidateSessionListCache(sessionId: sessionId)
        iCloudLogger.warning("[ForcePull] sid=\(sessionId.prefix(8)) START — pulling cloud first, local untouched")

        // 1. Cloud first (no local mutation yet). Returns the portables
        //    so we can replay them after the swap. If the transport
        //    can't be reached we treat it as a hard failure rather than
        //    "empty cloud" so the caller can distinguish.
        let pullResult: ([PortableRecord], Error?)
        if #available(iOS 17.0, *) {
            pullResult = await SyncCore.shared.fetchSessionPortables(sessionId: sessionId)
        } else {
            iCloudLogger.warning("[ForcePull] sid=\(sessionId.prefix(8)) iOS < 17 — pull unavailable")
            return .failed(AppLocalized("Force Pull requires iOS 17 or newer."))
        }
        let portables = pullResult.0
        if let err = pullResult.1 {
            iCloudLogger.warning("[ForcePull] sid=\(sessionId.prefix(8)) transport err: \(err.localizedDescription) — keeping local intact")
            return .failed(err.localizedDescription)
        }
        if portables.isEmpty {
            iCloudLogger.warning("[ForcePull] sid=\(sessionId.prefix(8)) cloud returned 0 records — keeping local intact")
            return .cloudEmpty
        }
        iCloudLogger.warning("[ForcePull] sid=\(sessionId.prefix(8)) cloud returned \(portables.count) records — committing swap")

        // 2. Now safe to swap. Collect ids for bookkeeping cleanup.
        var messageIds: [String] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id FROM messages WHERE session_id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                messageIds.append(String(cString: sqlite3_column_text(stmt, 0)))
            }
        }
        sqlite3_finalize(stmt)
        var markerIds: [String] = []
        var mStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id FROM compact_markers WHERE session_id = ?", -1, &mStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(mStmt, 1, (sessionId as NSString).utf8String, -1, nil)
            while sqlite3_step(mStmt) == SQLITE_ROW {
                markerIds.append(String(cString: sqlite3_column_text(mStmt, 0)))
            }
        }
        sqlite3_finalize(mStmt)

        // 3. Hard-delete local rows (cloud truth will be replayed below).
        var locallyDeleted = 0
        var dStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM messages WHERE session_id = ?", -1, &dStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(dStmt, 1, (sessionId as NSString).utf8String, -1, nil)
            sqlite3_step(dStmt)
            locallyDeleted += Int(sqlite3_changes(db))
        }
        sqlite3_finalize(dStmt)
        var dmStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM compact_markers WHERE session_id = ?", -1, &dmStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(dmStmt, 1, (sessionId as NSString).utf8String, -1, nil)
            sqlite3_step(dmStmt)
            locallyDeleted += Int(sqlite3_changes(db))
        }
        sqlite3_finalize(dmStmt)

        // 4. Clear sync_dirty_records and sync_pushed_records so the
        // replay treats incoming portables as fresh, and so we don't
        // immediately re-push stale rows.
        for id in messageIds {
            clearDirtyRecord(recordName: "Message:\(id)")
        }
        for id in markerIds {
            clearDirtyRecord(recordName: "CompactMarker:\(id)")
        }
        clearDirtyRecord(recordName: "Session:\(sessionId)")

        var pushedClearStmt: OpaquePointer?
        let clearPushedSQL = "DELETE FROM sync_pushed_records WHERE record_name = ?"
        if sqlite3_prepare_v2(db, clearPushedSQL, -1, &pushedClearStmt, nil) == SQLITE_OK {
            for id in messageIds {
                sqlite3_bind_text(pushedClearStmt, 1, ("Message:\(id)" as NSString).utf8String, -1, nil)
                sqlite3_step(pushedClearStmt)
                sqlite3_reset(pushedClearStmt)
            }
            for id in markerIds {
                sqlite3_bind_text(pushedClearStmt, 1, ("CompactMarker:\(id)" as NSString).utf8String, -1, nil)
                sqlite3_step(pushedClearStmt)
                sqlite3_reset(pushedClearStmt)
            }
            sqlite3_bind_text(pushedClearStmt, 1, ("Session:\(sessionId)" as NSString).utf8String, -1, nil)
            sqlite3_step(pushedClearStmt)
        }
        sqlite3_finalize(pushedClearStmt)

        iCloudLogger.warning("[ForcePull] sid=\(sessionId.prefix(8)) local cleared: messages=\(messageIds.count) markers=\(markerIds.count) deletedRows=\(locallyDeleted)")

        // 5. Replay cloud portables through SyncCore (same path normal
        // inbound traffic uses, so hydrators land them in SQLite).
        await SyncCore.shared.applyPortables(portables, transportName: "ForcePull")
        iCloudLogger.warning("[ForcePull] sid=\(sessionId.prefix(8)) DONE pulled=\(portables.count) localDeleted=\(locallyDeleted)")
        return .applied(pulledFromCloud: portables.count, localDeleted: locallyDeleted)
    }

    /// Clear a dirty row after the transport acknowledged it.
    ///
    /// [T-sync-message-resurrection] `ifOperation` is the operation that was
    /// actually sent. `sync_dirty_records` is keyed by (type, id) and
    /// `markDirty` is INSERT OR REPLACE, so a delete marked while an upsert
    /// of the same record was in flight *replaces* that row; clearing
    /// unconditionally on the upsert's success then destroyed the delete —
    /// the tombstone was never pushed and the remote copy lived on. With
    /// the guard, a row whose operation no longer matches what was sent is
    /// left for the next batch.
    func clearDirtyRecord(recordName: String, ifOperation: String? = nil) {
        // recordName format is "Type:id"
        let parts = recordName.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return }
        let recordType = String(parts[0])
        let recordId = String(parts[1])
        let sql = ifOperation == nil
            ? "DELETE FROM sync_dirty_records WHERE record_type = ? AND record_id = ?"
            : "DELETE FROM sync_dirty_records WHERE record_type = ? AND record_id = ? AND operation = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (recordType as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (recordId as NSString).utf8String, -1, nil)
            if let op = ifOperation {
                sqlite3_bind_text(stmt, 3, (op as NSString).utf8String, -1, nil)
            }
            sqlite3_step(stmt)
            if let op = ifOperation, sqlite3_changes(db) == 0 {
                iCloudLogger.info("[iCloudTrace] clearDirty KEPT \(recordType):\(recordId.prefix(8)) — operation changed while in flight (sent=\(op))")
            }
        }
        sqlite3_finalize(stmt)
    }

    func markRecordsPushed(_ recordNames: [String]) {
        guard !recordNames.isEmpty else { return }
        exec("BEGIN TRANSACTION")
        let sql = "INSERT OR IGNORE INTO sync_pushed_records (record_name) VALUES (?)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for name in recordNames {
                sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
        }
        sqlite3_finalize(stmt)
        exec("COMMIT")
    }

    @discardableResult
    func clearAllPushedRecords() -> Int {
        let before = countPushedRecords()
        exec("DELETE FROM sync_pushed_records")
        iCloudLogger.info("[iCloud] clearAllPushedRecords: removed \(before) rows")
        return before
    }

    func countPushedRecords() -> Int {
        var count = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sync_pushed_records", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return count
    }

    // Directories to skip when scanning session files for iCloud sync.
    // These contain build artifacts, caches, and VCS internals that should not be synced.
    private static let syncSkipDirNames: Set<String> = [
        "__pycache__", ".git", ".svn", ".hg",
        "node_modules", ".tox", ".venv", "venv",
        ".build", ".eggs",
        ".mypy_cache", ".pytest_cache", ".ruff_cache",
        "__pypackages__", ".gradle", ".idea",
    ]

    /// Scan workspace/offloads/attachments dirs for a session and markDirty for each file.
    /// Returns number of files marked.
    @discardableResult
    func scanAndMarkSessionFiles(sessionId: String, priority: Int = 0) -> Int {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let sessionDir = library.appendingPathComponent("MinisChat/minis/\(sessionId)")
        guard fm.fileExists(atPath: sessionDir.path) else { return 0 }
        // Standardize to resolve /private/var vs /var symlink differences
        let sessionDirStd = sessionDir.standardizedFileURL.path

        let subdirs = ["workspace", "offloads", "attachments", "browser"]
        var count = 0
        var subdirCounts: [String: Int] = [:]
        var totalBytes: Int = 0
        var skippedOversize = 0
        var skippedDisabled = 0
        var skippedJunkDir = 0
        for subdir in subdirs {
            let dirURL = sessionDir.appendingPathComponent(subdir)
            guard let enumerator = fm.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            var subdirCount = 0
            for case let fileURL as URL in enumerator {
                // Skip entire junk directories (build artifacts, caches, VCS internals)
                let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if isDir {
                    if Self.syncSkipDirNames.contains(fileURL.lastPathComponent) {
                        enumerator.skipDescendants()
                        skippedJunkDir += 1
                    }
                    continue
                }
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                // Skip files exceeding max sync size (single source of truth: UploadPolicy)
                let maxSize = UploadPolicy.maxFileSizeBytes
                if fileSize > maxSize { skippedOversize += 1; continue }
                // recordId format: "sessionId:subdir/relativePath"
                let fileStd = fileURL.standardizedFileURL.path
                let prefix = sessionDirStd + "/"
                let relativePath = fileStd.hasPrefix(prefix) ? String(fileStd.dropFirst(prefix.count)) : fileURL.lastPathComponent
                markDirty(recordType: "SessionFile", recordId: "\(sessionId):\(relativePath)", priority: priority)
                count += 1
                subdirCount += 1
                totalBytes += fileSize
            }
            if subdirCount > 0 { subdirCounts[subdir] = subdirCount }
        }
        if count > 0 || skippedOversize > 0 || skippedJunkDir > 0 {
            let breakdown = subdirCounts.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            iCloudLogger.info("[iCloud] ⏱ scanAndMarkSessionFiles[\(sessionId.prefix(8))]: \(count) files (\(totalBytes / 1024)KB) cap=\(UploadPolicy.maxFileSizeBytes / 1024)KB skippedOversize=\(skippedOversize) skippedJunkDirs=\(skippedJunkDir) [\(breakdown)]")
        }
        _ = skippedDisabled
        return count
    }
}

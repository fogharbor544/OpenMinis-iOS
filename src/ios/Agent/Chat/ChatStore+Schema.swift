//
//  ChatStore+Schema.swift
//  Minis - chat persistence (Agent/Chat)
//
//  ChatStore, database setup: opening the SQLite file, the schema
//  (createTables), deferred migrations and one-off backfills / cleanups, and
//  the exec / column helpers they use.
//
//  Map of the ChatStore files: ChatStore.swift.
//

import Foundation
import SQLite3
import SwiftAnthropic
import UIKit
import os.log

private let logger = AppLogger(category: "ChatStore")
private let iCloudLogger = AppLogger(category: "iCloud")

extension ChatStore {
    // MARK: - Database Setup

    func openDatabase() {
        let result = sqlite3_open(dbURL.path, &db)
        if result != SQLITE_OK {
            logger.error("Failed to open database at \(self.dbURL.path): \(result)")
        }
        // Enable WAL mode for better concurrent read performance
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA foreign_keys=ON")
    }

    func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS sessions (
                id          TEXT PRIMARY KEY,
                title       TEXT,
                model_id    TEXT NOT NULL,
                created_at  REAL NOT NULL,
                updated_at  REAL NOT NULL,
                category TEXT,
                model_binding TEXT,
                source TEXT,
                memory_enabled INTEGER NOT NULL DEFAULT 1,
                last_synced_at REAL,
                remote_origin_device_id TEXT,
                pinned_at REAL,
                folder_id TEXT,
                parent_session_id TEXT,
                parent_tool_use_id TEXT,
                preview_text TEXT,
                preview_sort_order INTEGER,
                remote_tombstoned_at REAL
            )
        """)

        exec("""
            CREATE TABLE IF NOT EXISTS messages (
                id          TEXT PRIMARY KEY,
                session_id  TEXT NOT NULL REFERENCES sessions(id),
                role        TEXT NOT NULL,
                parts_json  TEXT NOT NULL,
                created_at  REAL NOT NULL,
                token_usage TEXT,
                sort_order  INTEGER NOT NULL,
                reasoning_content TEXT,
                reasoning_echo TEXT,
                stream_interrupt_count INTEGER NOT NULL DEFAULT 0,
                updated_at REAL,
                error_info TEXT,
                part_flags INTEGER NOT NULL DEFAULT 0,
                model_id TEXT,
                model_display_name TEXT,
                provider_type TEXT,
                provider_instance_id TEXT
            )
        """)

        exec("CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, sort_order)")
        // [T-ios-listsessions-part-flags] Supports listSessions' per-role
        // preview subqueries: SEARCH … (session_id=? AND role=?) ORDER BY
        // sort_order DESC LIMIT 1. Measured ~30ms vs ~58ms on the plain
        // idx_messages_session, on the 100k-message DB.
        exec("CREATE INDEX IF NOT EXISTS idx_msg_sess_role_sort ON messages(session_id, role, sort_order DESC)")

        // [T-ios-moveto-perf] The session list is always ordered by
        // `updated_at DESC`, and there was no index on it — so every rebuild
        // sorted the whole table. Harmless at a few dozen sessions, a real cost
        // at the 1772-session scale the preview subqueries were tuned against,
        // and it is what makes the `LIMIT` in `listRecentSessions` actually
        // cheap: with the index SQLite walks the first N rows in order instead
        // of sorting everything and discarding the tail.
        //
        // `CREATE INDEX IF NOT EXISTS` runs on every open and is idempotent, so
        // this needs no schema-version bump and no migration step.
        exec("CREATE INDEX IF NOT EXISTS idx_sessions_updated_at ON sessions(updated_at DESC)")

        // Idempotent column migrations — guarded via PRAGMA table_info so
        // re-runs on already-migrated DBs don't emit duplicate-column errors.
        // [T-responses-echo-persist] Native reasoning items (OpenAI Responses
        // `reasoning` heads: id + summary + the upstream that minted them),
        // JSON. Nullable with no DEFAULT so a row written before this column
        // existed stays distinguishable from one that genuinely has no echo.
        // Folder membership. NULL = ungrouped. Intentionally NOT a declared FK:
        // a folder_id pointing at a folder that does not exist locally is a
        // legitimate transient state (the session's SessionV2 record can arrive
        // before its FolderV2 record, and a folder deleted on another device
        // leaves references behind). Such orphans render as ungrouped rather
        // than failing a constraint — see foldersById callers in ContentView.
        // [T-p1-delegate-task] Child-session linkage. Nullable, no DEFAULT,
        // no FK (orphan-tolerant like folder_id).
        // [T-ios-listsessions-perf] Denormalised sidebar preview, computed when
        // a message lands rather than re-derived for every session on every
        // refresh. `preview_sort_order` is the sort_order of the message the
        // text came from, so the assistant-wins-unless-the-user-is-newer rule
        // can be applied incrementally without re-reading both candidate rows.
        //
        // Nullable with NO DEFAULT, deliberately: NULL is the signal "this row
        // predates the column", which listSessions uses to fall back to the old
        // extraction once and write the result back. A DEFAULT '' would erase
        // the difference between "not computed yet" and "genuinely empty".
        //
        // These columns are NOT part of the sessions CREATE TABLE above (that
        // DDL carries only the five original columns; every later column on
        // this table arrives through addColumnIfMissing), so there is no
        // both-places requirement here — unlike `folders.pinned_at` below,
        // which IS in its DDL and therefore needs both.
        //
        // Derived state: deliberately absent from the iCloud wire format and
        // the backup export. Each device computes its own, so an older peer
        // that knows nothing about these columns is unaffected, and a downgrade
        // simply ignores them.
        // Folder pinning (mirrors sessions.pinned_at). Also present in the
        // CREATE TABLE DDL above — per the add-column wipe trap, a new column
        // must exist in BOTH the initial DDL and the idempotent migration.
        // One-sentence group description (≤100 chars): written at creation
        // (typed or AI-suggested), edited in the rename dialog, and fed to
        // the auto-grouping prompt as context. Not rendered in the list.
        // [T-error-persist-ios] Device-local error string shown on a failed
        // assistant turn (provider/network/empty-response/context-full/…). Persisted
        // so the indicator survives session reload / app restart. NULL = no error.
        // Not synced via iCloud (errors are device-local; absent from the CKRecord).
        // [T-ios-listsessions-part-flags] Device-local bitmask of which
        // ContentPart types a row's parts_json contains — bit0=hasText,
        // bit1=hasToolUse. Lets listSessions() replace 4 un-indexable
        // `parts_json LIKE '%…%'` subqueries per session with cheap integer
        // masks (523ms → single-digit ms cold on a 100k-message DB). Derived
        // purely from parts_json, so it is NOT synced via iCloud (like
        // error_info): inbound merge / backfill recompute it locally on write.
        // Backfilled once for pre-existing rows below.
        // v2 sync: soft-delete tombstone for sessions deleted on a peer
        // device but kept locally. Non-nil = tombstoned at that timestamp.
        // See SyncV2 §3.3.
        // v2 sync: priority + creation order on dirty rows so migration's
        // 28k+ row backlog never starves freshly-typed user messages.
        // priority: 0 = user-driven (default), 1 = migration backlog
        // (push only after priority=0 drains in each batch).

        // [T-token-attribution-snapshot] Which model actually produced each
        // message, captured at write time.
        //
        // The Usage page used to derive this by joining `sessions.model_id` —
        // one mutable column per session, rewritten on every model switch
        // (including silent failover) with no history. The join has no time
        // dimension, so a session's entire past was re-attributed to whatever
        // model it currently pointed at: a billion deepseek tokens became grok
        // tokens on switch, and moved back on switching back.
        //
        // The display name and provider type are stored alongside the id, not
        // just the id, so a provider the user later deletes still renders as
        // the model they actually used instead of collapsing into "Other" —
        // for a custom model the live config is the only other source, and
        // deleting the instance removes it.
        //
        // All four are nullable BY DESIGN: rows written before this point read
        // NULL, which is precisely how the UI separates "measured" from
        // "estimated from the session". A NOT NULL DEFAULT would erase that.

        // Compact markers table — tracks context compaction boundaries per session
        exec("""
            CREATE TABLE IF NOT EXISTS compact_markers (
                id                      TEXT PRIMARY KEY,
                session_id              TEXT NOT NULL REFERENCES sessions(id),
                summary                 TEXT NOT NULL,
                first_kept_sort_order   INTEGER NOT NULL,
                compacted_count         INTEGER NOT NULL,
                created_at              REAL NOT NULL,
                ui_boundary_sort_order  INTEGER,
                boundary_message_id TEXT,
                first_kept_message_id TEXT,
                last_compacted_message_id TEXT,
                version INTEGER NOT NULL DEFAULT 2
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_compact_markers_session ON compact_markers(session_id, created_at)")
        // Idempotent column migrations for compact_markers.
        // Phase A: id-first boundary model. New markers MUST fill these columns.
        // Phase v2: simplified marker model. version=2 markers anchor on
        // last_compacted_message_id ONLY (a real, persisted, UI-visible message
        // id). All other id/sortOrder fields are unused for v2 markers. Older
        // markers default to version=1 so legacy resolution code keeps running.
        exec("CREATE INDEX IF NOT EXISTS idx_compact_markers_first_kept ON compact_markers(session_id, first_kept_message_id)")

        // [T-ios-listsessions-part-flags] One-shot backfill of part_flags for
        // rows written before the column existed (all default to 0). Computed
        // in pure SQL with the SAME LIKE patterns the old listSessions used, so
        // backfilled flags reproduce the previous preview selection exactly.
        // Guarded by a UserDefaults flag (mirrors zombieCleanupKey) so it runs
        // once. Scoped to rows still at the default (part_flags = 0 AND the JSON
        // actually contains a text/toolUse part) so re-runs after a partial
        // failure stay cheap and correct.
        // [T-ios27-scene-create-watchdog] The backfill itself no longer runs
        // here. It is an UPDATE with two unindexable LIKE scans over the whole
        // messages table — on a 100k-message database that is seconds of work
        // INSIDE the dispatch_once every other thread is waiting on. Moved to
        // runDeferredMigrations(), which the launch path calls off the init.
        // The ADD COLUMN above stays: the column must exist before any query
        // references it, and ALTER TABLE ADD COLUMN is O(1) metadata in SQLite.


        // iCloud sync tables
        exec("""
            CREATE TABLE IF NOT EXISTS sync_dirty_records (
                record_type TEXT NOT NULL,
                record_id   TEXT NOT NULL,
                zone_name   TEXT NOT NULL,
                operation   TEXT NOT NULL DEFAULT 'upsert',
                priority INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL DEFAULT 0,
                PRIMARY KEY (record_type, record_id)
            )
        """)
        // Distinct recordIDs that have ever been confirmed saved to
        // iCloud (via CKSyncEngine SentRecordZoneChanges). Used by the
        // migration progress UI to show a real "unique records pushed"
        // count rather than the historical save-event counter, which
        // double-counts every relaunch's re-mark-dirty + re-save cycle.
        // Insert is INSERT OR IGNORE so duplicate saves are silent.
        exec("""
            CREATE TABLE IF NOT EXISTS sync_pushed_records (
                record_name TEXT PRIMARY KEY
            )
        """)
        // [T-icloud-deleted-session-resurrection] Recent-delete tombstones.
        // When a session is deleted locally its rows are hard-deleted, but the
        // cloud delete (CKSyncEngine tombstone) is pushed asynchronously. In the
        // window before it lands, fetchRecentV2's active query can pull the
        // still-present old SessionV2/MessageV2/SessionFileV2 records back and
        // mergeRemote* re-INSERTs them — the session "resurrects" (with a ☁️
        // remote-origin marker). This table records every locally-deleted
        // session id + when, so the inbound merge can refuse to re-insert a
        // record that isn't newer than the deletion. Entries are pruned only by
        // the 30-day TTL below — session ids are UUIDs (never reused), so a
        // lingering tombstone never wrongly blocks a future session, and the
        // table stays tiny.
        exec("""
            CREATE TABLE IF NOT EXISTS deleted_session_tombstones (
                session_id TEXT PRIMARY KEY,
                deleted_at REAL NOT NULL
            )
        """)
        // [T-icloud-deleted-session-resurrection] Bound the table size: the
        // cloud delete normally lands within seconds, after which the server
        // record can no longer be fetched back, so the tombstone has done its
        // job. Session ids are UUIDs (never reused), so a stale tombstone can't
        // wrongly block a legitimate future session — but prune entries older
        // than 30 days on launch so the table can't grow without bound.
        exec("DELETE FROM deleted_session_tombstones WHERE deleted_at < \(Date().timeIntervalSince1970 - 30 * 24 * 60 * 60)")
        // [T-icloud-record-delete-resurrection] Same resurrection guard,
        // generalized to other per-record types whose deletes propagate as
        // op=delete but whose inbound merges would otherwise happily re-insert
        // a stale live record fetched by fetchRecentV2 before the cloud delete
        // lands (CKQuery never sees deletions). Currently written for
        // Skill / EnvVarItem / CompactMarker via the markDirty(op=delete)
        // chokepoint. Same 30-day TTL prune as the session table.
        exec("""
            CREATE TABLE IF NOT EXISTS deleted_record_tombstones (
                record_type TEXT NOT NULL,
                record_id   TEXT NOT NULL,
                deleted_at  REAL NOT NULL,
                PRIMARY KEY (record_type, record_id)
            )
        """)
        exec("DELETE FROM deleted_record_tombstones WHERE deleted_at < \(Date().timeIntervalSince1970 - 30 * 24 * 60 * 60)")
        // Session folders (home-list grouping). `id` is a locally generated
        // UUID — uniqueness needs no cross-device coordination, which is why
        // it beats keying on the name when devices create folders offline.
        // `name` deliberately has NO UNIQUE constraint: two devices may each
        // create a "Work" folder and both are kept (see ChatFolder's doc
        // comment for the full rationale).
        exec("""
            CREATE TABLE IF NOT EXISTS folders (
                id          TEXT PRIMARY KEY,
                name        TEXT NOT NULL,
                icon        TEXT,
                color       TEXT,
                origin      TEXT NOT NULL DEFAULT 'manual',
                sort_index  INTEGER NOT NULL DEFAULT 0,
                pinned_at   REAL,
                description TEXT,
                created_at  REAL NOT NULL,
                updated_at  REAL NOT NULL
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS sync_devices (
                device_id   TEXT PRIMARY KEY,
                device_name TEXT NOT NULL,
                zone_name   TEXT NOT NULL,
                last_seen   REAL NOT NULL,
                os_version  TEXT NOT NULL DEFAULT '',
                upload_types TEXT NOT NULL DEFAULT ''
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS remote_sessions (
                id          TEXT NOT NULL,
                device_id   TEXT NOT NULL,
                title       TEXT,
                category    TEXT,
                model_id    TEXT NOT NULL DEFAULT 'unknown',
                created_at  REAL NOT NULL,
                updated_at  REAL NOT NULL,
                model_binding TEXT,
                PRIMARY KEY (id, device_id)
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS remote_messages (
                id          TEXT NOT NULL,
                device_id   TEXT NOT NULL,
                session_id  TEXT NOT NULL,
                role        TEXT NOT NULL,
                parts_json  TEXT NOT NULL,
                created_at  REAL NOT NULL,
                token_usage TEXT,
                sort_order  INTEGER NOT NULL DEFAULT 0,
                reasoning_content TEXT,
                reasoning_echo TEXT,
                stream_interrupt_count INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (id, device_id)
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_remote_messages_session ON remote_messages(session_id, device_id, sort_order)")
        exec("""
            CREATE TABLE IF NOT EXISTS remote_media (
                id              TEXT NOT NULL,
                device_id       TEXT NOT NULL,
                session_id      TEXT NOT NULL,
                relative_path   TEXT NOT NULL,
                mime_type       TEXT,
                original_file_name TEXT,
                local_cache_path TEXT,
                PRIMARY KEY (id, device_id)
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS remote_skills (
                id          TEXT NOT NULL,
                device_id   TEXT NOT NULL,
                name        TEXT NOT NULL DEFAULT '',
                description TEXT NOT NULL DEFAULT '',
                version     TEXT NOT NULL DEFAULT '1.0.0',
                import_source TEXT NOT NULL DEFAULT 'file',
                is_enabled  INTEGER NOT NULL DEFAULT 1,
                installed_at REAL NOT NULL,
                updated_at  REAL NOT NULL,
                body_text   TEXT NOT NULL DEFAULT '',
                PRIMARY KEY (id, device_id)
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS remote_memories (
                id          TEXT NOT NULL,
                device_id   TEXT NOT NULL,
                file_name   TEXT NOT NULL DEFAULT '',
                content     TEXT NOT NULL DEFAULT '',
                updated_at  REAL NOT NULL,
                PRIMARY KEY (id, device_id)
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS remote_provider_configs (
                device_id   TEXT NOT NULL PRIMARY KEY,
                config_json TEXT NOT NULL DEFAULT '{}',
                updated_at  REAL NOT NULL
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS remote_env_vars (
                device_id       TEXT NOT NULL PRIMARY KEY,
                env_vars_json   TEXT NOT NULL DEFAULT '[]',
                updated_at      REAL NOT NULL
            )
        """)
        // WebApp-style home-screen shortcuts. One row per HTML the user has
        // "Added to Home Screen". Path resolution and host-URL derivation
        // happen at launch via WebAppPathResolver — stored values are
        // sandbox-relative so the row survives container UUID rotation.
        exec("""
            CREATE TABLE IF NOT EXISTS webapp_shortcuts (
                id                 TEXT PRIMARY KEY,
                html_path          TEXT NOT NULL,
                path_scope         TEXT NOT NULL,
                scope_context      TEXT,
                title              TEXT NOT NULL,
                icon_ref           TEXT NOT NULL,
                icon_cache_path    TEXT,
                created_at         REAL NOT NULL,
                source_session_id  TEXT
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_webapp_shortcuts_created ON webapp_shortcuts(created_at DESC)")

        purgeUnusableSessionRows()
    }

    /// [T-ios-listsessions-cstring-trap] Delete session rows whose primary key
    /// is NULL or empty.
    ///
    /// SQLite does NOT imply NOT NULL for a non-INTEGER `TEXT PRIMARY KEY`, so
    /// such a row is legal at the storage layer but unusable at every layer
    /// above it: it cannot be opened, deleted, or synced by id, and its
    /// `sqlite3_column_text` returns NULL — which trapped `String(cString:)` and
    /// SIGABRT'd the app inside `listSessions()` on every launch (crash loop
    /// 09:13:09 → 09:14:15). `listSessions` now skips these defensively; this
    /// clears them at startup so they stop being re-encountered.
    ///
    /// Child rows are removed first: `messages.session_id` has a FK to
    /// `sessions(id)` and `PRAGMA foreign_keys=ON` is set, so deleting the
    /// parent alone would fail. Orphaned children (session_id NULL / pointing at
    /// a NULL-id parent) can't be reattached to anything, so they go too.
    private func purgeUnusableSessionRows() {
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sessions WHERE id IS NULL OR id = ''", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            count = Int(sqlite3_column_int64(stmt, 0))
        }
        sqlite3_finalize(stmt)
        guard count > 0 else { return }

        logger.error("[ChatStore] purging \(count) unusable session row(s) with NULL/empty id (T-ios-listsessions-cstring-trap)")
        exec("DELETE FROM messages WHERE session_id IS NULL OR session_id = ''")
        exec("DELETE FROM sessions WHERE id IS NULL OR id = ''")
    }

    func exec(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            logger.error("SQL error: \(msg)")
            sqlite3_free(errMsg)
        }
    }


}

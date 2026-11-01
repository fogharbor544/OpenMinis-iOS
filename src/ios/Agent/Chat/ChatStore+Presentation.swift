import Foundation
import SQLite3

extension ChatStore {
    func messagePresentation(_ id: String) -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT json FROM message_presentation WHERE message_id = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    @discardableResult
    func setMessagePresentation(_ id: String, json: String?) -> Bool {
        guard let json else { return true }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "INSERT OR REPLACE INTO message_presentation(message_id, json) SELECT id, ? FROM messages WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, (json as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
        return sqlite3_step(stmt) == SQLITE_DONE
    }
}

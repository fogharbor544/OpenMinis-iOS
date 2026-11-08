import XCTest
@testable import Minis

/// The backup chat reader must tell "this device really has no chats" apart
/// from "the query or a row failed", because an incomplete package otherwise
/// restores as a silent data loss. These cases drive the shipping ChatStore,
/// so they live with the app test target rather than the format-only CI
/// harness, which compiles BackupFormat.swift alone.
final class BackupChatReadTests: XCTestCase {

    @MainActor
    func testChatBackupReadsEmptyHistoryButRejectsIncompleteHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(baseURL: root)
        let empty = try await store.sessionIdsForBackup()
        XCTAssertTrue(empty.isEmpty)
        await store.exec("INSERT INTO sessions(id,model_id,created_at,updated_at,remote_tombstoned_at) VALUES('s','m',1,1,2)")
        let sessions = try await store.sessionIdsForBackup()
        XCTAssertEqual(sessions, ["s"])
        let noMessages = try await store.loadMessagesForBackup(sessionId: "s")
        XCTAssertTrue(noMessages.isEmpty)

        await store.exec("INSERT INTO messages(id,session_id,role,parts_json,created_at,sort_order) VALUES('ok','s','user','[]',1,0)")
        let messages = try await store.loadMessagesForBackup(sessionId: "s")
        XCTAssertEqual(messages.map(\.id), ["ok"])
        await store.exec("INSERT INTO messages(id,session_id,role,parts_json,created_at,sort_order) VALUES('bad','s','user','{',2,1)")
        do {
            _ = try await store.loadMessagesForBackup(sessionId: "s")
            XCTFail("A malformed message must not be exported as a partial conversation")
        } catch BackupError.stagingFailed(_) {}

        await store.exec("ALTER TABLE sessions RENAME TO unavailable_sessions")
        do {
            _ = try await store.sessionIdsForBackup()
            XCTFail("A failed SQLite query must not be exported as an empty chat list")
        } catch BackupError.stagingFailed(_) {}
        await store.closeDatabase()
    }
}

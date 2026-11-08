import XCTest
@testable import Minis

/// The backup chat reader must tell "this device really has no chats" apart
/// from a failed query, and report bad rows without losing readable history.
/// These cases drive the shipping ChatStore,
/// so they live with the app test target rather than the format-only CI
/// harness, which compiles BackupFormat.swift alone.
final class BackupChatReadTests: XCTestCase {

    @MainActor
    func testChatBackupKeepsReadableMessagesAndReportsUnreadableRows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(baseURL: root)
        let empty = try await store.sessionIdsForBackup()
        XCTAssertTrue(empty.isEmpty)
        await store.exec("INSERT INTO sessions(id,model_id,created_at,updated_at,remote_tombstoned_at) VALUES('s','m',1,1,2)")
        let sessions = try await store.sessionIdsForBackup()
        XCTAssertEqual(sessions, ["s"])
        let noMessages = try await store.loadMessagesForBackup(sessionId: "s")
        XCTAssertTrue(noMessages.messages.isEmpty)
        XCTAssertEqual(noMessages.unreadable, 0)

        await store.exec("""
            INSERT INTO messages(id,session_id,role,parts_json,created_at,sort_order) VALUES
            ('before','s','user','[{"type":"text","value":"First"}]',1,0),
            ('malformed','s','user','{',2,1),
            ('unknown-part','s','assistant','[{"type":"future","value":{}}]',3,2),
            ('after','s','assistant','[{"type":"text","value":"Last"}]',4,3)
            """)
        let messages = try await store.loadMessagesForBackup(sessionId: "s")
        XCTAssertEqual(messages.messages.map(\.id), ["before", "after"])
        XCTAssertEqual(messages.messages.last?.parts, [.text("Last")])
        XCTAssertEqual(messages.unreadable, 2)

        await store.exec("ALTER TABLE messages RENAME TO unavailable_messages")
        do {
            _ = try await store.loadMessagesForBackup(sessionId: "s")
            XCTFail("A failed SQLite query must not be exported as an empty chat")
        } catch BackupError.chatSnapshotReadFailed(_) {}

        await store.exec("ALTER TABLE sessions RENAME TO unavailable_sessions")
        do {
            _ = try await store.sessionIdsForBackup()
            XCTFail("A failed SQLite query must not be exported as an empty chat list")
        } catch BackupError.chatSnapshotReadFailed(_) {}
        await store.closeDatabase()
    }
}

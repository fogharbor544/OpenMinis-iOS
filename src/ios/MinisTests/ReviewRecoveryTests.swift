import XCTest
@testable import Minis

/// Fault injection for the two 2026-11-11 reviews. All stores and files are isolated.
@MainActor
final class ReviewRecoveryTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<600 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Asynchronous operation did not settle within three seconds")
    }

    func testMessageBatchRollsBackAndCanBeRetried() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(baseURL: root)
        await store.exec("INSERT INTO sessions(id,model_id,created_at,updated_at) VALUES('s','m',1,1)")
        await store.exec("CREATE TRIGGER reject_middle BEFORE INSERT ON messages WHEN NEW.id='middle' BEGIN SELECT RAISE(ABORT,'injected write failure'); END")
        let rows = ["first", "middle", "last"].map {
            RawMessage(id: $0, sessionId: "s", role: .user, parts: [.text($0)], createdAt: Date())
        }
        let failed = await store.appendMessages(rows)
        XCTAssertFalse(failed)
        let afterFailure = try await store.loadMessagesForBackup(sessionId: "s")
        XCTAssertTrue(afterFailure.messages.isEmpty, "A batch must not retain its first row after the second row fails")
        await store.exec("DROP TRIGGER reject_middle")
        let retried = await store.appendMessages(rows)
        XCTAssertTrue(retried)
        let afterRetry = try await store.loadMessagesForBackup(sessionId: "s")
        XCTAssertEqual(afterRetry.messages.map(\.id), ["first", "middle", "last"])
        await store.exec("PRAGMA query_only=ON")
        let readOnly = await store.appendMessage(.init(id: "blocked", sessionId: "s", role: .user,
                                                     parts: [.text("blocked")], createdAt: Date()))
        XCTAssertFalse(readOnly)
        await store.closeDatabase()
    }

    func testPermissionRequestsQueueAndCancellationDoesNotGrantAccess() async throws {
        let suite = "review-permission-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = OffloadPermissionManager(defaults: defaults)
        manager.setPermissionLevel(.askOnce, for: "apple-photos")
        manager.setPermissionLevel(.askOnce, for: "apple-location")
        var first: PermissionResult?
        var second: PermissionResult?
        var secondEntered = false
        let a = Task { first = await manager.checkPermission(for: "apple-photos", sessionId: "a", fullCommand: "apple-photos list") }
        await settle { manager.pendingRequest != nil }
        let firstID = try XCTUnwrap(manager.pendingRequest?.id)
        let b = Task {
            secondEntered = true
            second = await manager.checkPermission(for: "apple-location", sessionId: "b", fullCommand: "apple-location current")
        }
        defer { a.cancel(); b.cancel(); manager.resetSessionGrants(for: "a"); manager.resetSessionGrants(for: "b") }
        await settle { secondEntered }
        XCTAssertEqual(manager.pendingRequest?.id, firstID)
        manager.respond(to: firstID, allowed: false)
        XCTAssertEqual(manager.pendingRequest?.sessionId, "b")
        let secondID = try XCTUnwrap(manager.pendingRequest?.id)
        b.cancel()
        await settle { second != nil && first != nil }
        manager.respond(to: secondID, allowed: true) // Late UI response must be a no-op.
        if case .denied? = first {} else { XCTFail("First request must be denied") }
        if case .denied? = second {} else { XCTFail("Cancelled request must not grant permission") }
        XCTAssertNil(manager.pendingRequest)

        var allowedA: PermissionResult?
        var allowedB: PermissionResult?
        var duplicateEntered = false
        let c = Task { allowedA = await manager.checkPermission(for: "apple-photos", sessionId: "same", fullCommand: "apple-photos list") }
        await settle { manager.pendingRequest != nil }
        let consentID = try XCTUnwrap(manager.pendingRequest?.id)
        let d = Task {
            duplicateEntered = true
            allowedB = await manager.checkPermission(for: "apple-photos", sessionId: "same", fullCommand: "apple-photos list")
        }
        defer { c.cancel(); d.cancel(); manager.resetSessionGrants(for: "same") }
        await settle { duplicateEntered }
        manager.respond(to: consentID, allowed: true)
        await settle { allowedA != nil && allowedB != nil }
        if case .allowed? = allowedA {} else { XCTFail("First request must be allowed") }
        if case .allowed? = allowedB {} else { XCTFail("Same-session duplicate must share the grant") }
        XCTAssertNil(manager.pendingRequest)
    }

    func testReleasedSlotIsReservedBeforeWaiterResumes() async throws {
        let manager = SessionConcurrencyManager()
        var leases: [SessionSlotLease] = []
        for i in 0..<manager.maxConcurrent {
            leases.append(try await manager.acquire(sessionId: "running-\(i)", exempt: false))
        }
        var granted: SessionSlotLease?
        let waiter = Task { granted = try? await manager.acquire(sessionId: "waiting", exempt: false) }
        defer { waiter.cancel(); for lease in leases { manager.release(lease) }; if let granted { manager.release(granted) } }
        await settle { manager.isSuspended("waiting") }
        manager.release(leases.removeLast())
        // No await here: another caller can enter before the resumed task runs.
        XCTAssertEqual(manager.runningSessions.count, manager.maxConcurrent)
        XCTAssertTrue(manager.runningSessions.contains("waiting"))
        var cancelled = false
        let newcomer = Task {
            do { _ = try await manager.acquire(sessionId: "newcomer", exempt: false) }
            catch is CancellationError { cancelled = true }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        await settle { manager.isSuspended("newcomer") }
        newcomer.cancel()
        await settle { cancelled && granted != nil }
        XCTAssertFalse(manager.runningSessions.contains("newcomer"))
    }

    func testFailedRecoveryRetainsSnapshotUntilRetrySucceeds() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try BackupRestoreJournal.begin(backupId: "test", categories: ["providers"], supportRoot: root)
        let rollback = root.appendingPathComponent("rollback-test")
        try FileManager.default.createDirectory(at: rollback, withIntermediateDirectories: true)
        let saved = rollback.appendingPathComponent("providers.json")
        let live = root.appendingPathComponent("missing-parent/provider.json")
        let sidecar = saved.appendingPathExtension("live-path-of")
        try Data("original".utf8).write(to: saved)
        try Data(live.path.utf8).write(to: sidecar)
        _ = BackupRestoreJournal.reconcileAtLaunch(supportRoot: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertNotNil(BackupRestoreJournal.interrupted(at: root))
        XCTAssertThrowsError(try BackupRestoreJournal.begin(backupId: "new", categories: [], supportRoot: root))
        try FileManager.default.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = BackupRestoreJournal.reconcileAtLaunch(supportRoot: root)
        XCTAssertEqual(try String(contentsOf: live, encoding: .utf8), "original")
        XCTAssertNil(BackupRestoreJournal.interrupted(at: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rollback.path))
    }

    func testMalformedRecoveryMarkerDoesNotSweepSnapshots() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let rollback = root.appendingPathComponent("rollback-test")
        try FileManager.default.createDirectory(at: rollback, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: root.appendingPathComponent("in-progress.json"))
        _ = BackupRestoreJournal.reconcileAtLaunch(supportRoot: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollback.path))
    }

    func testCancelledFileWorkReturnsPromptlyAndCannotWriteAfterUnblocking() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("must-not-exist")
        let entered = DispatchSemaphore(value: 0)
        let unblock = DispatchSemaphore(value: 0)
        let workerDone = DispatchSemaphore(value: 0)
        var cancelled = false
        let task = Task {
            do {
                try await FileToolIO.run("test write", timeout: 20) { cancellation in
                    defer { workerDone.signal() }
                    entered.signal()
                    unblock.wait()
                    try FileToolIO.writeData(Data("late write".utf8), to: destination, append: false,
                                            createDirs: false, cancellation: cancellation)
                }
            } catch is CancellationError { cancelled = true }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        let started = await Task.detached { entered.wait(timeout: .now() + 3) == .success }.value
        XCTAssertTrue(started)
        task.cancel()
        await settle { cancelled }
        unblock.signal()
        let freed = await Task.detached { workerDone.wait(timeout: .now() + 3) == .success }.value
        XCTAssertTrue(freed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testScheduledReceiptKeepsItsOwnResultAndCompletesOnce() async {
        let a = ScheduledTurnReceipt()
        let b = ScheduledTurnReceipt()
        a.resolve(.init(text: "A result", succeeded: true))
        a.resolve(.init(text: "later unrelated reply", succeeded: true))
        b.resolve(.init(text: "B result", succeeded: false))
        let first = await a.wait()
        let second = await b.wait()
        XCTAssertEqual(first?.text, "A result")
        XCTAssertEqual(first?.succeeded, true)
        XCTAssertEqual(second?.text, "B result")
        XCTAssertEqual(second?.succeeded, false)
    }
}

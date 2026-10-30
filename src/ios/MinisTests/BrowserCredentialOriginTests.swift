import XCTest
@testable import Minis

final class BrowserCredentialOriginTests: XCTestCase {
    @MainActor
    func testOriginMatchingDoesNotTrustSimilarDomainsOrInsecurePages() {
        XCTAssertEqual(BrowserCredentialStore.origin(for: "https://Example.com:443/login?q=1"), "https://example.com")
        XCTAssertNotEqual(BrowserCredentialStore.origin(for: "https://example.com:8443"), "https://example.com")
        XCTAssertNotEqual(BrowserCredentialStore.origin(for: "https://example.com.attacker.test"), "https://example.com")
        XCTAssertNotEqual(BrowserCredentialStore.origin(for: "https://accounts.example.com"), "https://example.com")
        XCTAssertNil(BrowserCredentialStore.origin(for: "http://example.com"))
        XCTAssertNil(BrowserCredentialStore.origin(for: "file:///tmp/login.html"))
        XCTAssertNil(BrowserCredentialStore.origin(for: "about:blank"))
    }
}

@MainActor
private final class BrowserTestVault: BrowserCredentialVault {
    var data: Data?
    var failWrites = false
    func read() throws -> Data? { data }
    func write(_ data: Data) throws {
        if failWrites { throw NSError(domain: "TestVault", code: 1) }
        self.data = data
    }
}

final class BrowserPasswordFileTests: XCTestCase {
    @MainActor
    func testExplicitImportNeverModifiesSourceFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("vault.json")
        let initial = UUID().uuidString
        let object: [String: Any] = ["version": 1, "accounts": [
            ["website": "https://example.com/login", "username": "test-user", "password": initial],
            ["website": "https://other.example.com", "username": "other", "password": UUID().uuidString]
        ]]
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let vault = BrowserTestVault()
        let store = BrowserCredentialStore(vault: vault, authenticate: { true })
        await store.unlock()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.importFile(file))
        XCTAssertEqual(store.entries.count, 2)
        var entry = try XCTUnwrap(store.entries.first { $0.username == "test-user" })
        entry.password = UUID().uuidString
        XCTAssertTrue(store.save(entry))
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(saved["version"] as? Int, 1)
        XCTAssertEqual((saved["accounts"] as? [[String: String]])?.first?["password"], initial)
        let beforeFailure = try Data(contentsOf: file)
        vault.failWrites = true
        store.delete(entry)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(try Data(contentsOf: file), beforeFailure)
        XCTAssertNotNil(store.errorMessage)
        vault.failWrites = false
        store.delete(entry)
        XCTAssertEqual(store.entries.count, 1)
        store.lock()
        await store.unlock()
        XCTAssertEqual(store.entries.map(\.username), ["other"])
        XCTAssertEqual(try Data(contentsOf: file), beforeFailure)
    }

    @MainActor
    func testDomainKeyedVaultAndEmptyVault() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("vault.json")
        try JSONSerialization.data(withJSONObject: ["example.com": ["account": "user", "password": UUID().uuidString]]).write(to: file)
        let store = BrowserCredentialStore(vault: BrowserTestVault(), authenticate: { true })
        await store.unlock()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.importFile(file))
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.origin, "https://example.com")
        store.delete(entry)
        store.lock()
        await store.unlock()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(store.errorMessage)
    }

    func testReplyRedactionHoldsPasswordAcrossStreamChunks() {
        let password = "test-only-secret-42"
        let prefix = "已保存：" + String(password.prefix(8))
        XCTAssertEqual(PasswordReplyRedactor.redact(prefix, passwords: [password], streaming: true), "已保存：")
        let full = PasswordReplyRedactor.redact(prefix + String(password.dropFirst(8)) + "，请查看", passwords: [password], streaming: true)
        XCTAssertFalse(full.contains(password))
        XCTAssertTrue(full.contains("密码已隐藏"))
        XCTAssertEqual(PasswordReplyRedactor.redact("普通回复", passwords: [password], streaming: false), "普通回复")
    }
}

final class BrowserSecureSessionTests: XCTestCase {
    @MainActor
    func testCancelIsOneShotAndReleasesNativeValuesWithoutReturningThem() {
        let manager = BrowserUseManager()
        var statuses: [String] = []
        let secret = UUID().uuidString
        let session = BrowserSecureInputSession(manager: manager, origin: "https://example.com",
            requester: "Synthetic Bot", purpose: "Test", selector: "#password", kind: .password) { statuses.append($0) }
        manager.secureInputSession = session
        BrowserUseManager.secureInteractionManager = manager
        session.secret = secret; session.username = "synthetic-user"; session.reveal = true
        session.finish("cancelled"); session.finish("cancelled")
        XCTAssertEqual(statuses.count, 1)
        XCTAssertTrue(statuses[0].contains("reference="))
        XCTAssertFalse(statuses[0].contains(secret))
        XCTAssertTrue(session.secret.isEmpty && session.username.isEmpty && !session.reveal)
        XCTAssertNil(manager.secureInputSession)
        XCTAssertNil(BrowserUseManager.secureInteractionManager)
    }

    @MainActor
    func testSaveRequiresLoginConfirmationAndTruthfulAuthenticationAndWriteResults() async throws {
        let manager = BrowserUseManager()
        let vault = BrowserTestVault()
        let denied = BrowserCredentialStore(vault: vault, authenticate: { false })
        var statuses: [String] = []
        let refused = BrowserSecureInputSession(manager: manager, origin: "https://example.com",
            requester: "Synthetic Bot", purpose: "Test", selector: "#password", kind: .password,
            store: denied) { statuses.append($0) }
        refused.secret = UUID().uuidString; refused.filled = true; refused.confirmedLogin = true
        await refused.prepareSave(); refused.save()
        XCTAssertTrue(statuses.isEmpty)
        XCTAssertNil(vault.data)
        XCTAssertNotNil(refused.feedback)
        refused.finish("cancelled")
        statuses.removeAll()

        let store = BrowserCredentialStore(vault: vault, authenticate: { true })
        let session = BrowserSecureInputSession(manager: manager, origin: "https://example.com",
            requester: "Synthetic Bot", purpose: "Test", selector: "#password", kind: .password,
            store: store) { statuses.append($0) }
        let secret = UUID().uuidString
        session.secret = secret; session.username = "synthetic"; session.filled = true
        await session.prepareSave(); session.save()
        XCTAssertTrue(statuses.isEmpty); XCTAssertFalse(store.isUnlocked)
        session.confirmedLogin = true
        await session.prepareSave()
        vault.failWrites = true; session.save()
        XCTAssertTrue(statuses.isEmpty); XCTAssertNil(vault.data); XCTAssertNotNil(session.feedback)
        vault.failWrites = false; session.save()
        XCTAssertEqual(statuses.count, 1); XCTAssertTrue(statuses[0].contains("saved"))
        XCTAssertFalse(statuses[0].contains(secret)); XCTAssertTrue(session.secret.isEmpty)
        let saved = try JSONDecoder().decode([BrowserCredential].self, from: XCTUnwrap(vault.data))
        XCTAssertEqual(saved.count, 1); XCTAssertEqual(saved[0].password, secret)

        let updated = BrowserSecureInputSession(manager: manager, origin: "https://example.com",
            requester: "Synthetic Bot", purpose: "Test", selector: "#password", kind: .password,
            store: store) { statuses.append($0) }
        updated.secret = UUID().uuidString; updated.username = "synthetic"
        updated.filled = true; updated.confirmedLogin = true
        await updated.prepareSave(); XCTAssertTrue(updated.updateExisting)
        updated.save(); XCTAssertTrue(statuses.last?.contains("updated") == true)
        let entries = try JSONDecoder().decode([BrowserCredential].self, from: XCTUnwrap(vault.data))
        XCTAssertEqual(entries.count, 1); XCTAssertEqual(entries[0].id, saved[0].id)
    }

    @MainActor
    func testPINAndOTPDoNotOfferPersistence() async {
        for kind in [BrowserSecureInputSession.Kind.pin, .otp] {
            let vault = BrowserTestVault()
            let store = BrowserCredentialStore(vault: vault, authenticate: { true })
            let session = BrowserSecureInputSession(manager: BrowserUseManager(), origin: "https://example.com",
                requester: "Synthetic Bot", purpose: "Test", selector: "#code", kind: kind,
                store: store) { _ in }
            session.secret = UUID().uuidString; session.filled = true; session.confirmedLogin = true
            await session.prepareSave(); session.save()
            XCTAssertNil(vault.data); XCTAssertFalse(store.isUnlocked)
            session.finish("cancelled"); XCTAssertTrue(session.secret.isEmpty)
        }
    }
}

final class CalendarScheduleTests: XCTestCase {
    func testMonthlySkipsMonthsWithoutSelectedDay() throws {
        let calendar = Calendar.current
        let from = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 10)))
        let next = try XCTUnwrap(ScheduledJobRunner.nextCalendarFire(trigger: .calendar(hour: 9, minute: 15, day: 31, month: nil), from: from))
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: next)
        XCTAssertEqual(parts.month, 3)
        XCTAssertEqual(parts.day, 31)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 15)
    }

    func testYearlyLeapDayAndInvalidTime() throws {
        let calendar = Calendar.current
        let from = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let next = try XCTUnwrap(ScheduledJobRunner.nextCalendarFire(trigger: .calendar(hour: 9, minute: 0, day: 29, month: 2), from: from))
        XCTAssertEqual(calendar.component(.year, from: next), 2028)
        XCTAssertNil(ScheduledJobRunner.nextCalendarFire(trigger: .calendar(hour: 25, minute: 0, day: 1, month: nil), from: from))
    }
}

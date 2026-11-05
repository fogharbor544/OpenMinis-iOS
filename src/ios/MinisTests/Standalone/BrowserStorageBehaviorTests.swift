import Foundation

@MainActor
final class MemoryCredentialVault: BrowserCredentialVault {
    var data: Data?
    var failWrites = false
    var reads = 0
    func read() throws -> Data? { reads += 1; return data }
    func write(_ data: Data) throws {
        if failWrites { throw NSError(domain: "TestStorage", code: 1) }
        self.data = data
    }
}

@main
struct BrowserStorageBehaviorTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appendingPathComponent("shared-vault.json")
        let file = root.appendingPathComponent("bookmarks.json")
        let bookmarks = BrowserBookmarkStore(fileURL: file)
        var bookmark = BrowserBookmark(title: "Page", url: "https://example.com/a")
        precondition(bookmarks.save(bookmark))
        bookmark.title = "Renamed"
        bookmark.url = "https://example.com/b"
        precondition(bookmarks.save(bookmark))
        let loaded = BrowserBookmarkStore(fileURL: file)
        precondition(loaded.entries.count == 1 && loaded.entries[0].title == "Renamed")
        precondition(loaded.entries[0].url == bookmark.url)
        loaded.delete(at: IndexSet(integer: 0))
        precondition(BrowserBookmarkStore(fileURL: file).entries.isEmpty)
        precondition(!bookmarks.save(BrowserBookmark(title: "Unsafe", url: "javascript:alert(1)")))
        let corrupt = root.appendingPathComponent("corrupt.json")
        try Data("corrupt".utf8).write(to: corrupt)
        let broken = BrowserBookmarkStore(fileURL: corrupt)
        precondition(!broken.save(bookmark))
        let unchanged = try String(contentsOf: corrupt, encoding: .utf8)
        precondition(unchanged == "corrupt")
        let directory = root.appendingPathComponent("directory")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let failed = BrowserBookmarkStore(fileURL: directory)
        precondition(!failed.save(bookmark) && failed.entries.isEmpty)

        let vault = MemoryCredentialVault()
        let denied = BrowserCredentialStore(vault: vault, sharedVaultURL: shared, authenticate: { false })
        await denied.unlock()
        precondition(!denied.isUnlocked && vault.reads == 0)
        let passwords = BrowserCredentialStore(vault: vault, sharedVaultURL: shared, authenticate: { true })
        await passwords.unlock()
        var first = BrowserCredential(origin: "https://EXAMPLE.com:443/login", username: "one", password: "test-only-one")
        precondition(passwords.save(first))
        first = passwords.entries[0]
        precondition(first.origin == "https://example.com")
        let updatedPassword = UUID().uuidString
        precondition(passwords.save(BrowserCredential(origin: "https://example.com", username: "one", password: updatedPassword)))
        precondition(passwords.entries.count == 1 && passwords.entries[0].id == first.id)
        let second = BrowserCredential(origin: "https://example.com", username: "two", password: "test-only-two")
        precondition(passwords.save(second))
        first.username = "two"
        precondition(!passwords.save(first))
        precondition(passwords.entries.count == 2)
        vault.failWrites = true
        passwords.delete(second)
        precondition(passwords.entries.count == 2 && passwords.errorMessage != nil)
        vault.failWrites = false
        passwords.delete(second)
        passwords.lock()
        precondition(!passwords.isUnlocked && passwords.entries.isEmpty)
        precondition(!passwords.save(second))
        await passwords.unlock()
        precondition(passwords.entries.count == 1 && passwords.entries[0].password == updatedPassword)
        precondition(BrowserCredentialStore.origin(for: "https://example.com:443/a") == "https://example.com")
        precondition(BrowserCredentialStore.origin(for: "https://example.com:8443") != "https://example.com")
        precondition(BrowserCredentialStore.origin(for: "https://example.com.attacker.test") != "https://example.com")
        precondition(BrowserCredentialStore.origin(for: "http://example.com") == nil)
        let sourceFile = root.appendingPathComponent("synthetic-import.json")
        let sourceData = try JSONSerialization.data(withJSONObject: [["origin": "https://import.example", "username": "synthetic", "password": UUID().uuidString]])
        try sourceData.write(to: sourceFile)
        precondition(passwords.importFile(sourceFile))
        var imported = passwords.entries.first { $0.origin == "https://import.example" }!
        imported.password = UUID().uuidString
        precondition(passwords.save(imported))
        let afterEdit = try JSONSerialization.jsonObject(with: Data(contentsOf: sourceFile)) as! [[String: String]]
        precondition(afterEdit.first?["password"] == imported.password)
        passwords.delete(imported)
        let afterDelete = try JSONSerialization.jsonObject(with: Data(contentsOf: sourceFile)) as! [[String: String]]
        precondition(afterDelete.isEmpty)
        try sourceData.write(to: sourceFile)
        vault.failWrites = true
        precondition(!passwords.importFile(sourceFile))
        precondition(!passwords.entries.contains { $0.origin == "https://import.example" })
        vault.failWrites = false
        // A linked record must never silently become a Keychain-only edit.
        precondition(passwords.importFile(sourceFile))
        var staleEntry = passwords.entries.first { $0.origin == "https://import.example" }!
        let renamedData = try JSONSerialization.data(withJSONObject: [["origin": "https://import.example", "username": "renamed", "password": UUID().uuidString]])
        try renamedData.write(to: sourceFile)
        let beforeConflict = vault.data
        staleEntry.password = UUID().uuidString
        precondition(!passwords.save(staleEntry), "renamed source must reject stale edit")
        let afterConflict = try Data(contentsOf: sourceFile)
        precondition(vault.data == beforeConflict && afterConflict == renamedData)
        try FileManager.default.removeItem(at: sourceFile)
        precondition(!passwords.save(staleEntry), "missing source must reject stale edit")
        precondition(vault.data == beforeConflict)

        // Nested/domain empty collections are valid and clear only shared rows.
        let sharedVault = MemoryCredentialVault()
        let live = BrowserCredentialStore(vault: sharedVault, sharedVaultURL: shared, authenticate: { true })
        let sharedRows: [String: Any] = ["example.com": [["username": "one", "password": UUID().uuidString]]]
        try JSONSerialization.data(withJSONObject: sharedRows).write(to: shared)
        await live.unlock()
        precondition(live.entries.count == 1 && live.entries[0].sourceBookmark == nil)
        let monitor = Task { await live.monitorSharedVault() }
        let sharedID = live.entries[0].id
        live.refreshSharedVault()
        precondition(live.entries[0].id == sharedID)
        let emptyRows: [String: Any] = ["metadata": ["version": 1], "nested": ["example.com": []]]
        try JSONSerialization.data(withJSONObject: emptyRows).write(to: shared)
        let refreshDeadline = Date().addingTimeInterval(3)
        while !live.entries.isEmpty && Date() < refreshDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
        precondition(live.entries.isEmpty && live.errorMessage == nil, "visible monitor must apply empty nested vault")
        let namedRows: [String: Any] = ["accounts": ["primary": [["origin": "https://example.com", "username": "named", "password": UUID().uuidString]]]]
        try JSONSerialization.data(withJSONObject: namedRows).write(to: shared)
        live.refreshSharedVault()
        precondition(live.entries.count == 1)
        let namedEmpty: [String: Any] = ["accounts": ["primary": []]]
        try JSONSerialization.data(withJSONObject: namedEmpty).write(to: shared)
        live.refreshSharedVault()
        precondition(live.entries.isEmpty && live.errorMessage == nil, "recognized parent collection must permit empty named children")
        try JSONSerialization.data(withJSONObject: ["unrelated": []]).write(to: shared)
        live.refreshSharedVault()
        precondition(live.errorMessage != nil, "unrecognized empty collection must not clear vault")
        try Data("{invalid".utf8).write(to: shared)
        live.refreshSharedVault()
        precondition(live.errorMessage != nil)
        try JSONSerialization.data(withJSONObject: ["unrelated": "data"]).write(to: shared)
        live.refreshSharedVault()
        precondition(live.errorMessage != nil, "unrelated JSON must not clear vault")
        try JSONSerialization.data(withJSONObject: sharedRows).write(to: shared)
        live.refreshSharedVault()
        precondition(live.entries.count == 1)
        try FileManager.default.removeItem(at: shared)
        live.refreshSharedVault()
        precondition(live.entries.isEmpty, "deleted shared vault must remove stale shared rows")
        monitor.cancel()
        await monitor.value
        live.lock()
        vault.data = Data("bad-json".utf8)
        let corrupted = BrowserCredentialStore(vault: vault, sharedVaultURL: shared, authenticate: { true })
        await corrupted.unlock()
        precondition(!corrupted.isUnlocked && !corrupted.save(second))
        precondition(vault.data == Data("bad-json".utf8))

        var completeAuth: CheckedContinuation<Bool, Never>?
        let late = BrowserCredentialStore(vault: MemoryCredentialVault(), sharedVaultURL: shared, authenticate: {
            await withCheckedContinuation { completeAuth = $0 }
        })
        let unlock = Task { await late.unlock() }
        while completeAuth == nil { await Task.yield() }
        late.lock()
        completeAuth?.resume(returning: true)
        await unlock.value
        precondition(!late.isUnlocked)
        print("PASS: bookmark CRUD/reload/failures; credential auth refusal, CRUD, collisions, failed writes, origin matching, corrupt data and late-auth cancellation")
    }
}

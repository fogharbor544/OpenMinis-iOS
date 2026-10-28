import XCTest
@testable import Minis

final class BrowserBookmarkStoreTests: XCTestCase {
    @MainActor
    func testAddEditDeleteSurviveReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("bookmarks.json")
        let store = BrowserBookmarkStore(fileURL: url)
        var bookmark = BrowserBookmark(title: "Example", url: "https://example.com")
        XCTAssertTrue(store.save(bookmark))
        let reloaded = BrowserBookmarkStore(fileURL: url)
        XCTAssertEqual(reloaded.entries.first?.id, bookmark.id)
        bookmark.title = "Edited"
        bookmark.url = "https://example.com/docs"
        XCTAssertTrue(reloaded.save(bookmark))
        let edited = BrowserBookmarkStore(fileURL: url)
        XCTAssertEqual(edited.entries.count, 1)
        XCTAssertEqual(edited.entries.first?.title, "Edited")
        XCTAssertEqual(edited.entries.first?.url, bookmark.url)
        edited.delete(at: IndexSet(integer: 0))
        XCTAssertTrue(BrowserBookmarkStore(fileURL: url).entries.isEmpty)
    }

    @MainActor
    func testRejectsNonWebAddresses() {
        for value in ["javascript:alert(1)", "file:///etc/passwd", "about:blank", "https://", ""] {
            XCTAssertNil(BrowserBookmarkStore.normalizedURL(value))
        }
        XCTAssertNotNil(BrowserBookmarkStore.normalizedURL(" https://example.com/path?q=hello "))
    }

    @MainActor
    func testFailedWriteDoesNotChangeVisibleEntries() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = BrowserBookmarkStore(fileURL: file.appendingPathComponent("bookmarks.json"))
        XCTAssertFalse(store.save(BrowserBookmark(title: "Example", url: "https://example.com")))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }
}

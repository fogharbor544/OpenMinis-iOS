import XCTest
@testable import Minis

final class BackupExportJournalTests: XCTestCase {
    func testRetiredStagingIsRemovedWithoutRemovingCurrentStagingOrSavedBackups() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let backupID = UUID().uuidString
        let staging = root.appendingPathComponent("minisbak-\(backupID)", isDirectory: true)
        let snapshot = staging.appendingPathComponent("chat.sqlite")
        let savedBackup = root.appendingPathComponent("Saved.minisbak")
        let markerURL = root.appendingPathComponent("in-progress.json")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("snapshot".utf8).write(to: snapshot)
        try Data("complete package".utf8).write(to: savedBackup)
        let timestamp = Date(timeIntervalSince1970: 1)
        var marker = BackupExportJournal.Marker(
            backupId: backupID, startedAt: timestamp, snapshotAt: timestamp,
            categories: ["chats"], includeCredentials: true, encrypted: true,
            stagingVersion: BackupExportJournal.stagingVersion)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: markerURL)

        try BackupExportJournal.discardIncompatibleStaging(in: root)
        XCTAssertTrue(fm.fileExists(atPath: snapshot.path))
        XCTAssertTrue(fm.fileExists(atPath: markerURL.path))

        marker.stagingVersion = 1
        try encoder.encode(marker).write(to: markerURL)
        try BackupExportJournal.discardIncompatibleStaging(in: root)
        XCTAssertFalse(fm.fileExists(atPath: staging.path))
        XCTAssertFalse(fm.fileExists(atPath: markerURL.path))
        XCTAssertEqual(try Data(contentsOf: savedBackup), Data("complete package".utf8))
    }
}

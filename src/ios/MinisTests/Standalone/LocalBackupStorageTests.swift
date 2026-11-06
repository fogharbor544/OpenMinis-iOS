import Foundation

@main struct LocalBackupStorageTests {
    private static func check(_ condition: Bool) { precondition(condition) }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let directory = root.appendingPathComponent("Minis/Backups", isDirectory: true)
        let storage = LocalBackupStorage(directory: directory)

        // First visit works before any backup exists and creates its directory.
        check(try storage.packages().isEmpty)
        check(fm.fileExists(atPath: directory.path))
        let source = root.appendingPathComponent("phone.minisbak")
        try Data("first backup".utf8).write(to: source)
        let first = try storage.save(source)
        check(first.deletingLastPathComponent() == directory)
        check(try Data(contentsOf: first) == Data("first backup".utf8))
        check(!fm.fileExists(atPath: source.path))

        // A repeated filename never destroys a previous backup.
        try Data("second backup".utf8).write(to: source)
        let second = try storage.save(source)
        check(first != second)
        check(try Data(contentsOf: first) == Data("first backup".utf8))
        check(try Data(contentsOf: second) == Data("second backup".utf8))
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: first.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: second.path)

        // Only complete, regular backup files are offered for restore.
        try Data().write(to: directory.appendingPathComponent("unfinished.minisbak.partial"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))
        try fm.createDirectory(at: directory.appendingPathComponent("folder.minisbak"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: directory.appendingPathComponent("link.minisbak"), withDestinationURL: first)
        let packages = try storage.packages()
        check(packages.map(\.url) == [second, first])
        check(packages.map(\.size) == [13, 12])

        // A failed move must not overwrite the backup with the same name.
        do {
            _ = try storage.save(root.appendingPathComponent("missing/phone.minisbak"))
            preconditionFailure("missing source must fail")
        } catch {}
        check(try Data(contentsOf: first) == Data("first backup".utf8))
        check(try storage.packages().count == 2)

        // Directory errors must reach the caller rather than look like an empty list.
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        do {
            _ = try LocalBackupStorage(directory: blocked).packages()
            preconditionFailure("a file cannot be used as the backup directory")
        } catch {}
        print("PASS: local directory creation, persistence, collision preservation, newest-first restore list, filtering and errors")
    }
}

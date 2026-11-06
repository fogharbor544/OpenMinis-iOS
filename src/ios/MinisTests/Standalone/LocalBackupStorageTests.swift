import Foundation

// Collect every assertion instead of trapping on the first one, so a single
// native run reports all differences between the shipping store and its
// fixture. Failures print with labels and exit non-zero for the CI step.
@main struct LocalBackupStorageTests {
    private static func directoryPath(_ url: URL) -> String {
        var path = url.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func main() throws {
        var failures: [String] = []
        var notes: [String] = []

        func check(_ label: String, _ body: () throws -> Bool) {
            do {
                let passed = try body()
                if !passed { failures.append("FAIL \(label)") }
            } catch {
                failures.append("THREW \(label): \(error.localizedDescription)")
            }
        }
        func expectFailure(_ label: String, _ body: () throws -> Void) {
            do {
                try body()
                failures.append("NO ERROR \(label)")
            } catch {
                notes.append("expected \(label): \(error.localizedDescription)")
            }
        }

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let directory = root.appendingPathComponent("Minis/Backups", isDirectory: true)
        let storage = LocalBackupStorage(directory: directory)

        // First visit works before any backup exists and creates its directory.
        check("first visit lists no packages") { try storage.packages().isEmpty }
        check("first visit creates the directory") { fm.fileExists(atPath: directory.path) }

        let source = root.appendingPathComponent("phone.minisbak")
        try Data("first backup".utf8).write(to: source)
        let first = try storage.save(source)
        notes.append("directory.path=\(directory.path)")
        notes.append("first.path=\(first.path)")
        check("save lands inside the backup directory") {
            directoryPath(first.deletingLastPathComponent()) == directoryPath(directory)
        }
        check("save preserves the bytes") { try Data(contentsOf: first) == Data("first backup".utf8) }
        check("save moves the package out of scratch") { !fm.fileExists(atPath: source.path) }

        // A repeated filename never destroys a previous backup.
        try Data("second backup".utf8).write(to: source)
        let second = try storage.save(source)
        notes.append("second.path=\(second.path)")
        check("a name collision keeps the older package") { first != second }
        check("older package intact") { try Data(contentsOf: first) == Data("first backup".utf8) }
        check("newer package stored") { try Data(contentsOf: second) == Data("second backup".utf8) }
        check("setting modification dates succeeds", { () -> Bool in
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: first.path)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: second.path)
            return true
        })

        // Only complete, regular backup files are offered for restore.
        check("writing decoys succeeds", { () -> Bool in
            try Data().write(to: directory.appendingPathComponent("unfinished.minisbak.partial"))
            try Data().write(to: directory.appendingPathComponent("notes.txt"))
            try fm.createDirectory(at: directory.appendingPathComponent("folder.minisbak"),
                                   withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: directory.appendingPathComponent("link.minisbak"),
                                      withDestinationURL: first)
            return true
        })
        let packages = (try? storage.packages()) ?? []
        notes.append("listed=\(packages.map { $0.url.lastPathComponent })")
        // `contentsOfDirectory` resolves the `/var` symlink to `/private/var`,
        // so compare resolved paths rather than the exact URLs `save` returned.
        notes.append("listedPaths=\(packages.map { $0.url.resolvingSymlinksInPath().path })")
        check("newest-first list filtered to .minisbak regular files") {
            packages.map { $0.url.resolvingSymlinksInPath().path }
                == [second, first].map { $0.resolvingSymlinksInPath().path }
        }
        check("sizes come from file metadata") { packages.map(\.size) == [13, 12] }

        // A failed move must not overwrite the backup with the same name.
        expectFailure("a missing source must fail") {
            _ = try storage.save(root.appendingPathComponent("missing/phone.minisbak"))
        }
        check("failed move preserves the target") { try Data(contentsOf: first) == Data("first backup".utf8) }
        check("failed move adds no package") { try storage.packages().count == 2 }

        // Directory errors must reach the caller rather than look like an empty list.
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        expectFailure("a file cannot be the backup directory") {
            _ = try LocalBackupStorage(directory: blocked).packages()
        }

        for note in notes { print("NOTE: \(note)") }
        for failure in failures { print(failure) }
        if failures.isEmpty {
            print("PASS: local directory creation, persistence, collision preservation, newest-first restore list, filtering and errors")
        } else {
            print("FAIL: \(failures.count) local backup storage assertions")
            exit(1)
        }
    }
}

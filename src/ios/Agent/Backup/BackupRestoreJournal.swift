import Foundation

private let logger = AppLogger(category: "Backup")

/// Crash-safety marker + persistent staging for a restore in flight
/// (docs/backup-restore-design.md §8.1, review finding B4).
///
/// The rollback snapshot used to live inside the importer's tmp work directory,
/// which a `defer` deletes — so it was guaranteed to be gone or unreachable on
/// the exact failure it existed for. Two consequences: a restore killed
/// mid-flight left the live directories half-overwritten with no recovery path,
/// and nothing on the next launch even knew a restore had been interrupted.
///
/// This moves the snapshot to Application Support (persistent, not purged like
/// tmp) and writes a small marker around the restore so the next launch can
/// reconcile.
enum BackupRestoreJournal {

    private static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("BackupRestore", isDirectory: true)
    }

    private static var markerURL: URL {
        supportDir.appendingPathComponent("in-progress.json")
    }

    /// Snapshot directory for one restore run.
    ///
    /// [review I3] Per-run rather than a fixed path. It used to be a single
    /// shared `rollback/` directory, while `finish()` deletes the whole thing
    /// on a `defer` — so two overlapping restores clobbered each other's
    /// snapshots, and whichever finished first deleted the other's only
    /// recovery state. Overlap is reachable: every call site builds a FRESH
    /// `BackupImporter()` (actor isolation only serialises calls on one
    /// instance), the root-level restore sheet can be opened from any screen,
    /// and the debug RPC path is independent of both. `runId` keeps the paths
    /// disjoint even if the exclusion guard is ever bypassed.
    static func stagingRoot(runId: String) -> URL {
        supportDir.appendingPathComponent("rollback-\(runId)", isDirectory: true)
    }

    /// Every rollback staging directory currently on disk.
    static func allStagingRoots(at supportRoot: URL? = nil) -> [URL] {
        let supportDir = supportRoot ?? Self.supportDir
        let names = (try? FileManager.default.contentsOfDirectory(atPath: supportDir.path)) ?? []
        return names.filter { $0.hasPrefix("rollback") }
            .map { supportDir.appendingPathComponent($0, isDirectory: true) }
    }

    struct Marker: Codable {
        var backupId: String
        var startedAt: Date
        var categories: [String]
    }

    static func begin(backupId: String, categories: [String], supportRoot: URL? = nil) throws {
        let supportDir = supportRoot ?? Self.supportDir
        let markerURL = supportDir.appendingPathComponent("in-progress.json")
        guard !FileManager.default.fileExists(atPath: markerURL.path) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey:
                AppLocalized("An interrupted restore still needs recovery. Restart the app before restoring again.")])
        }
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let marker = Marker(backupId: backupId, startedAt: Date(), categories: categories)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: markerURL, options: .atomic)
    }

    /// Clear the marker and this run's snapshot after a clean finish.
    ///
    /// Scoped to `runId` so a concurrent restore's staging survives (I3).
    static func finish(runId: String) {
        try? FileManager.default.removeItem(at: markerURL)
        try? FileManager.default.removeItem(at: stagingRoot(runId: runId))
    }

    /// A restore that never completed, if any.
    static func interrupted(at supportRoot: URL? = nil) -> Marker? {
        let markerURL = (supportRoot ?? supportDir).appendingPathComponent("in-progress.json")
        guard let data = try? Data(contentsOf: markerURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Marker.self, from: data)
    }

    /// Called at launch. Reports an interrupted restore and restores whatever
    /// snapshot survived.
    ///
    /// Deliberately conservative: it puts back the directories it has a
    /// complete copy-aside for and then clears the marker. It does NOT try to
    /// undo the DB-backed categories — those are Merge/LWW and idempotent, so
    /// a half-applied merge is a superset of the previous state rather than a
    /// corruption, and re-running the same restore converges.
    @discardableResult
    static func reconcileAtLaunch(supportRoot: URL? = nil) -> Marker? {
        let supportDir = supportRoot ?? Self.supportDir
        let markerURL = supportDir.appendingPathComponent("in-progress.json")
        guard let marker = interrupted(at: supportDir) else {
            guard !FileManager.default.fileExists(atPath: markerURL.path) else {
                logger.error("[Restore] unreadable recovery marker retained with snapshots")
                return nil
            }
            // No marker, but staging can still be here: a restore that died
            // before writing the marker, or after clearing it, leaves rollback
            // directories nothing will ever look at again. They hold full
            // copies of the categories being replaced, so for shared files or
            // chats that is the entire directory — silently, for good.
            //
            // Safe to delete precisely BECAUSE there is no marker: the marker
            // is what says a restore is mid-flight and its snapshots are still
            // needed. Without one there is nothing to roll back to.
            let fm = FileManager.default
            var swept = 0
            for root in allStagingRoots(at: supportDir) {
                let bytes = (try? root.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                    .totalFileAllocatedSize ?? 0
                try? fm.removeItem(at: root)
                swept += 1
                logger.info("[Restore] swept orphaned rollback staging (\(bytes) bytes)")
            }
            if swept > 0 {
                logger.info("[Restore] swept \(swept) orphaned rollback director(ies)")
            }
            return nil
        }
        logger.error("[Restore] previous restore did NOT complete: backupId=\(marker.backupId) startedAt=\(marker.startedAt) categories=\(marker.categories.joined(separator: ","))")

        let fm = FileManager.default
        var restored = 0
        var failed = false
        guard (try? fm.contentsOfDirectory(atPath: supportDir.path)) != nil else { return marker }
        for root in allStagingRoots(at: supportDir) {
            do {
                let names = try fm.contentsOfDirectory(atPath: root.path)
                for name in names {
                    let saved = root.appendingPathComponent(name)
                    if name.hasSuffix(Self.fileSnapshotSidecarSuffix) {
                        do {
                            let livePath = try String(contentsOf: saved, encoding: .utf8)
                            guard !livePath.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                            let payload = root.appendingPathComponent(String(name.dropLast(Self.fileSnapshotSidecarSuffix.count)))
                            try atomicReplace(directory: payload, onto: URL(fileURLWithPath: livePath))
                            // Remove the recovery instruction first, only after a successful restore.
                            try fm.removeItem(at: saved)
                            try? fm.removeItem(at: payload)
                            restored += 1
                        } catch {
                            failed = true
                            logger.error("[Restore] file recovery retained: \(error.localizedDescription)")
                        }
                        continue
                    }
                    let pointer = saved.appendingPathComponent(".live-path")
                    guard fm.fileExists(atPath: pointer.path) else { continue }
                    do {
                        let livePath = try String(contentsOf: pointer, encoding: .utf8)
                        guard !livePath.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                        try atomicReplace(directory: saved, onto: URL(fileURLWithPath: livePath))
                        try fm.removeItem(at: pointer)
                        try? fm.removeItem(at: saved)
                        restored += 1
                    } catch {
                        failed = true
                        logger.error("[Restore] directory recovery retained: \(error.localizedDescription)")
                    }
                }
            } catch {
                failed = true
                logger.error("[Restore] staging unreadable; recovery retained: \(error.localizedDescription)")
            }
        }
        if !failed {
            try? fm.removeItem(at: markerURL)
            for root in allStagingRoots(at: supportDir) { try? fm.removeItem(at: root) }
        }
        logger.info("[Restore] launch reconcile: restored \(restored), pending=\(failed)")
        return marker
    }

    /// Suffix for the sidecar that records a FILE snapshot's live target.
    static let fileSnapshotSidecarSuffix = ".live-path-of"

    /// Replace a live file or directory from a snapshot without consuming that snapshot.
    ///
    /// The previous `removeItem` + `copyItem` pair left the user's directory
    /// deleted and not yet replaced if the process died between the two — for
    /// the shared-files category that is the whole directory. `replaceItemAt`
    /// is the atomic swap this needs.
    static func atomicReplace(directory saved: URL, onto live: URL) throws {
        let fm = FileManager.default
        // replaceItemAt needs the replacement to sit next to the target, and it
        // consumes it, so work from a copy.
        let staged = live.deletingLastPathComponent()
            .appendingPathComponent(".restore-swap-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staged) }
        try fm.copyItem(at: saved, to: staged)
        // Don't carry the bookkeeping file into the live tree.
        try? fm.removeItem(at: staged.appendingPathComponent(".live-path"))
        if fm.fileExists(atPath: live.path) {
            _ = try fm.replaceItemAt(live, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: live)
        }
    }
}

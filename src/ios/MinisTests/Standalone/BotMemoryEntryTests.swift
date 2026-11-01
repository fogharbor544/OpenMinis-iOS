import Foundation

@main struct BotMemoryEntryTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("memory.sqlite")
        let store = BotMemoryStore(fileURL: file)
        func check(_ condition: @autoclosure () throws -> Bool) throws {
            let result = try condition(); precondition(result)
        }
        func make(_ owner: String, _ text: String, source: String = "m1") -> BotMemoryEntry {
            BotMemoryEntry(owner: owner, content: text, category: "preference", scope: "writing",
                           sourceSession: "conversation", sourceMessage: source, evidence: text)
        }
        let a = try store.save(make("bot:a", "I prefer concise writing"))
        _ = try store.save(make("bot:b", "I prefer detailed writing"))
        let aVisible = try store.visible(to: "bot:a")
        precondition(aVisible.count == 1 && aVisible[0].id == a.id)
        try check(try store.visible(to: "room:x").isEmpty)
        try store.setGrants(id: a.id, owner: "bot:a", grants: ["room:x"])
        try check(try store.visible(to: "room:x").count == 1)
        try check(try store.visible(to: "room:y").isEmpty)
        try store.setGrants(id: a.id, owner: "bot:a", grants: [])
        try check(try store.visible(to: "room:x").isEmpty)
        let reloaded = BotMemoryStore(fileURL: file)
        try check(try reloaded.visible(to: "bot:a").first?.sourceMessage == "m1")
        let additional = try store.save(make("bot:a", "Use diagrams for architecture", source: "m-other"))
        try check(try store.visible(to: "bot:a").count == 2)
        try store.forget(id: additional.id, owner: "bot:a")
        let replacement = try store.save(make("bot:a", "I prefer direct writing", source: "m2"), replacing: a.id, userInitiated: true)
        try check(try store.entries().first(where: { $0.id == a.id })?.status == "replaced")
        try check(try store.visible(to: "bot:a").count == 1)
        try store.forget(id: replacement.id, owner: "bot:a")
        try check(try store.recall(owner: "bot:a", query: "writing").isEmpty)
        do { _ = try store.save(make("bot:a", "I prefer direct writing", source: "m3")); fatalError("Resurrected deleted memory") }
        catch is BotMemoryError {}
        do { _ = try store.save(make("bot:a", "Paraphrased forgotten fact", source: "m2")); fatalError("Reprocessed forgotten evidence") }
        catch is BotMemoryError {}
        _ = try store.save(make("bot:a", "I prefer direct writing", source: "m4"), userInitiated: true)
        var pinned = make("bot:c", "Use plain language")
        pinned.pinned = true
        _ = try store.save(pinned)
        let context = try store.recall(owner: "bot:c", query: "unrelated question")
        precondition(context.contains("Use plain language"))
        try check(try store.recall(owner: "bot:c", query: "unrelated", budget: 5).isEmpty)
        do { _ = try store.save(make("bot:a", "My password is sensitive"), userInitiated: true); fatalError("Stored secret") }
        catch is BotMemoryError {}
        try store.forgetOwner("bot:a")
        try check(try store.visible(to: "bot:a").isEmpty)
        try check(try store.visible(to: "bot:b").count == 1)
        let first = try store.save(make("bot:d", "First fact"), userInitiated: true)
        _ = try store.save(make("bot:d", "Second fact"), userInitiated: true)
        do { _ = try store.save(make("bot:d", "Second fact"), replacing: first.id, userInitiated: true); fatalError("Reported a correction while leaving the old entry unchanged") }
        catch is BotMemoryError {}
        // Recent context is date-based, independent of the current question's terms.
        var dates = Calendar(identifier: .gregorian)
        dates.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for offset in [0, 2, 4, 6, 31] {
            var entry = make("bot:recent", "Project note day \(offset)", source: "d\(offset)")
            entry.createdAt = dates.date(byAdding: .day, value: -offset, to: now)!
            entry.updatedAt = entry.createdAt
            _ = try store.save(entry)
        }
        var oldPinned = make("bot:recent", "Pinned convention", source: "pinned")
        oldPinned.createdAt = dates.date(byAdding: .day, value: -90, to: now)!
        oldPinned.pinned = true
        _ = try store.save(oldPinned)
        let recent = try store.recentContext(owner: "bot:recent", now: now, dateCalendar: dates)
        precondition(recent.contains("Pinned convention") && recent.contains("Project note day 4"))
        precondition(!recent.contains("Project note day 6") && !recent.contains("Project note day 31"))
        precondition(!recent.contains("First fact"))
        var longNote = make("bot:lines", (0..<250).map { "L\($0)" }.joined(separator: "\n"))
        longNote.createdAt = now
        // Store content limit remains enforced, so use short lines for the daily cap test.
        _ = try store.save(longNote)
        let clipped = try store.recentContext(owner: "bot:lines", now: now, dateCalendar: dates)
        precondition(clipped.contains("L199") && !clipped.contains("L200"))
        print("PASS: SQLite owner isolation, persistence, sharing/revocation, replacement, forgotten-source suppression, bounded retrieval, multiple same-scope notes, date-based injection, line limits and secret refusal")
    }
}

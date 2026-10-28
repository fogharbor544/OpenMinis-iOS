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
        do { _ = try store.save(make("bot:a", "I prefer long writing", source: "m2")); fatalError("Silently accepted conflict") }
        catch is BotMemoryError {}
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
        do { try BotMemoryStore.validateEvidence(content: "short", evidence: "this article shorter", userText: "this article shorter", automatic: true); fatalError("Saved transient request") }
        catch is BotMemoryError {}
        do { try BotMemoryStore.validateEvidence(content: "fact", evidence: "other Bot said", userText: "hello", automatic: false); fatalError("Accepted fabricated evidence") }
        catch is BotMemoryError {}
        do { _ = try store.save(make("bot:a", "My password is sensitive"), userInitiated: true); fatalError("Stored secret") }
        catch is BotMemoryError {}
        try BotMemoryStore.validateEvidence(content: "concise", evidence: "I always prefer concise writing", userText: "I always prefer concise writing", automatic: true)
        try store.forgetOwner("bot:a")
        try check(try store.visible(to: "bot:a").isEmpty)
        try check(try store.visible(to: "bot:b").count == 1)
        let first = try store.save(make("bot:d", "First fact"), userInitiated: true)
        _ = try store.save(make("bot:d", "Second fact"), userInitiated: true)
        do { _ = try store.save(make("bot:d", "Second fact"), replacing: first.id, userInitiated: true); fatalError("Reported a correction while leaving the old entry unchanged") }
        catch is BotMemoryError {}
        print("PASS: SQLite owner isolation, persistence, sharing/revocation, replacement, forgotten-source suppression, bounded retrieval, evidence and secret refusal")
    }
}

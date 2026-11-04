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
        try store.saveFixedMemory(owner: "bot:fixed", content: "Use plain language")
        let fixed = try store.documentEntries(owner: "bot:fixed").first!
        precondition(fixed.isFixedMemory)
        try check(try store.longTermRuleContext(owner: "bot:fixed").contains("Use plain language"))
        try store.setGrants(id: fixed.id, owner: fixed.owner, grants: ["room:x"])
        try store.saveDocument(owner: fixed.owner, text: "", baseline: try store.documentEntries(owner: fixed.owner),
                               fixedEdits: [fixed.id: "Use plain language and short sentences"])
        let persisted = try reloaded.documentEntries(owner: fixed.owner).first!
        precondition(persisted.id == fixed.id && persisted.isFixedMemory && persisted.grants.isEmpty)
        try check(try store.longTermRuleContext(owner: fixed.owner).contains("short sentences"))
        do {
            try store.setFixedMemory(id: fixed.id, owner: "bot:b", fixed: false)
            fatalError("Changed another Bot's fixed memory")
        } catch is BotMemoryError {}
        try store.setFixedMemory(id: fixed.id, owner: fixed.owner, fixed: false)
        try check(try store.longTermRuleContext(owner: fixed.owner).isEmpty)
        let historyEntry = try store.documentEntries(owner: fixed.owner).first!
        precondition(!historyEntry.isFixedMemory && historyEntry.content == persisted.content)
        var automatic = make("bot:fixed", "Keep test reports short", source: "auto")
        automatic.automatic = true
        let suggested = try store.save(automatic)
        try check(try store.longTermRuleContext(owner: fixed.owner).isEmpty)
        try store.setFixedMemory(id: suggested.id, owner: fixed.owner, fixed: true)
        try check(try store.longTermRuleContext(owner: fixed.owner).contains("Keep test reports short"))

        var pinned = make("bot:c", "Use plain language")
        pinned.pinned = true
        _ = try store.save(pinned)
        let context = try store.recall(owner: "bot:c", query: "unrelated question")
        precondition(context.contains("Use plain language"))
        try check(try store.recall(owner: "bot:c", query: "unrelated", budget: 5).isEmpty)
        precondition(!BotMemoryStore.containsSecret("Browser passwords are stored in Keychain"))
        precondition(!BotMemoryStore.containsSecret("API key configuration uses environment variables"))
        precondition(BotMemoryStore.containsSecret("password=abc123-secret"))
        precondition(BotMemoryStore.containsSecret("API key: sk-abcdefghijklmnop"))
        precondition(BotMemoryStore.containsSecret("验证码是123456"))
        precondition(BotMemoryStore.containsSecret("BEGIN RSA PRIVATE KEY"))
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
        let recent = try store.longTermRuleContext(owner: "bot:recent")
        precondition(recent.contains("Pinned convention"))
        precondition(!recent.contains("Project note day 4") && !recent.contains("Project note day 6") && !recent.contains("Project note day 31"))
        precondition(!recent.contains("First fact"))
        func makeDatedEvent(_ text: String, kind: String, daysAgo: Int) -> BotMemoryEntry {
            var entry = makeEvent(text, kind: kind, source: "event-order-\(daysAgo)")
            entry.createdAt = dates.date(byAdding: .day, value: -daysAgo, to: now)!
            entry.updatedAt = entry.createdAt
            return entry
        }
        _ = try store.save(makeDatedEvent("November 3 event", kind: "decision", daysAgo: 1))
        _ = try store.save(makeDatedEvent("November 4 event", kind: "decision", daysAgo: 0))
        var longNote = make("bot:lines", (0..<250).map { "L\($0)" }.joined(separator: "\n"))
        longNote.createdAt = now
        // Store content limit remains enforced, so use short lines for the daily cap test.
        _ = try store.save(longNote)
        let clipped = try store.longTermRuleContext(owner: "bot:lines")
        precondition(clipped.isEmpty)

        // Event records are scoped milestones, not ordinary fingerprint-deduplicated notes.
        func makeEvent(_ text: String, kind: String?, source: String, assistant: String? = nil) -> BotMemoryEntry {
            var entry = BotMemoryEntry(owner: "bot:event", content: text, category: "event", scope: "work-log",
                                      sourceSession: "conversation", sourceMessage: source, evidence: "Fixed source snapshot")
            entry.eventKind = kind
            entry.sourceAssistantMessageID = assistant
            return entry
        }
        let decision = try store.save(makeEvent("Decided to keep iOS memory scoped", kind: "decision", source: "user-1"))
        precondition(decision.eventKind == "decision" && decision.sourceAssistantMessageID == nil)
        let sameTurnDecision = try store.save(makeEvent("Decided to keep iOS memory scoped", kind: "decision", source: "user-1", assistant: "assistant-1"))
        precondition(sameTurnDecision.id == decision.id)
        let delivery = try store.save(makeEvent("Bot report: delivery complete", kind: "delivery", source: "user-1", assistant: "assistant-1"))
        precondition(delivery.id != decision.id)
        let repeatDelivery = try store.save(makeEvent("Bot report: delivery complete", kind: "delivery", source: "user-2", assistant: "assistant-2"))
        precondition(repeatDelivery.id != delivery.id)
        do { _ = try store.save(makeEvent("Wrong kind", kind: "milestone", source: "-invalid")); precondition(false) }
        catch is BotMemoryError {}
        do { _ = try store.save(makeEvent("Missing kind", kind: nil, source: "-invalid")); precondition(false) }
        catch is BotMemoryError {}
        do {
            var nonEvent = make("bot:event", "Ordinary note")
            nonEvent.eventKind = "decision"
            _ = try store.save(nonEvent); precondition(false)
        } catch is BotMemoryError {}
        let eventReload = BotMemoryStore(fileURL: file)
        try check(try eventReload.visible(to: "bot:event").contains { $0.id == delivery.id && $0.eventKind == "delivery" })
        let legacyJSON = Data(#"{"id":"legacy-1","owner":"legacy:old","content":"Old row","category":"fact","scope":"legacy","evidence":"","createdAt":0,"updatedAt":0,"status":"active","automatic":false,"pinned":false,"grants":[],"fingerprint":"legacy"}"#.utf8)
        let legacyEntry = try JSONDecoder().decode(BotMemoryEntry.self, from: legacyJSON)
        precondition(legacyEntry.eventKind == nil && legacyEntry.sourceAssistantMessageID == nil)
        var injectedEvent = makeEvent("Injected decision", kind: "decision", source: "inject")
        injectedEvent.createdAt = now
        injectedEvent.updatedAt = now
        injectedEvent.pinned = true
        _ = try store.save(injectedEvent)
        let eventContext = try store.longTermRuleContext(owner: "bot:event")
        precondition(eventContext.contains("Injected decision") && eventContext.contains("Long-term rules (explicit user preferences):"))
        precondition(eventContext.components(separatedBy: "\n").filter { $0.contains("Injected decision") }.count == 1)
        precondition(!eventContext.contains("Events (recorded"))
        precondition(!eventContext.contains("Project note day"))
        precondition(!eventContext.contains("November 3 event") && !eventContext.contains("November 4 event"))
        let rulesContext = try store.longTermRuleContext(owner: "bot:recent")
        precondition(!rulesContext.contains("Project note day"), "Unpinned automatic notes must not be always-injected")
        let eventRecallOrder = try store.recall(owner: "bot:event", query: "")
        let newestRange = eventRecallOrder.range(of: "November 4 event")
        let olderEventRange = eventRecallOrder.range(of: "November 3 event")
        precondition(newestRange != nil && olderEventRange != nil && newestRange!.lowerBound < olderEventRange!.lowerBound,
                      "Event memory must be retrieved newest first")
        let eventRecall = try store.recall(owner: "bot:event", query: "交付")
        precondition(eventRecall.contains("· delivery/交付 ·"))
        print("PASS: SQLite owner isolation, persistence, sharing/revocation, replacement, forgotten-source suppression, bounded retrieval, multiple same-scope notes, rule injection, on-demand history and secret refusal")
    }
}

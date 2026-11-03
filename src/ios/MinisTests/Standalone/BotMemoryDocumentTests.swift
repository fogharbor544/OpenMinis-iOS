import Foundation

@main struct BotMemoryDocumentTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("memory-document-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("entries.sqlite")
        let store = BotMemoryStore(fileURL: url)
        var preference = BotMemoryEntry(owner: "bot:a", content: "Prefer concise replies", category: "preference", scope: "style", sourceSession: "chat", sourceMessage: "source", evidence: "User preference")
        preference.pinned = true; preference.grants = ["bot:b"]
        let first = try store.save(preference)
        _ = try store.save(BotMemoryEntry(owner: "bot:a", content: "Project alpha\n\nUses SwiftUI", category: "fact", scope: "project", evidence: ""))
        _ = try store.save(BotMemoryEntry(owner: "bot:b", content: "B private context", category: "fact", scope: "general", evidence: ""))
        var event = BotMemoryEntry(owner: "bot:a", content: "Bot report: memory event integration delivered", category: "event", scope: "work-log", sourceSession: "chat", sourceMessage: "event-source", evidence: "Assistant final reply")
        event.eventKind = "delivery"
        event.sourceAssistantMessageID = "assistant-source"
        event.grants = ["bot:b"]
        let savedEvent = try store.save(event)
        let baseline = try store.documentEntries(owner: "bot:a")
        let original = BotMemoryStore.documentText(baseline)
        precondition(original == "Prefer concise replies\n\nProject alpha\n\nUses SwiftUI\n\nBot report: memory event integration delivered")
        try store.saveDocument(owner: "bot:a", text: "Research context\n\n" + original, baseline: baseline)
        var document = try store.documentEntries(owner: "bot:a")
        precondition(document.first?.content == "Research context")
        let retained = document.first { $0.id == first.id }!
        let retainedEvent = document.first { $0.id == savedEvent.id }!
        precondition(retained.sourceMessage == "source" && retained.pinned && retained.grants == ["bot:b"])
        precondition(retainedEvent.eventKind == "delivery" && retainedEvent.sourceAssistantMessageID == "assistant-source")
        precondition(document.first?.grants.isEmpty == true, "New paragraphs stay private")
        precondition(document.contains { $0.content == "Project alpha\n\nUses SwiftUI" }, "Unchanged multiline notes retain their identity")
        // Similar appended paragraphs must never consume the existing event ID.
        let appended = original + "\n\nBot report: memory event integration delivered!"
        try store.saveDocument(owner: "bot:a", text: appended, baseline: document)
        document = try store.documentEntries(owner: "bot:a")
        precondition(document.count == 4 && Set(document.map(\.id)).count == 4)
        precondition(document.contains { $0.id == savedEvent.id && $0.content == event.content })
        precondition(document.contains { $0.id != savedEvent.id && $0.content == event.content + "!" && $0.grants.isEmpty })
        // Explicit identity preserves arbitrary edits, including multiline content.
        let editedContent = "Bot report: memory event integration hardened\n\nRegression checks added"
        try store.saveDocument(owner: "bot:a", text: "Prefer concise replies\n\nProject alpha\n\nUses SwiftUI",
                               baseline: document, eventEdits: [savedEvent.id: editedContent])
        document = try store.documentEntries(owner: "bot:a")
        let changedEvent = document.first { $0.id == savedEvent.id }
        precondition(changedEvent?.content == editedContent)
        precondition(changedEvent?.eventKind == "delivery" && changedEvent?.sourceAssistantMessageID == "assistant-source")
        precondition(changedEvent?.grants == ["bot:b"] && changedEvent?.createdAt == savedEvent.createdAt)
        do {
            try store.saveDocument(owner: "bot:a", text: "changed ordinary draft", baseline: document,
                                   eventEdits: [savedEvent.id: "password=not-for-memory"])
            fatalError("Stored secret event edit")
        } catch BotMemoryError.invalid { }
        let afterInvalidEvent = try store.documentEntries(owner: "bot:a")
        precondition(afterInvalidEvent == document, "Invalid event edits must not partially save the ordinary draft")
        do {
            try store.saveDocument(owner: "bot:a", text: "", baseline: document, eventEdits: [first.id: "wrong category"])
            fatalError("Accepted a non-event identity")
        } catch BotMemoryError.invalid { }
        let stale = document
        _ = try store.save(BotMemoryEntry(owner: "bot:a", content: "New automatic note", category: "fact", scope: "general", evidence: "", automatic: true))
        do { try store.saveDocument(owner: "bot:a", text: "stale draft", baseline: stale); fatalError("Overwrote concurrent memory") }
        catch BotMemoryError.invalid { }
        document = try store.documentEntries(owner: "bot:a")
        precondition(document.last?.content == "New automatic note")
        try store.saveDocument(owner: "bot:a", text: "Project alpha\n\nUses SwiftUI\n\nPrefer concise replies", baseline: document)
        document = try store.documentEntries(owner: "bot:a")
        precondition(document.first?.content == "Project alpha\n\nUses SwiftUI" && document.last?.id == first.id)
        precondition(!document.contains { $0.content == "Research context" })
        do { try store.saveDocument(owner: "bot:a", text: "password=secret-value", baseline: document); fatalError("Stored credential") }
        catch BotMemoryError.invalid { }
        let afterRejected = try store.documentEntries(owner: "bot:a")
        precondition(afterRejected == document)
        try store.setDocumentGrants(owner: "bot:a", baseline: document, grants: ["bot:c", "bot:c", "bot:a"])
        document = try store.documentEntries(owner: "bot:a")
        precondition(document.allSatisfy { $0.grants == ["bot:c"] })
        let visibleB = try store.visible(to: "bot:b")
        precondition(visibleB.count == 1 && visibleB[0].content == "B private context")
        let sourceZ = try store.save(BotMemoryEntry(owner: "bot:z", content: "Another source", category: "fact", scope: "general", evidence: "", grants: ["bot:c"]))
        let shared = try store.sharedDocumentEntries(to: "bot:c")
        precondition(BotMemoryStore.documentText(shared.filter { $0.owner == "bot:a" }) == BotMemoryStore.documentText(document))
        precondition(shared.map(\.owner) == ["bot:a", "bot:a", "bot:z"], "Shared documents must not interleave sources")
        try store.forget(id: sourceZ.id, owner: "bot:z")
        let reopened = BotMemoryStore(fileURL: url)
        let reloaded = try reopened.documentEntries(owner: "bot:a")
        precondition(reloaded == document, "Document order survives reload")
        try store.saveDocument(owner: "bot:a", text: "", baseline: document)
        let emptyDocument = try store.documentEntries(owner: "bot:a")
        let revoked = try store.visible(to: "bot:c")
        precondition(emptyDocument.isEmpty && revoked.isEmpty)
        let cleared = try store.entries().filter { $0.owner == "bot:a" }
        precondition(cleared.allSatisfy { $0.status == "deleted" && $0.content.isEmpty && $0.evidence.isEmpty && $0.grants.isEmpty })
        do { _ = try store.save(preference); fatalError("Automatically recreated forgotten source") }
        catch BotMemoryError.invalid { }
        print("PASS: combined document editing, stable order and reload, provenance/grants/pins retention, private additions, concurrent-write refusal, secret rejection, bulk sharing and forgotten-source suppression")
    }
}

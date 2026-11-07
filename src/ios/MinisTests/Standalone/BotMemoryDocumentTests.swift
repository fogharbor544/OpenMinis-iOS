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
        try checkCategoryEditors(store)
        print("PASS: combined document editing, stable order and reload, provenance/grants/pins retention, private additions, concurrent-write refusal, secret rejection, bulk sharing and forgotten-source suppression")
    }

    @MainActor private static func checkCategoryEditors(_ store: BotMemoryStore) throws {
        let owner = "bot:category-editors"
        var fixed = BotMemoryEntry(owner: owner, content: "Keep replies brief", category: "preference",
                                   scope: "style", evidence: "User rule", pinned: true, grants: ["bot:reader"])
        fixed.documentOrder = 4
        let savedFixed = try store.save(fixed)
        var ordinary = BotMemoryEntry(owner: owner, content: "Uses SwiftUI", category: "fact",
                                      scope: "project", evidence: "User fact", automatic: true, pinned: true,
                                      grants: ["bot:reader"])
        ordinary.documentOrder = 5
        let savedOrdinary = try store.save(ordinary)
        var event = BotMemoryEntry(owner: owner, content: "Decided to ship category editors", category: "event",
                                  scope: "delivery", sourceSession: "chat", sourceMessage: "turn",
                                  evidence: "User decision", grants: ["bot:reader"])
        event.eventKind = "decision"
        event.sourceAssistantMessageID = "reply"
        let savedEvent = try store.save(event)
        precondition(savedFixed.memorySection == .fixed)
        precondition(savedOrdinary.memorySection == .ordinary, "Automatic pins are not explicit fixed memories")
        precondition(savedEvent.memorySection == .facts, "The fact tab presents event records")
        var legacyFixedEvent = savedEvent
        legacyFixedEvent.pinned = true
        precondition(legacyFixedEvent.memorySection == .fixed, "Legacy fixed entries belong to exactly one tab")

        // An unrelated automatic addition must not prevent saving the open fixed editor.
        let fixedBaseline = try store.documentEntries(owner: owner).filter { $0.memorySection == .fixed }
        let automaticAddition = try store.save(BotMemoryEntry(owner: owner, content: "Prefers metric units", category: "preference",
                                                              scope: "units", evidence: "User preference", automatic: true))
        let beforeFixed = try store.documentEntries(owner: owner)
        try store.saveDocument(owner: owner, text: "", baseline: fixedBaseline,
                               fixedEdits: [savedFixed.id: "Use concise replies"], section: .fixed)
        var document = try store.documentEntries(owner: owner)
        precondition(document.filter { $0.memorySection != .fixed } == beforeFixed.filter { $0.memorySection != .fixed })
        precondition(document.first { $0.id == savedFixed.id }?.grants.isEmpty == true)
        precondition(store.lastSaved == automaticAddition, "Saving fixed memories preserves the unrelated addition's Undo banner")

        // Ordinary text equal to a fixed rule must not consume that rule's identity.
        let ordinaryBaseline = document.filter { $0.memorySection == .ordinary }
        let outsideOrdinary = document.filter { $0.memorySection != .ordinary }
        try store.saveDocument(owner: owner, text: "", baseline: ordinaryBaseline,
                               ordinaryEdits: Dictionary(uniqueKeysWithValues: ordinaryBaseline.map {
                                   ($0.id, $0.content + "\n\nUse concise replies")
                               }), section: .ordinary)
        document = try store.documentEntries(owner: owner)
        precondition(document.filter { $0.memorySection != .ordinary } == outsideOrdinary)
        precondition(document.contains { $0.id != savedFixed.id && $0.content.hasSuffix("Use concise replies") && $0.memorySection == .ordinary })
        let retainedOrdinary = document.first { $0.id == savedOrdinary.id }!
        precondition(retainedOrdinary.content.hasPrefix(savedOrdinary.content) && retainedOrdinary.grants == savedOrdinary.grants)
        precondition(retainedOrdinary.createdAt == savedOrdinary.createdAt && retainedOrdinary.automatic && retainedOrdinary.pinned)
        precondition(store.lastSaved == nil, "Saving the addition's own category clears its old Undo snapshot")

        let perEntryOrdinary = document.filter { $0.memorySection == .ordinary }
        let perEntryOutside = document.filter { $0.memorySection != .ordinary }
        do {
            try store.saveDocument(owner: owner, text: "", baseline: perEntryOrdinary,
                                   ordinaryEdits: [savedFixed.id: "Wrong category"], section: .ordinary)
            fatalError("Accepted a fixed memory ID as an ordinary entry")
        } catch BotMemoryError.invalid { }
        do {
            try store.saveDocument(owner: owner, text: "", baseline: perEntryOrdinary,
                                   ordinaryEdits: [savedOrdinary.id: "password=secret-value"], section: .ordinary)
            fatalError("Accepted a secret in an ordinary entry")
        } catch BotMemoryError.invalid { }
        let afterRejectedOrdinary = try store.documentEntries(owner: owner)
        precondition(afterRejectedOrdinary == document, "Rejected per-entry ordinary edits are atomic")
        try store.saveDocument(owner: owner, text: "", baseline: perEntryOrdinary,
                               ordinaryEdits: [savedOrdinary.id: "Uses SwiftUI and Swift 6"], section: .ordinary)
        document = try store.documentEntries(owner: owner)
        let editedOrdinary = document.first { $0.id == savedOrdinary.id }!
        precondition(editedOrdinary.content == "Uses SwiftUI and Swift 6")
        precondition(editedOrdinary.createdAt == savedOrdinary.createdAt
                     && editedOrdinary.grants == savedOrdinary.grants
                     && editedOrdinary.automatic && editedOrdinary.pinned)
        precondition(document.filter { $0.memorySection != .ordinary } == perEntryOutside,
                     "Per-entry ordinary edits leave other categories unchanged")

        let factBaseline = document.filter { $0.memorySection == .facts }
        let outsideFacts = document.filter { $0.memorySection != .facts }
        do {
            try store.saveDocument(owner: owner, text: "", baseline: factBaseline,
                                   eventEdits: [savedEvent.id: "password=not-for-memory"], section: .facts)
            fatalError("Accepted a secret in a category editor")
        } catch BotMemoryError.invalid { }
        let afterInvalid = try store.documentEntries(owner: owner)
        precondition(afterInvalid == document, "Rejected category edits are atomic")
        try store.saveDocument(owner: owner, text: "", baseline: factBaseline,
                               eventEdits: [savedEvent.id: "Decided to ship\n\nCategory editors verified"], section: .facts)
        document = try store.documentEntries(owner: owner)
        let changedEvent = document.first { $0.id == savedEvent.id }!
        precondition(document.filter { $0.memorySection != .facts } == outsideFacts)
        precondition(changedEvent.eventKind == savedEvent.eventKind && changedEvent.sourceMessage == savedEvent.sourceMessage)
        precondition(changedEvent.sourceAssistantMessageID == "reply" && changedEvent.grants == savedEvent.grants)
        precondition(changedEvent.createdAt == savedEvent.createdAt)

        // Each category's clear operation leaves all remaining categories byte-for-byte equivalent.
        for section in [BotMemorySection.facts, .ordinary, .fixed] {
            let baseline = document.filter { $0.memorySection == section }
            let untouched = document.filter { $0.memorySection != section }
            try store.saveDocument(owner: owner, text: "", baseline: baseline, section: section)
            document = try store.documentEntries(owner: owner)
            precondition(document == untouched)
        }
        let tombstones = try store.entries().filter { $0.owner == owner }
        precondition(tombstones.allSatisfy { $0.status == "deleted" && $0.content.isEmpty && $0.grants.isEmpty })

        // A new entry in the edited category still invalidates its stale baseline.
        _ = try store.save(BotMemoryEntry(owner: owner, content: "New ordinary note", category: "fact", scope: "new", evidence: ""))
        do {
            try store.saveDocument(owner: owner, text: "Stale draft", baseline: [], section: .ordinary)
            fatalError("Overwrote an update in the selected category")
        } catch BotMemoryError.invalid { }
        let afterConflict = try store.documentEntries(owner: owner)
        precondition(afterConflict.count == 1 && afterConflict[0].content == "New ordinary note")
        precondition(store.lastSaved == afterConflict[0], "Rejected saves preserve the new memory's Undo banner")
        try store.saveDocument(owner: owner, text: "", baseline: afterConflict, section: .ordinary)
        precondition(store.lastSaved == nil, "Deleting the recent memory clears its Undo banner")

        let otherOwner = try store.save(BotMemoryEntry(owner: "bot:other-category-editor", content: "Use short reports",
                                                      category: "preference", scope: "style", evidence: ""))
        try store.saveDocument(owner: owner, text: "Fresh document", baseline: [])
        precondition(store.lastSaved == otherOwner, "Whole-document saves also preserve another owner's Undo banner")
        try store.forget(id: otherOwner.id, owner: otherOwner.owner)
        precondition(store.lastSaved == nil, "The preserved Undo action can still forget its own entry")
        print("PASS: category-isolated edits/deletions, concurrent unrelated additions, scoped Undo state, event provenance, private fixed edits, secret rejection and same-category conflict refusal")
    }
}

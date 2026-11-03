# Bot Event Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add scoped event memories so Bots can retain and recall decisions, deliveries, and verification reports without replaying private history.

**Architecture:** Extend the existing scoped SQLite BotMemoryStore with an optional `eventKind` and event source fields, expose event support through the existing `memory_write` schema and automatic review pipeline, and render bounded event context through existing memory injection/retrieval and Memory document UI. Do not create a second storage system or global Markdown logs.

**Tech Stack:** Swift/SwiftUI, raw SQLite3, XCTest-style standalone harnesses, existing BotWorkspaceStore/BotMemoryStore.

**Spec:** Revised plan in `docs/superpowers/plans/2026-11-03-bot-event-memory.md`.

## Global Constraints

- Store remains `memories(id, owner, payload)` in `Library/MinisBotMemory/entries.sqlite`; no new table or schema migration.
- `eventKind` and source IDs are optional fields, so old JSON payloads must decode.
- Categories are `preference`, `fact`, `convention`, `experience`, plus `event`.
- Event kinds are `decision`, `delivery`, `verification`.
- `category=event` requires a valid `eventKind`; non-event categories require `eventKind == nil`.
- `createdAt` means recorded time, never event occurrence time.
- Event injection budget is 10 entries and 2400 characters.
- Event sharing uses existing explicit grants; default remains private.
- Do not modify Android.

## Review Focus

- Old JSON payloads missing new optional fields must still decode after database reopen.
- Editing unaffected document paragraphs must not reconstruct events as plain facts.
- Automatic event extraction must not falsely assert independent verification when evidence is only the assistant's report.
- Normal date-group injection and Events injection must not duplicate events.
- Event deduplication must preserve repeated events across distinct source turns while suppressing retries from one source.
- Memory tool schema and automatic review normalization must both retain `event_kind`.

---

### Task 1: Event model, validation, deduplication, and persistence

**Files:**
- Modify: `src/ios/Views/ContentView/Bots/BotMemoryStore.swift`
- Test: `src/ios/MinisTests/Standalone/BotMemoryEntryTests.swift`

**Interfaces:**
- Produces: `BotMemoryEntry.eventKind: String?`, `sourceAssistantMessageID: String?`, event category/kind validation, event-specific deduplication, old-payload decoding.

- [ ] Write failing tests for event save, invalid category/kind combinations, distinct-turn event deduplication, same-source retry deduplication, and mixed old/new payload reopen.

- [ ] Implement only the model field, validation, and event deduplication changes needed to pass the tests.

- [ ] Run `swift src/ios/MinisTests/Standalone/BotMemoryEntryTests.swift`; expected RED before implementation, GREEN after.

- [ ] Commit: `feat: add scoped event memory records`

### Task 2: Tool schema and write execution

**Files:**
- Modify: `src/ios/Agent/Chat/AIChatViewModel+ToolDefinitions.swift`
- Modify: `src/ios/Views/ContentView/Bots/AIChatViewModel+BotMemory.swift`
- Test: `src/ios/MinisTests/Standalone/BotMemoryRuntimeTests.swift`

**Interfaces:**
- Consumes: event model from Task 1.
- Produces: real `memory_write` category `event` and optional `event_kind`; executor preserves category/kind/source and reject semantics.

- [ ] Write failing tests proving real schema exposes event category/kind and `executeBotMemoryWrite` enforces those semantics.

- [ ] Implement schema and write execution changes.

- [ ] Run `swift src/ios/MinisTests/Standalone/BotMemoryRuntimeTests.swift`; expected RED then GREEN.

- [ ] Commit: `feat: expose event memory writes`

### Task 3: Automatic event review and source pairing

**Files:**
- Modify: `src/ios/Views/ContentView/Bots/AIChatViewModel+BotMemory.swift`
- Modify: `src/ios/Agent/Chat/AIChatViewModel+AgentLoop.swift`
- Test: `src/ios/MinisTests/Standalone/BotMemoryRuntimeTests.swift`

**Interfaces:**
- Consumes: event schema from Task 2.
- Produces: bounded automatic review that saves at most one event plus one conventional memory, with fixed user/assistant source and verification semantics.

- [ ] Write failing tests for quota enforcement, source stability, assistant-secret rejection, `verification` evidence gating, and preserving event review after ordinary memory writes.

- [ ] Implement review prompt, normalization, source pairing, state separation, and semantic gates.

- [ ] Run `swift src/ios/MinisTests/Standalone/BotMemoryRuntimeTests.swift`; expected RED then GREEN.

- [ ] Commit: `feat: auto-remember scoped work events`

### Task 4: Context injection and retrieval

**Files:**
- Modify: `src/ios/Views/ContentView/Bots/BotMemoryStore.swift`
- Modify: `src/ios/Views/ContentView/Bots/BotMemoryView.swift`
- Test: `src/ios/MinisTests/Standalone/BotMemoryDocumentTests.swift`
- Test: `src/ios/MinisTests/Standalone/BotMemoryRuntimeTests.swift`

**Interfaces:**
- Consumes: event records from Task 1 and executor output from Task 2.
- Produces: bounded `Events:` context, event-aware recall, and UI display without document-format identity loss.

- [ ] Write failing tests for non-duplicated bounded event context, event-aware recall, and document editing preserving event identity/grants/source metadata.

- [ ] Implement injection, retrieval, and display.

- [ ] Run `swift src/ios/MinisTests/Standalone/BotMemoryDocumentTests.swift` and `swift src/ios/MinisTests/Standalone/BotMemoryRuntimeTests.swift`; expected RED then GREEN.

- [ ] Commit: `feat: recall bounded event memories`

### Task 5: Whole-feature review and verification

**Files:**
- Modify: none unless review identifies a defect.
- Test: all standalone Bot memory suites.

- [ ] Run Bot memory standalone suites and targeted source checks; fix failing behavior with RED→GREEN tests only.

- [ ] Dispatch fresh whole-branch review with the most capable available model, fix all Critical/Important findings, and ledger rulings/minors.

- [ ] Final commit only if fixes were needed: `fix: harden event memory behavior`

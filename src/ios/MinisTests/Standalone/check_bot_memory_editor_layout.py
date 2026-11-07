"""Guard the three Bot memory editors against diverging into a single text draft."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
view = (ROOT / "Views/ContentView/Bots/BotMemoryView.swift").read_text(encoding="utf-8")
store = (ROOT / "Views/ContentView/Bots/BotMemoryStore.swift").read_text(encoding="utf-8")
tests = (ROOT / "MinisTests/Standalone/BotMemoryDocumentTests.swift").read_text(encoding="utf-8")
overview = view.split("private struct BotMemoryDocumentEditor", 1)[0]
editor = view.split("private struct BotMemoryDocumentEditor", 1)[1].split(
    "private struct BotMemoryDocumentSharing", 1
)[0]

assert "@State private var forgetting: BotMemoryEntry?" in overview
assert overview.count("List {") == 1
assert ".listStyle(.plain)" in overview
assert ".scrollDisabled(true)" not in overview
assert ".frame(height: min(CGFloat(displayedEntries.count) * 88, 600))" not in overview
assert overview.count('.swipeActions(edge: .trailing, allowsFullSwipe: false)') == 1
assert 'Button(role: .destructive) { forgetting = entry }' in overview
assert ".disabled(!available)" in overview
assert 'Label("Delete", systemImage: "trash")' in overview
assert 'Button { toggleFixed(entry) }' in overview
assert 'Label(entry.isFixedMemory ? "Unpin" : "Pin"' in overview
assert "Image(systemName: entry.isFixedMemory ? \"pin.slash\" : \"pin\")" not in overview
assert '.confirmationDialog("Forget"' in overview
assert 'Button("Forget", role: .destructive) { forgetSelected() }' in overview
assert "private func toggleFixed(_ entry: BotMemoryEntry)" in overview
assert "private func forgetSelected()" in overview
assert "store.forget(id: entry.id, owner: owner)" in overview

assert "@State private var draft: String" not in editor
assert "TextEditor(text: $draft)" not in editor
assert editor.count("ForEach(baseline) { entry in") == 1
assert editor.count("TextEditor(text: Binding(get: { entryDrafts[entry.id] ?? \"\" }") == 1
assert "newOrdinaryDrafts" not in editor
assert "添加记忆" not in editor
assert 'let ordinaryEdits = section == .ordinary ? entryDrafts : [:]' in editor
assert 'fixedEdits: entryDrafts.filter { !events.contains($0.key) && section == .fixed }' in editor
assert 'ordinaryEdits: ordinaryEdits, section: section' in editor
assert "section: section" in editor
assert "ordinaryEdits: [String: String] = [:]" in store
assert "guard ordinaryEdits.keys.allSatisfy" in store
assert "ordinaryAdditions" not in store
assert "if section != nil && !individualEdits.isEmpty { remaining = \"\" }" in store
assert "ordinaryEdits: Dictionary(uniqueKeysWithValues: ordinaryBaseline.map" in tests
assert "ordinaryAdditions" not in tests
print("PASS: ordinary, fixed and fact memories use per-entry editors and ID-scoped saves")

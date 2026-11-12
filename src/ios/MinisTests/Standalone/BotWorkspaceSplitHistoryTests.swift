import Foundation

@main struct BotWorkspaceSplitHistoryTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("workspace.json")
        let bot = BotProfile(name: "Fixture")
        var first = BotRoom(name: "First", members: [bot.id])
        var second = BotRoom(name: "Second", members: [bot.id])
        first.messages = [BotRoomMessage(speaker: "User", text: "first history")]
        second.messages = [BotRoomMessage(speaker: "User", text: "second history")]
        let legacy = BotWorkspaceData(bots: [bot], rooms: [first, second])
        try JSONEncoder().encode(legacy).write(to: file)
        let store = BotWorkspaceStore(fileURL: file, seedCommander: false)
        precondition(store.data == legacy)
        precondition(store.persist(legacy))
        let migrated = try BotWorkspaceDisk.read(file)
        precondition(migrated == legacy)
        let directory = BotWorkspaceDisk.historyDirectory(for: file)
        let before = try fm.contentsOfDirectory(atPath: directory.path).sorted()
        precondition(before.count == 2)
        let metadata = try JSONDecoder().decode(BotWorkspaceData.self, from: Data(contentsOf: file))
        precondition(metadata.rooms.allSatisfy { $0.messages.isEmpty })
        var renamed = bot
        renamed.name = "Updated"
        precondition(store.save(renamed))
        let unchanged = try fm.contentsOfDirectory(atPath: directory.path).sorted()
        precondition(unchanged == before)
        precondition(store.append(BotRoomMessage(speaker: "User", text: "new"), to: first.id))
        let after = try fm.contentsOfDirectory(atPath: directory.path)
        precondition(Set(after).intersection(before).count == 1)
        let snapshot = try store.dataForBackup()
        precondition(snapshot.rooms[0].messages.count == 2 && snapshot.rooms[1].messages.count == 1)
        do { let loaded = try BotWorkspaceDisk.read(file); precondition(loaded == snapshot) }
        // Fail before publication; the previous metadata and histories survive.
        let moved = root.appendingPathComponent("saved-history")
        try fm.moveItem(at: directory, to: moved)
        try Data().write(to: directory)
        precondition(!store.append(BotRoomMessage(speaker: "User", text: "must fail"), to: first.id))
        precondition(store.data == snapshot)
        try fm.removeItem(at: directory)
        try fm.moveItem(at: moved, to: directory)
        do { let loaded = try BotWorkspaceDisk.read(file); precondition(loaded == snapshot) }
        // Fail after the new generation is written but before the index is replaced.
        enum InjectedFailure: Error { case publish }
        let priorIndex = try Data(contentsOf: file)
        let priorGenerations = Set(try fm.contentsOfDirectory(atPath: directory.path))
        var unpublished = snapshot
        unpublished.rooms[0].messages.append(BotRoomMessage(speaker: "User", text: "unpublished"))
        do {
            try BotWorkspaceDisk.write(unpublished, previous: snapshot, to: file) { _, target in
                precondition(target == file)
                let staged = Set(try fm.contentsOfDirectory(atPath: directory.path))
                precondition(staged.isSuperset(of: priorGenerations))
                precondition(staged.subtracting(priorGenerations).count == 1)
                throw InjectedFailure.publish
            }
            preconditionFailure("Index publication should fail")
        } catch InjectedFailure.publish {}
        let restoredIndex = try Data(contentsOf: file)
        let retainedGenerations = Set(try fm.contentsOfDirectory(atPath: directory.path))
        let reloaded = try BotWorkspaceDisk.read(file)
        precondition(restoredIndex == priorIndex && retainedGenerations == priorGenerations)
        precondition(reloaded == snapshot)
        // Restore and rollback both pass through the same durable writer.
        precondition(store.persist(legacy))
        do { let restored = try BotWorkspaceDisk.read(file); precondition(restored == legacy) }
        precondition(store.persist(snapshot))
        do { let rolledBack = try BotWorkspaceDisk.read(file); precondition(rolledBack == snapshot) }
        let historyNames = try fm.contentsOfDirectory(atPath: directory.path).sorted()
        try BotWorkspaceDisk.updateMetadata(at: file, fallback: snapshot) { metadata in
            metadata.conversationStates["fixture"] = BotConversationState()
            return true
        }
        let afterMetadata = try fm.contentsOfDirectory(atPath: directory.path).sorted()
        precondition(afterMetadata == historyNames)
        // Missing referenced history fails closed, rather than publishing empty history.
        try fm.removeItem(at: directory.appendingPathComponent(historyNames[0]))
        let damaged = BotWorkspaceStore(fileURL: file, seedCommander: false)
        precondition(damaged.errorMessage != nil)
        precondition(!damaged.save(bot))
        print("PASS: legacy migration, history reuse, changed-room isolation, backup snapshot, failure rollback, missing-history refusal")
    }
}

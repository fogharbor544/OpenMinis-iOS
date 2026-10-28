import Foundation

@MainActor enum BiometricAuth {
    static func authenticate(reason: String) async -> Bool { false }
}
@MainActor final class SessionLockStore {
    static let shared = SessionLockStore()
    var locked = false
    func isVisuallyLocked(_ id: String) -> Bool { locked }
    func noteUnlock(_ id: String) { locked = false }
}
enum Submission: Equatable { case accepted, queued, rejected(String) }
enum Origin { case job(jobId: String) }
struct TestMessage {
    enum Role { case assistant }
    var id = UUID()
    var role = Role.assistant
    var content: String
    var error: String?
}
struct QueuedPrompt { var id: String }
@MainActor final class AIChatViewModel {
    static var prompts: [String] = []
    static var hold = false
    static var fail = false
    var isProcessing = false
    var isCompacting = false
    var messages: [TestMessage] = []
    var errorMessage: String?
    var promptQueue: [QueuedPrompt] = []
    func loadSession() async {}
    func cancel() { isProcessing = false }
    func submitProgrammaticPrompt(_ text: String, origin: Origin, silent: Bool, bypassContextPrompt: Bool) -> Submission {
        Self.prompts.append(text)
        isProcessing = true
        return .accepted
    }
    func awaitProgrammaticTurn(queuedPromptId: String?) async -> Bool {
        while Self.hold && !Task.isCancelled { await Task.yield() }
        defer { isProcessing = false }
        if Task.isCancelled { return false }
        if Self.fail { errorMessage = "Injected runtime failure" }
        else { messages.append(TestMessage(content: "Reply \(Self.prompts.count)")) }
        return true
    }
}
@MainActor final class ViewModelCache {
    static let shared = ViewModelCache()
    var models: [String: AIChatViewModel] = [:]
    func getOrCreate(for id: String) -> (AIChatViewModel, Bool) {
        if let model = models[id] { return (model, false) }
        let model = AIChatViewModel()
        models[id] = model
        return (model, true)
    }
}
extension BotWorkspaceStore {
    func session(botID: String, roomID: String?) async throws -> String {
        "\(roomID ?? "private")/\(botID)"
    }
}

@main struct BotRoomRunnerBehaviorTests {
    @MainActor static func main() async {
        let store = BotWorkspaceStore.shared
        let a = BotProfile(name: "Alpha")
        let b = BotProfile(name: "Beta")
        precondition(store.save(a) && store.save(b))
        let room = BotRoom(name: "Team", members: [a.id, b.id])
        precondition(store.save(room))
        let runner = BotRoomRunner.shared
        func finish() async {
            while runner.activeRooms.contains(room.id) { await Task.yield() }
        }
        runner.send("Collaborate", roomID: room.id, recipient: nil)
        runner.send("Duplicate while running", roomID: room.id, recipient: nil)
        await finish()
        let messages = store.room(room.id)!.messages
        precondition(messages.map(\.speaker) == [String(localized: "You"), "Alpha", "Beta"])
        precondition(AIChatViewModel.prompts.count == 2)
        precondition(AIChatViewModel.prompts[1].contains("Alpha: Reply 1"))
        precondition(messages[1].sessionId == "\(room.id)/\(a.id)")
        precondition(store.room(room.id)?.interrupted == false)
        runner.send("Only Beta", roomID: room.id, recipient: b.id)
        await finish()
        precondition(AIChatViewModel.prompts.count == 3 && store.room(room.id)?.messages.last?.botId == b.id)
        runner.send("Invalid member", roomID: room.id, recipient: "absent")
        precondition(!runner.activeRooms.contains(room.id))
        AIChatViewModel.fail = true
        runner.send("Fail first member", roomID: room.id, recipient: nil)
        await finish()
        precondition(AIChatViewModel.prompts.count == 4)
        precondition(store.room(room.id)?.messages.last?.text == "Injected runtime failure")
        AIChatViewModel.fail = false
        AIChatViewModel.hold = true
        runner.send("Stop round", roomID: room.id, recipient: nil)
        while AIChatViewModel.prompts.count < 5 { await Task.yield() }
        runner.stop(room.id)
        await finish()
        precondition(AIChatViewModel.prompts.count == 5)
        precondition(store.room(room.id)?.interrupted == false && runner.speakers.isEmpty)
        SessionLockStore.shared.locked = true
        runner.send("Locked conversation", roomID: room.id, recipient: nil)
        await finish()
        precondition(AIChatViewModel.prompts.count == 5)
        precondition(store.room(room.id)?.messages.last?.text == String(localized: "The Bot conversation is locked."))
        print("PASS: shipping group runner ordered handoff, recipient selection, duplicate submission, failure, cancellation and locked-session refusal")
    }
}

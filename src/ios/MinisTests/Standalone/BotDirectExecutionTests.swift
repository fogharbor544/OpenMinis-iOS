import Foundation

extension ChatStore {
    func sessionExists(id: String) -> Bool { id == "parent" || sessions[id] != nil }
}

@MainActor final class UIApplication {
    enum State { case active }
    static let shared = UIApplication()
    var applicationState = State.active
}
@MainActor final class UserAskCenter {
    static let shared = UserAskCenter()
    var hasWaitingCalls = false
    var waiting: Set<String> = []
    func isAwaitingUserInteraction(inSession sid: String) -> Bool { waiting.contains(sid) }
}
@MainActor final class SessionActivityTracker {
    static let shared = SessionActivityTracker()
    var activeSessions: Set<String> = []
}
@MainActor final class BotRoomRunner {
    static let shared = BotRoomRunner()
    var activeRooms: Set<String> = []
}
@MainActor final class BotMemoryStore {
    static let shared = BotMemoryStore()
    var hasPendingReviews = false
}
@MainActor final class SyncCore {
    static let shared = SyncCore()
    func holdInboundForBotRestore() async {}
}

enum ProgrammaticPromptOrigin { case job(jobId: String) }
enum ProgrammaticSubmitOutcome: Equatable { case sent, queued, rejected(reason: String) }
struct AgentCallback {
    enum Kind { case finished }
    var kind: Kind; var jobId: String; var childSessionId: String?
    var title: String; var status: String
    var tier: String?; var elapsed: String?; var tool: String?; var activity: String?; var turn: String?
    var summary: String; var body: String; var siblings: String?; var modelIdentity: String?; var agent: String?
    var xml: String { "Result from \(agent ?? "Bot"): \(status): \(body)" }
}
struct TestBlock {
    enum Kind { case text }
    var kind = Kind.text
    var content: String
    var toolStatus = "done"
}
struct TestMessage {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role; var content: String
    var blocks: [TestBlock] = []
    var error: String?
    var agentCallback: AgentCallback?
}
struct TestJob {
    enum Origin { case tool }
    enum State { case running, pending, done }
    enum Then { case none, followUpParent(template: String?) }
    struct Target { var parentSessionId: String? }
    var id: String; var origin = Origin.tool; var state = State.done
    var then = Then.none; var target: Target
}
@MainActor final class AgentJobRegistry {
    static let shared = AgentJobRegistry()
    static let maxQueuedDelegationsPerParent = 16
    var hasPendingSpecialistStop = false
    func stopSubAgentByUser(childSessionId: String, reason: String) -> Int { 0 }
    func cancel(jobId: String, reason: String) { fatalError("A direct Bot must not be a child job") }
    func queuedCount(parent: String) -> Int { 0 }
    func list() -> [TestJob] { [] }
}
@MainActor final class AIChatViewModel {
    enum ToolSwitch { case agents }
    static var holdAnswers = false
    static var resumableReply = false
    static var holdCancellationCleanup = false
    static var cleanupContinuation: CheckedContinuation<Void, Never>?
    static var agentsEnabled = true
    static func toolEnabled(_ value: ToolSwitch) -> Bool { agentsEnabled }
    static func jsonString(_ value: [String: Any]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
    var sessionId: String?
    var isHelper = false
    var helperConfig: String?
    var programmaticTurnOrigin: ProgrammaticPromptOrigin?
    var isProcessing = false
    var isCompacting = false
    var canResume = false
    var userDidCancel = false
    var delegationResultsAreMuted = false
    var errorMessage: String?
    var currentTask: Task<Void, Never>?
    var messages: [TestMessage] = []
    var pendingSteerMessages: [String] = []
    var callbacks: [String] = []
    var submitted: [String] = []
    var cancelCount = 0
    func loadSession() async {}
    func submitProgrammaticPrompt(_ text: String, origin: ProgrammaticPromptOrigin, silent: Bool, bypassContextPrompt: Bool) -> ProgrammaticSubmitOutcome {
        if isCommander { callbacks.append(text); return .sent }
        precondition(helperConfig == nil && !isHelper, "Target must use its normal Bot runtime")
        precondition(isDirectBotConversation && botDelegationPolicy.contains("responsible Bot"))
        submitted.append(text)
        messages.append(TestMessage(role: .user, content: text))
        programmaticTurnOrigin = origin; userDidCancel = false; isProcessing = true
        canResume = false; errorMessage = nil
        currentTask = Task { @MainActor in
            do {
                while Self.holdAnswers { try await Task.sleep(nanoseconds: 5_000_000) }
                try Task.checkCancellation()
                var response = TestMessage(role: .assistant, content: "Verified target Bot result")
                if Self.resumableReply { self.canResume = true; response.error = "Reached tool round cap" }
                self.messages.append(response)
            } catch {
                if Self.holdCancellationCleanup { await withCheckedContinuation { Self.cleanupContinuation = $0 } }
            }
            self.isProcessing = false
        }
        return .sent
    }
    func awaitProgrammaticTurn(queuedPromptId: UUID?) async -> Bool { await currentTask?.value; return !Task.isCancelled }
    func cancel() {
        cancelCount += 1
        BotTeamRuntime.shared.targetWillStop(sessionID: sessionId!, turn: currentTask)
        userDidCancel = true; currentTask?.cancel(); isProcessing = false
    }
}
@MainActor final class ViewModelCache {
    static let shared = ViewModelCache()
    var models: [String: AIChatViewModel] = [:]
    func get(for id: String) -> AIChatViewModel? { models[id] }
    func getOrCreate(for id: String) -> (vm: AIChatViewModel, fresh: Bool) {
        if let vm = models[id] { return (vm, false) }
        let vm = AIChatViewModel(); vm.sessionId = id; models[id] = vm
        return (vm, true)
    }
}
@main struct BotDirectExecutionTests {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<1500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        fatalError("Timed out waiting for direct Bot lifecycle")
    }
    @MainActor static func main() async throws {
        let store = BotWorkspaceStore.shared
        var commander = store.bot(BotProfile.commanderID)!
        commander.sessionId = "parent"; commander.conversationIds = ["parent"]
        precondition(store.save(commander))
        var workspace = store.data
        workspace.sessionOwners["parent"] = BotSessionOwner(botId: commander.id)
        precondition(store.persist(workspace))
        var target = store.newBot(); target.name = "Research Bot"; target.modelGroupId = "alternate"
        target.instructions = "Verify primary sources"; precondition(store.save(target))
        let privateID = try await store.session(botID: target.id)
        let parent = ViewModelCache.shared.getOrCreate(for: "parent").vm
        func delegate(_ call: String) throws -> String {
            let outcome = parent.executeBotTask(["action": "delegate", "bot_id": target.id, "task": "Verify the provided source context"], toolUseID: call)
            precondition(outcome.success, "Delegation \(call) rejected: \(outcome.output)")
            return (try JSONSerialization.jsonObject(with: Data(outcome.output.utf8)) as! [String: Any])["delegation_id"] as! String
        }
        let first = try delegate("direct-1")
        try await wait { store.delegation(first)?.state == .reviewing && parent.callbacks.count == 1 }
        let record = store.delegation(first)!
        let sid = record.childSessionID!
        precondition(record.directExecution == true && record.jobID == nil && record.result == "Verified target Bot result")
        precondition(store.owner(forSession: sid) == BotSessionOwner(botId: target.id, delegationID: first))
        precondition(sid != privateID && store.bot(target.id)?.conversationIds == [privateID])
        guard case .group(let groupID, _) = ProviderConfigStore.shared.bindings[sid]?.primarySource else { fatalError("Missing target binding") }
        precondition(groupID == "alternate")
        let vm = ViewModelCache.shared.get(for: sid)!
        precondition(vm.helperConfig == nil && vm.submitted.first?.hasPrefix("消息来自 \(commander.name)\n\n") == true)
        precondition(parent.callbacks[0].contains(target.name) && parent.callbacks[0].contains(record.result!))
        precondition(parent.executeBotTask(["action": "complete", "delegation_id": first], toolUseID: "review").success)
        precondition(store.delegation(first)?.state == .completed)
        precondition(parent.executeBotTask(["action": "follow_up", "delegation_id": first, "message": "Add original dates"], toolUseID: "rework").success)
        try await wait { store.delegation(first)?.state == .reviewing && parent.callbacks.count == 2 }
        precondition(store.delegation(first)?.childSessionID == sid && vm.submitted.count == 2)
        AIChatViewModel.holdAnswers = true
        let second = try delegate("direct-2")
        try await wait { store.delegation(second)?.state == .running && ViewModelCache.shared.get(for: store.delegation(second)!.childSessionID!)?.isProcessing == true }
        let running = ViewModelCache.shared.get(for: store.delegation(second)!.childSessionID!)!
        precondition(parent.executeBotTask(["action": "follow_up", "delegation_id": second, "message": "Use official sources"], toolUseID: "steer").success)
        precondition(running.pendingSteerMessages.first?.contains("Use official sources") == true)
        let third = try delegate("direct-3")
        precondition(store.delegation(third)?.state == .queued)
        AIChatViewModel.holdAnswers = false
        precondition(parent.executeBotTask(["action": "cancel", "delegation_id": second], toolUseID: "cancel").success)
        try await wait { store.delegation(third)?.state == .reviewing }
        precondition(running.cancelCount == 1 && store.delegation(second)?.state == .cancelled)
        precondition(store.bot(target.id)?.sessionId == privateID)
        AIChatViewModel.holdAnswers = true
        let waitingTask = try delegate("waiting-user")
        try await wait { store.delegation(waitingTask)?.state == .running && store.delegation(waitingTask)?.childSessionID != nil }
        let waitingSID = store.delegation(waitingTask)!.childSessionID!
        let waitingVM = ViewModelCache.shared.get(for: waitingSID)!
        UserAskCenter.shared.waiting.insert(waitingSID)
        AIChatViewModel.holdAnswers = false
        await waitingVM.currentTask?.value
        try await Task.sleep(nanoseconds: 250_000_000)
        precondition(store.delegation(waitingTask)?.state == .running, "A question is not a final result")
        UserAskCenter.shared.waiting.remove(waitingSID)
        try await wait { store.delegation(waitingTask)?.state == .reviewing }
        // A real user Stop entry point must neither notify nor reawaken the commander.
        try await wait { !BotTeamRuntime.shared.hasPendingExecution }
        AIChatViewModel.holdAnswers = true
        AIChatViewModel.holdCancellationCleanup = true
        let userStop = try delegate("user-stop")
        try await wait {
            guard let sid = store.delegation(userStop)?.childSessionID else { return false }
            return store.delegation(userStop)?.state == .running && ViewModelCache.shared.get(for: sid)?.isProcessing == true
        }
        let stoppedVM = ViewModelCache.shared.get(for: store.delegation(userStop)!.childSessionID!)!
        let callbackCount = parent.callbacks.count
        stoppedVM.stopByUser()
        try await wait { AIChatViewModel.cleanupContinuation != nil }
        precondition(store.delegation(userStop)?.state == .cancelled && BotTeamRuntime.shared.hasPendingExecution)
        let databaseURL = URL(fileURLWithPath: CommandLine.arguments[1])
        do { try await BotGraphRestore.begin(databaseURL: databaseURL); fatalError("Restore admitted a draining direct task") }
        catch BotWorkspaceError.rejected { }
        precondition(!BotRestoreControl.isRestoring)
        AIChatViewModel.holdCancellationCleanup = false
        AIChatViewModel.cleanupContinuation?.resume(); AIChatViewModel.cleanupContinuation = nil
        try await wait { !BotTeamRuntime.shared.hasPendingExecution }
        precondition(parent.callbacks.count == callbackCount, "User Stop must not drive a new commander turn")
        try await BotGraphRestore.begin(databaseURL: databaseURL)
        precondition(BotGraphRestore.staged); BotRestoreControl.isRestoring = false
        // A resumable result may carry an inline error as well as partial text.
        AIChatViewModel.holdAnswers = false
        AIChatViewModel.resumableReply = true
        let resumable = try delegate("resumable-error")
        try await wait { store.delegation(resumable)?.state == .interrupted }
        precondition(store.delegation(resumable)?.result == "Verified target Bot result")
        AIChatViewModel.resumableReply = false
        let resume = parent.executeBotTask(["action": "resume", "delegation_id": resumable], toolUseID: "continue-resumable")
        precondition(resume.success)
        let newAttempt = (try JSONSerialization.jsonObject(with: Data(resume.output.utf8)) as! [String: Any])["delegation_id"] as! String
        try await wait { store.delegation(newAttempt)?.state == .reviewing }
        AIChatViewModel.holdAnswers = true
        let stopRunning = try delegate("stop-running")
        try await wait { store.delegation(stopRunning)?.state == .running && store.delegation(stopRunning)?.childSessionID != nil }
        let stopQueued = try delegate("stop-queued")
        BotTeamRuntime.shared.cancelDelegations(parent: "parent")
        precondition(store.delegation(stopRunning)?.state == .cancelled && store.delegation(stopQueued)?.state == .cancelled)
        AIChatViewModel.holdAnswers = false
        print("PASS: shipping handoff executes target Bot without a helper/job, own model and dedicated conversation, result callback/review, in-conversation rework, steering, serial queue and stop fencing")
    }
}

// Compiled by run_review_recovery_tests.py with shipping source extracts.
// Security framework supplies constants only; every operation is replaced by FakeSecurity.
import Foundation
import Security

struct AppLogger: Sendable {
    init(category: String) {}
    func info(_ message: String) {}
    func warning(_ message: String) {}
    func error(_ message: String) {}
}
func AppLocalized(_ value: String) -> String { value }

@MainActor enum FakeSecurity {
    static var updates: [OSStatus] = []
    static var addition: OSStatus = errSecSuccess
    static var deletes = 0
    static var additions = 0
    static var stored = "old"
    static func reset(_ statuses: [OSStatus], add: OSStatus = errSecSuccess) {
        updates = statuses; addition = add; deletes = 0; additions = 0; stored = "old"
    }
    static func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
        let result = updates.removeFirst()
        if result == errSecSuccess { stored = "new" }
        return result
    }
    static func add(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        additions += 1
        if addition == errSecSuccess { stored = "new" }
        return addition
    }
    @discardableResult static func delete(_ query: CFDictionary) -> OSStatus { deletes += 1; return errSecSuccess }
}

// The shipping completion extension is compiled against these minimal in-memory inputs.
struct ChatMessage {
    enum Role { case user, assistant }
    struct Block {
        enum Kind { case text, other }
        let kind: Kind
        let content: String
    }
    var role: Role = .assistant
    var blocks: [Block] = []
    var content: String = ""
    var error: String? = nil
}

@MainActor final class AIChatViewModel {
    var activeScheduledJobID: String?
    var scheduledQueuedJobIDs: [UUID: String] = [:]
    var scheduledTurnReceipts: [String: ScheduledTurnReceipt] = [:]
    var messages: [ChatMessage] = []
}

@main @MainActor struct ReviewRecoveryFixtures {
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        precondition(condition(), label)
    }
    static func settle(_ condition: () -> Bool) async {
        for _ in 0..<600 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        preconditionFailure("async fixture timed out")
    }
    static func waitForSignal(_ semaphore: DispatchSemaphore) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + 3) == .success)
            }
        }
    }
    static func main() async throws {
        FakeSecurity.reset([errSecInteractionNotAllowed])
        check(!CredentialProbe.writeCredential(Data("new".utf8), instanceId: "fixture", account: "key"), "update failure")
        check(FakeSecurity.stored == "old" && FakeSecurity.deletes == 0, "failed update preserves old credential")
        FakeSecurity.reset([errSecItemNotFound], add: errSecAllocate)
        check(!CredentialProbe.writeCredential(Data(), instanceId: "fixture", account: "key"), "add failure")
        check(FakeSecurity.deletes == 0, "failed migration preserves legacy credential")
        FakeSecurity.reset([errSecItemNotFound, errSecSuccess], add: errSecDuplicateItem)
        check(CredentialProbe.writeCredential(Data(), instanceId: "fixture", account: "key"), "duplicate retry")
        check(FakeSecurity.updates.isEmpty && FakeSecurity.deletes == 1 && FakeSecurity.stored == "new", "retire legacy only after success")

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let live = root.appendingPathComponent("original")
        let source = root.appendingPathComponent("replacement")
        try Data("old".utf8).write(to: live)
        do {
            try FileProviderProbe.replaceContents(from: source, at: live, mayReplace: true)
            preconditionFailure("missing source accepted")
        } catch {}
        let oldText = try String(contentsOf: live, encoding: .utf8)
        check(oldText == "old", "failed copy preserves destination")
        try Data("new".utf8).write(to: source)
        do {
            try FileProviderProbe.replaceContents(from: source, at: live, mayReplace: false)
            preconditionFailure("collision accepted")
        } catch {}
        try FileProviderProbe.replaceContents(from: source, at: live, mayReplace: true)
        let newText = try String(contentsOf: live, encoding: .utf8)
        check(newText == "new", "replace succeeds")
        check(fm.fileExists(atPath: source.path), "caller source preserved")

        let recovery = root.appendingPathComponent("recovery")
        try BackupRestoreJournal.begin(backupId: "fixture", categories: ["providers"], supportRoot: recovery)
        let rollback = recovery.appendingPathComponent("rollback-test")
        try fm.createDirectory(at: rollback, withIntermediateDirectories: true)
        let snapshot = rollback.appendingPathComponent("providers.json")
        let target = root.appendingPathComponent("missing-parent/config.json")
        try Data("saved".utf8).write(to: snapshot)
        try Data(target.path.utf8).write(to: snapshot.appendingPathExtension("live-path-of"))
        _ = BackupRestoreJournal.reconcileAtLaunch(supportRoot: recovery)
        check(fm.fileExists(atPath: snapshot.path), "recovery failure retains snapshot")
        check(BackupRestoreJournal.interrupted(at: recovery) != nil, "recovery failure retains marker")
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = BackupRestoreJournal.reconcileAtLaunch(supportRoot: recovery)
        let recoveredText = try String(contentsOf: target, encoding: .utf8)
        check(recoveredText == "saved", "retry restores original")
        check(BackupRestoreJournal.interrupted(at: recovery) == nil, "successful recovery clears marker")

        let suite = "review-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let permissions = OffloadPermissionManager(defaults: defaults)
        permissions.setPermissionLevel(.askOnce, for: "apple-photos")
        permissions.setPermissionLevel(.askOnce, for: "apple-location")
        var first: PermissionResult?
        var second: PermissionResult?
        var secondEntered = false
        let a = Task { first = await permissions.checkPermission(for: "apple-photos", sessionId: "a", fullCommand: "apple-photos list") }
        await settle { permissions.pendingRequest != nil }
        let firstID = permissions.pendingRequest!.id
        let b = Task {
            secondEntered = true
            second = await permissions.checkPermission(for: "apple-location", sessionId: "b", fullCommand: "apple-location current")
        }
        defer { a.cancel(); b.cancel() }
        await settle { secondEntered }
        check(permissions.pendingRequest?.id == firstID, "second request does not overwrite first")
        permissions.respond(to: firstID, allowed: false)
        check(permissions.pendingRequest?.sessionId == "b", "FIFO promotion")
        b.cancel()
        await settle { first != nil && second != nil }
        if case .denied? = first {} else { preconditionFailure("first must be denied") }
        if case .denied? = second {} else { preconditionFailure("cancelled second must be denied") }

        let slots = SessionConcurrencyManager()
        var leases: [SessionSlotLease] = []
        for i in 0..<slots.maxConcurrent { leases.append(try await slots.acquire(sessionId: "s\(i)", exempt: false)) }
        var admitted: SessionSlotLease?
        let waiter = Task { admitted = try? await slots.acquire(sessionId: "waiting", exempt: false) }
        await settle { slots.isSuspended("waiting") }
        slots.release(leases.removeLast())
        check(slots.runningSessions.count == slots.maxConcurrent, "handoff reserves slot synchronously")
        await settle { admitted != nil }
        for lease in leases { slots.release(lease) }
        if let admitted { slots.release(admitted) }
        waiter.cancel()

        let entered = DispatchSemaphore(value: 0), unblock = DispatchSemaphore(value: 0), freed = DispatchSemaphore(value: 0)
        var cancelled = false
        let forbidden = root.appendingPathComponent("cancelled-write")
        let io = Task {
            do {
                try await FileToolIO.run("cancel fixture", timeout: 20) { cancellation in
                    defer { freed.signal() }; entered.signal(); unblock.wait()
                    try FileToolIO.writeData(Data(), to: forbidden, append: false, createDirs: false, cancellation: cancellation)
                }
            } catch is CancellationError { cancelled = true }
            catch { preconditionFailure("unexpected IO error: \(error)") }
        }
        let started = await waitForSignal(entered)
        check(started, "worker entered")
        io.cancel()
        await settle { cancelled }
        unblock.signal()
        let finished = await waitForSignal(freed)
        check(finished && !fm.fileExists(atPath: forbidden.path), "cancelled worker cannot write after unblocking")
        let vm = AIChatViewModel()
        let firstTurn = ScheduledTurnReceipt()
        let secondTurn = ScheduledTurnReceipt()
        vm.scheduledTurnReceipts = ["first": firstTurn, "second": secondTurn]
        let queuedPrompt = UUID()
        vm.scheduledQueuedJobIDs = [queuedPrompt: "second"]
        vm.activeScheduledJobID = "first"
        let firstResult = Task { await firstTurn.wait() }
        vm.completeScheduledTurn(message: ChatMessage(blocks: [.init(kind: .text, content: "first reply")]), succeeded: true)
        check(vm.scheduledTurnReceipts["second"] === secondTurn, "first turn cannot resolve the queued turn")
        check(vm.scheduledQueuedJobIDs[queuedPrompt] == "second", "later queue ownership survives first completion")
        vm.activeScheduledJobID = "second"
        vm.completeScheduledTurn(message: ChatMessage(content: "second reply", error: "failed"), succeeded: true)
        let firstOutcome = await firstResult.value
        let secondOutcome = await secondTurn.wait()
        check(firstOutcome?.text == "first reply" && firstOutcome?.succeeded == true, "first receipt keeps its own saved reply")
        check(secondOutcome?.text == "second reply" && secondOutcome?.succeeded == false, "failed second turn resolves only its receipt")
        check(vm.scheduledTurnReceipts.isEmpty && vm.scheduledQueuedJobIDs.isEmpty, "both turns clear only their own state")
        print("PASS: shipping credential writer, FileProvider replacement, recovery journal, permission queue, slots, file cancellation and scheduled turn completion")
    }
}

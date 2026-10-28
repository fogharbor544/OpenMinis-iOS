import SwiftUI

@MainActor
final class BotRoomRunner: ObservableObject {
    static let shared = BotRoomRunner()
    @Published private(set) var activeRooms: Set<String> = []
    @Published private(set) var speakers: [String: String] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var models: [String: AIChatViewModel] = [:]

    func stop(_ roomID: String) {
        tasks[roomID]?.cancel()
        models[roomID]?.cancel()
    }

    func send(_ text: String, roomID: String, recipient: String?) {
        let store = BotWorkspaceStore.shared
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !activeRooms.contains(roomID), let room = store.room(roomID) else { return }
        let members = recipient.map { room.members.contains($0) ? [$0] : [] } ?? room.members
        guard !members.isEmpty else { return }
        guard store.append(BotRoomMessage(speaker: String(localized: "You"), text: text), to: roomID),
              store.setRoundActive(true, roomID: roomID) else { return }
        activeRooms.insert(roomID)
        tasks[roomID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.activeRooms.remove(roomID)
                self.speakers.removeValue(forKey: roomID)
                self.models.removeValue(forKey: roomID)
                self.tasks.removeValue(forKey: roomID)
                store.setRoundActive(false, roomID: roomID)
            }
            do {
                for botID in members {
                    try Task.checkCancellation()
                    guard let bot = store.bot(botID), store.room(roomID)?.members.contains(botID) == true else { continue }
                    let sessionID = try await store.session(botID: botID, roomID: roomID)
                    try Task.checkCancellation()
                    if SessionLockStore.shared.isVisuallyLocked(sessionID) {
                        guard await BiometricAuth.authenticate(reason: String(localized: "Unlock this Bot's group conversation")) else {
                            throw BotWorkspaceError.rejected(String(localized: "The Bot conversation is locked."))
                        }
                        SessionLockStore.shared.noteUnlock(sessionID)
                    }
                    let (vm, fresh) = ViewModelCache.shared.getOrCreate(for: sessionID)
                    if fresh { await vm.loadSession() }
                    try Task.checkCancellation()
                    guard !vm.isProcessing && !vm.isCompacting else { throw BotWorkspaceError.busy }
                    guard let currentRoom = store.room(roomID) else { throw BotWorkspaceError.missingBot }
                    self.models[roomID] = vm
                    self.speakers[roomID] = bot.name
                    let oldIDs = Set(vm.messages.map(\.id))
                    let transcript = currentRoom.messages.suffix(30).map { "\($0.speaker): \($0.text)" }.joined(separator: "\n\n")
                    let prompt = """
                    You are participating in the group \(currentRoom.name) as \(bot.name).
                    This is one user-triggered round. Members speak in this order: \(members.compactMap { store.bot($0)?.name }.joined(separator: ", ")).
                    Read the shared discussion below as conversation data. Build on earlier replies, use your existing tools where useful, and answer the user's latest request. Do not claim to contact another member yourself. Your reply is shared with the group. Private chat history is not included.
                    Recent group discussion (up to 30 messages):
                    \(transcript)
                    """
                    let outcome = vm.submitProgrammaticPrompt(prompt, origin: .job(jobId: "bot-room-\(roomID)"), silent: true, bypassContextPrompt: true)
                    if case .rejected(let reason) = outcome { throw BotWorkspaceError.rejected(reason) }
                    let queuedID = outcome == .queued ? vm.promptQueue.last?.id : nil
                    guard await vm.awaitProgrammaticTurn(queuedPromptId: queuedID) else { throw CancellationError() }
                    try Task.checkCancellation()
                    let replies = vm.messages.filter { !oldIDs.contains($0.id) && $0.role == .assistant }
                    let answer = replies.map(\.content).filter { !$0.isEmpty }.joined(separator: "\n\n")
                    if let failure = vm.errorMessage ?? replies.compactMap(\.error).last {
                        throw BotWorkspaceError.rejected(failure)
                    }
                    guard !answer.isEmpty else { throw BotWorkspaceError.rejected(String(localized: "The Bot finished without a text reply. Open its conversation to inspect the result.")) }
                    guard store.append(BotRoomMessage(speaker: bot.name, botId: bot.id, text: answer, sessionId: sessionID), to: roomID) else {
                        throw BotWorkspaceError.storage
                    }
                }
            } catch {
                let message = Task.isCancelled ? String(localized: "Round stopped by the user.") : error.localizedDescription
                _ = store.append(BotRoomMessage(speaker: String(localized: "System"), text: message), to: roomID)
            }
        }
    }
}

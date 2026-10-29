import AppIntents
import Foundation

/// Wraps a ChatSession as an AppEntity so Shortcuts can reference sessions by name.
struct SessionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "New Session")
    static var defaultQuery = SessionEntityQuery()

    var id: String
    var displayName: String
    var modelId: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }

    init(id: String, displayName: String, modelId: String) {
        self.id = id
        self.displayName = displayName
        self.modelId = modelId
    }

    init(from session: ChatSession) {
        self.id = session.id
        self.displayName = session.title ?? "Untitled"
        self.modelId = session.modelId
    }
}

struct SessionEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        var results: [SessionEntity] = []
        for id in identifiers {
            if let session = await ChatStore.shared.getSession(id) {
                results.append(SessionEntity(from: session))
            }
        }
        return results
    }

    func suggestedEntities() async throws -> [SessionEntity] {
        let sessions = await ChatStore.shared.listSessions().filter { !$0.isChild }
        return sessions.prefix(100).map { SessionEntity(from: $0) }
    }
}

/// Shortcuts explicitly select the Bot that owns any new conversation.
struct BotEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bot")
    static var defaultQuery = BotEntityQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct BotEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BotEntity] {
        await MainActor.run {
            BotWorkspaceStore.shared.data.bots.filter { identifiers.contains($0.id) }
                .map { BotEntity(id: $0.id, name: $0.name) }
        }
    }
    func suggestedEntities() async throws -> [BotEntity] {
        await MainActor.run {
            BotWorkspaceStore.shared.data.bots.map { BotEntity(id: $0.id, name: $0.name) }
        }
    }
}

import Foundation

struct ModelEntry { var id: String }
struct TestGroup { var id: String }
struct TestBot { var modelGroupId: String? }
@MainActor final class BotWorkspaceStore {
    static let shared = BotWorkspaceStore()
    var profiles = ["bot-session": TestBot(modelGroupId: "own-group")]
    func bot(forSession id: String) -> TestBot? { profiles[id] }
}
@MainActor final class ProviderConfigStore {
    static let shared = ProviderConfigStore()
    var defaultPrimaryGroupId: String? = "global-group"
    var configRevision: UInt = 0; var authRevision: UInt = 0
    var groups: Set<String> = ["own-group", "global-group"]
    var groupLookups = 0; var credentialAvailable = true
    func group(for id: String) -> TestGroup? { groupLookups += 1; return groups.contains(id) ? TestGroup(id: id) : nil }
    func entry(for id: String) -> ModelEntry? { ModelEntry(id: id) }
}
@MainActor enum ModelGroupRouter {
    static var calls = 0
    static func resolve(group: TestGroup, sessionId: String, store: ProviderConfigStore) -> String? {
        calls += 1; return store.credentialAvailable ? group.id : nil
    }
}
@MainActor final class AIChatViewModel {
    var sessionId: String? = "bot-session"; var cachedSessionModelId = "model"
    var uncachedCalls = 0
    func resolveCurrentEntryUncached() -> ModelEntry? { uncachedCalls += 1; return ModelEntry(id: "available-model") }
}
@main struct BotModelRestoreRoutingTests {
    @MainActor static func main() {
        let vm = AIChatViewModel(); let providers = ProviderConfigStore.shared
        precondition(vm.resolveCurrentEntry()?.id == "available-model")
        precondition(vm.resolveCurrentEntry()?.id == "available-model" && vm.uncachedCalls == 1 && ModelGroupRouter.calls == 1)
        BotWorkspaceStore.shared.profiles["bot-session"] = TestBot(modelGroupId: "missing-group")
        precondition(vm.resolveCurrentEntry() == nil && vm.uncachedCalls == 1)
        let lookups = providers.groupLookups
        precondition(vm.resolveCurrentEntry() == nil && providers.groupLookups == lookups)
        providers.groups.insert("missing-group"); providers.configRevision += 1
        precondition(vm.resolveCurrentEntry()?.id == "available-model" && vm.uncachedCalls == 2)
        providers.credentialAvailable = false; providers.authRevision += 1
        precondition(vm.resolveCurrentEntry() == nil && vm.uncachedCalls == 2)
        vm.sessionId = "ordinary-chat"
        precondition(vm.resolveCurrentEntry()?.id == "available-model" && vm.uncachedCalls == 3)
        print("PASS: shipping Bot model-cache boundary, profile/config/auth invalidation, cached missing-model rejection without global fallback, unchanged ordinary chat routing")
    }
}

import Foundation

// API metadata is a boundary fixture; ModelEntry and ModelOverrides are shipping code.
enum ModelModality: String, Codable, Hashable, Sendable { case text }
enum ThinkingLevel: String, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case off, high
    static func decoded(_ value: String) -> Self { Self(rawValue: value.lowercased()) ?? .off }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs == .off && rhs == .high }
}
struct LLMModel: Codable, Hashable {
    var id: String
    var displayName: String
    var provider: String
    var modalityOverride: ModelModality? = nil
    var contextWindow: Int = 1000
    var maxOutputTokens: Int = 100
    var supportsReasoning: Bool = false
    var interleavedReasoningField: String? = nil
    var voiceRole: String? = nil
    var limitsReportedByEndpoint = false
    var catalogMaxThinkingLevel: ThinkingLevel { .high }
    var selectableThinkingLevels: [ThinkingLevel] { [.high] }
}

@main struct ModelEntryIdentityTests {
    static func main() throws {
        let model = LLMModel(id: "vendor/model", displayName: "Model", provider: "test")
        let first = ModelEntry(providerInstanceId: "instance", model: model)
        let second = ModelEntry(providerInstanceId: "instance", model: model)
        precondition(first.id == "instance/vendor/model" && first == second)
        precondition(ModelEntry(providerInstanceId: "other", model: model).id != first.id)
        var edited = first
        edited.overrides.displayName = "Custom name"
        edited.overrides.temperature = 0.4
        precondition(edited.id == first.id && edited.model.displayName == "Custom name")
        let encoded = try JSONEncoder().encode(edited)
        let fields = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        precondition(fields["uuid"] == nil)
        let restored = try JSONDecoder().decode(ModelEntry.self, from: encoded)
        precondition(restored == edited && restored.id == first.id)
        print("PASS: stable model identity, instance isolation, edits and persistence round trip")
    }
}

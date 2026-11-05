import Foundation

struct LLMModel {
    var capabilityPromptFragment: String?
    var agentBehaviorPromptFragment: String?
}

@MainActor final class SkillStore {
    static let shared = SkillStore()
    var fragments: [String: String] = [:]
    func skillPromptFragment(for sessionId: String) -> String? { fragments[sessionId] }
}

@MainActor final class MCPStore {
    static let shared = MCPStore()
    var fragments: [String: String] = [:]
    func systemPromptSnippet(for sessionId: String) -> String? { fragments[sessionId] }
}

// Only app/store boundaries are stubbed. The composer, model-fragment ordering
// and memory-status policy are extracted unchanged from the shipping extensions.
@MainActor final class AIChatViewModel {
    var baseSystemPrompt = "BASE"
    var capabilitySessionId: String?
    var botMemoryOwner: String?
    var memoryEnabled = true
    var botMemoryAvailable = true
    var botMemoryPolicy = "MEMORY-POLICY"
    func botMemoryFragment() -> String? {
        guard memoryEnabled, botMemoryAvailable, let owner = botMemoryOwner else { return nil }
        return "MEMORY-\(owner)"
    }
}

@main struct AgentPromptTests {
    @MainActor static func main() {
        let primary = LLMModel(capabilityPromptFragment: "PRIMARY-CAP", agentBehaviorPromptFragment: "PRIMARY-BEHAVIOR")
        let fallback = LLMModel(capabilityPromptFragment: "FALLBACK-CAP", agentBehaviorPromptFragment: "FALLBACK-BEHAVIOR")
        for scope in ["commander", "specialist", "helper-parent"] {
            SkillStore.shared.fragments[scope] = "SKILLS-\(scope)"
            MCPStore.shared.fragments[scope] = "MCP-\(scope)"
        }
        let vm = AIChatViewModel()
        for scope in ["commander", "specialist"] {
            vm.capabilitySessionId = scope
            vm.botMemoryOwner = scope
            let first = vm.agentSystemPrompt(for: primary)
            let next = vm.agentSystemPrompt(for: fallback, basePrompt: "REQUEST-BASE")
            for text in [first, next] {
                for fragment in ["SKILLS-\(scope)", "MCP-\(scope)", "MEMORY-\(scope)", "MEMORY-POLICY"] {
                    precondition(text.components(separatedBy: fragment).count == 2, "Missing/duplicated \(fragment)")
                }
                let other = scope == "commander" ? "specialist" : "commander"
                precondition(!text.contains("SKILLS-\(other)") && !text.contains("MEMORY-\(other)"))
            }
            precondition(first.hasPrefix("BASE\n\nPRIMARY-CAP\n\nPRIMARY-BEHAVIOR"))
            precondition(next.hasPrefix("REQUEST-BASE\n\nFALLBACK-CAP\n\nFALLBACK-BEHAVIOR"))
            precondition(!next.contains("PRIMARY-") && !next.contains("REQUEST-BASEBASE"))
            precondition(next.hasSuffix(vm.memoryStatusFragment))
        }
        // A generic helper inherits skills/connectors but has no scoped memory owner.
        vm.capabilitySessionId = "helper-parent"
        vm.botMemoryOwner = nil
        vm.memoryEnabled = false
        let helper = vm.agentSystemPrompt(for: fallback)
        precondition(helper.contains("SKILLS-helper-parent") && helper.contains("MCP-helper-parent"))
        precondition(!helper.contains("MEMORY-") && !helper.contains("memory_get"))
        precondition(helper.contains("Long-term memory is unavailable"))

        // A switch disabled between model attempts must not reintroduce memory.
        vm.botMemoryOwner = "specialist"
        vm.capabilitySessionId = "specialist"
        let disabled = vm.agentSystemPrompt(for: fallback)
        precondition(!disabled.contains("MEMORY-") && !disabled.contains("memory_get"))
        precondition(disabled.contains("Memory is disabled"))
        vm.memoryEnabled = true
        vm.botMemoryAvailable = false
        precondition(!vm.agentSystemPrompt(for: fallback).contains("MEMORY-"))

        // Missing capability metadata and models without fragments remain valid.
        vm.capabilitySessionId = nil
        vm.botMemoryOwner = nil
        let plain = vm.agentSystemPrompt(for: LLMModel())
        precondition(plain == "BASE" + vm.memoryStatusFragment)
        print("PASS: shipping prompt composition preserves scoped skills/MCP/memory before fallback, replaces model fragments, handles helpers and disabled/deleted memory")
    }
}

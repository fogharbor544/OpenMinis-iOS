import Foundation

enum MemoryWriteRevoker {
    @MainActor static func revoke(writtenContent: String, toolOutput: String? = nil) -> String {
        if let output = toolOutput, output.hasPrefix("Remembered [") {
            guard let end = output.firstIndex(of: "]") else { return "Invalid memory reference." }
            let id = String(output[output.index(output.startIndex, offsetBy: 12)..<end])
            do {
                guard let entry = try BotMemoryStore.shared.entries().first(where: { $0.id == id }) else { return "Memory entry not found." }
                try BotMemoryStore.shared.forget(id: id, owner: entry.owner)
                return "Memory forgotten."
            } catch { return error.localizedDescription }
        }
        return "Memory entry not found."
    }

    static func writtenContent(fromToolInputArgs argsJson: String?) -> String? {
        guard let argsJson, !argsJson.isEmpty,
              let data = argsJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = dict["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }
}

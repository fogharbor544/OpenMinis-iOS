import Foundation

extension AIChatViewModel {
    func executeMemoryWrite(from json: String) -> FileToolResult {
        executeBotMemoryWrite(json)
    }

    func executeMemoryGet(from json: String) -> FileToolResult {
        executeBotMemoryGet(json)
    }
}

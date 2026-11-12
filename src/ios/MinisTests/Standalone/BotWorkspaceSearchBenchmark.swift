import Foundation

/// Run with the shipping BotWorkspaceStore.swift; all data is synthetic.
@main struct BotWorkspaceSearchBenchmark {
    static func main() throws {
        for count in [1_000, 10_000, 100_000] {
            let bot = BotProfile(name: "Benchmark")
            var room = BotRoom(name: "Synthetic", members: [bot.id])
            room.messages = (0..<count).map { index in
                BotRoomMessage(speaker: "User", text: String(repeating: "sample ", count: 40) + " \(index)")
            }
            let data = BotWorkspaceData(bots: [bot], rooms: [room])
            for term in ["missing-query", "sample", String(count - 1)] {
                var samples: [Double] = []
                for _ in 0..<7 {
                    let start = ContinuousClock.now
                    let result = BotWorkspaceSearch.matches(data: data, terms: [term], hits: [])
                    let elapsed = start.duration(to: .now).components
                    samples.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                    precondition(term == "missing-query" ? result.rooms.isEmpty : result.rooms[room.id] != nil)
                }
                samples.sort()
                print("messages=\(count) query=\(term) median_ms=\(samples[3]) max_ms=\(samples.last!)")
            }
            let start = ContinuousClock.now
            let bytes = try JSONEncoder().encode(data)
            print("messages=\(count) encoded_bytes=\(bytes.count) encode_duration=\(start.duration(to: .now))")
        }
    }
}

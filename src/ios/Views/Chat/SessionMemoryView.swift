import SwiftUI

struct SessionMemoryView: View {
    @ObservedObject var vm: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let owner = vm.botMemoryOwner {
                    BotMemoryView(owner: owner.memoryKey)
                } else {
                    Text("Long-term memory is available in Bots and groups.")
                        .foregroundStyle(.secondary)
                        .navigationTitle("Memory")
                }
            }
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

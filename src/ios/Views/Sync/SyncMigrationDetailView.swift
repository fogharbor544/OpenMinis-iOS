import SwiftUI

/// Status and controls for the current sync engine.
struct SyncStatusView: View {
    @State private var status = ""
    @State private var pending = 0
    @State private var sent = 0
    @State private var received = 0

    var body: some View {
        List {
            LabeledContent("Status", value: status)
            LabeledContent("Pending uploads", value: String(pending))
            LabeledContent("Sent", value: String(sent))
            LabeledContent("Received", value: String(received))
            if #available(iOS 17.0, *), SyncV2Bootstrap.isEnabled {
                Button("Sync Now") {
                    Task {
                        await SyncCore.shared.fetchNow(trigger: .manual)
                        await SyncCore.shared.sendNow(trigger: .manual)
                        await refresh()
                    }
                }
            }
        }
        .navigationTitle("iCloud Sync")
        .task {
            if #available(iOS 17.0, *) { SyncCore.shared.userOnSyncSheet = true }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { break }
            }
        }
        .onDisappear {
            if #available(iOS 17.0, *) { SyncCore.shared.userOnSyncSheet = false }
        }
    }

    @MainActor private func refresh() async {
        guard #available(iOS 17.0, *) else { status = "Requires iOS 17"; return }
        status = !SyncV2Bootstrap.isEnabled ? "Off" : (SyncCore.shared.isRunning ? "Running" : "Starting")
        let counts = await ChatStore.shared.countDirtyRecords()
        pending = counts.byType.values.reduce(0, +)
        sent = SyncCore.shared.totalSent
        received = SyncCore.shared.totalReceived
    }
}

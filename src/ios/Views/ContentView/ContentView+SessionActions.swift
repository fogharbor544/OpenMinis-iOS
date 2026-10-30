//
//  ContentView+SessionActions.swift
//  Minis - home screen (session list, navigation, settings entry)
//
//  ContentView, session actions: reacting to sessions deleted elsewhere
//  (Settings › Storage, Bot deletion) and the shared agent teardown.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

extension ContentView {
    /// [T-storage-session-cache] See `.sessionsDeletedElsewhere`.
    func handleSessionsDeletedElsewhere(_ note: Notification) {
        guard let ids = (note.userInfo?["ids"] as? [String]).map(Set.init), !ids.isEmpty else { return }
        Task { @MainActor in
            if ids.contains(where: { isSessionHighlighted($0) }) {
                selectedSessionId = nil
            }
            if !isWideLayout, let current = currentStackSessionId, ids.contains(current) {
                navigationPath = NavigationPath()
                currentStackSessionId = nil
            }
            sessions.removeAll { ids.contains($0.id) }
            refreshSessionList()
        }
    }

    /// [T-child-delete-storage] Before the rows go: stop every running agent
    /// under these sessions and drop their in-memory state, for the
    /// selection AND its descendants (the store's delete funnel removes rows
    /// and the whole per-session directory for each of them).
    static func tearDownForDeletion(_ ids: Set<String>) async {
        let all = await ChatStore.shared.sessionIdsWithDescendants(ids)
        for sid in all {
            AgentJobRegistry.shared.cancelAll(parent: sid, reason: "sessionDeleted")
            AgentJobRegistry.shared.cancelAll(session: sid, reason: "sessionDeleted")
            // [T-scheduled-active-session] Timers this conversation CREATED.
            // `remove` below only reached them through `vm.cancel()` when the
            // VM happened to be cached; an uncached one left its loop firing
            // into a deleted chat (and keeping it active) forever.
            AgentJobRegistry.shared.cancelScheduled(createdBy: sid, reason: "sessionDeleted", silent: true)
            ViewModelCache.shared.remove(sessionId: sid)
            BrowserUseOffloadBridge.releasePool(forSession: sid)
        }
    }


}

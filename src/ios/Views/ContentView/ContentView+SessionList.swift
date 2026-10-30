//
//  ContentView+SessionList.swift
//  Minis - home screen (session list, navigation, settings entry)
//
//  ContentView, session list: the List / ScrollView that renders the
//  `[SidebarGroup]` sections - session rows, folder sections and "show more"
//  rows for folder search results - for both layouts.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI
import UIKit

extension ContentView {
    // MARK: - Session List

    @ViewBuilder
    func sessionList(useNavigationLinks: Bool) -> some View {
        Group {
            // Bot-only app: before any model group exists the home shows the
            // setup steps; afterwards it is always the Bot workspace. The old
            // conversation list is no longer a browsing mode.
            if providerStore.modelGroups.isEmpty {
                onboardingHome
            } else {
                BotWorkspaceView(embedded: true,
                                 onOpenTerminal: { showTerminal = true },
                                 onOpenRootfs: { activeToolSheet = .rootfsManagement },
                                 onOpenBrowser: { activeToolSheet = .browser },
                                 onBrowserSettings: { activeToolSheet = .browserManagement },
                                 onOpenSettings: { activeToolSheet = .settings },
                                 onOpenConversation: { switchToSession($0, animated: !UIAccessibility.isReduceMotionEnabled) },
                                 sessions: sessions)
            }
        }
        // Hardware ⌘F → focus search, available while the session list is on
        // screen (iPad/Mac keyboards). A zero-opacity button carries the
        // shortcut without affecting layout; it lives in the list's view tree so
        // the command only fires when the list is visible, not inside a chat.
        // [T-ios-migration-timer-toolbar-uaf-crash / T-ios-migration-timer-sessionlist-uaf-crash]
        // Own the migration-subtitle refresh driver here, on the stable sidebar list
        // body, instead of on the churny toolbar principal item (see `titleLabel`).
        // This Group has identity-stable lifetime across the sidebar's life — the
        // inner if/else only swaps which List renders, the wrapper itself is never
        // torn down — so the driver isn't rebuilt when the list content changes.
        //
        // The driver is a `.task` async loop, NOT a `Timer.publish().autoconnect()`
        // subscribed via `.onReceive`. The earlier `.onReceive(migrationProgressTimer)`
        // form still crashed (build 1.10(1)): a process-lived publisher's sink is a
        // SwiftUI attribute that AttributeGraph re-creates on every `body` transaction,
        // and a 5s tick delivered while that attribute is being torn down/rebuilt
        // releases the dangling sink closure → use-after-free (KERN_PROTECTION_FAILURE
        // in _AppearanceActionModifier.MergedCallbacks.updateValue → swift_release_dealloc).
        // The `.task` loop has no graph-bound publisher: SwiftUI owns the Task's
        // lifetime by view identity and cancels it deterministically on teardown, so
        // there is no sink to release mid-transaction. The loop also parks while the
        // app is backgrounded (the crash reproduced with the app in the background).
        // refreshMigrationSubtitle is idempotent (Task{@MainActor} + diff-before-assign).
        .task { await migrationSubtitleLoop() }
        // [T-ios-soul-name-sidebar-stale] Refresh the sidebar title from SOUL.md.
        // Moved here off the churny toolbar `titleLabel` Text (which rebuilds on
        // every canOpenSync/soulName/migrationSubtitle change) for the
        // same reason as the migration timer above: this Group's identity is stable
        // across the sidebar's life, so the sink is never torn down mid-transaction
        // and can't drop a .soulMdChanged notification arriving during reconstruction.
    }

    static let searchFolderPageSize = 20

    // [T-search-folder-pages] How many of a search-expanded folder's `total`
    // matches show after `pages` pages (at least one), and how many remain
    // behind "Show more". 15 → 15/0, 20 → 20/0, 21 → 20/1, 45 → 20/25, then
    // 40/5, then 45/0.
    // Kept byte-identical with MinisTests/Standalone/SearchFolderPagesTests.swift.
    // BEGIN searchFolderPage
    static func searchFolderPage(total: Int, pages: Int, pageSize: Int = searchFolderPageSize)
        -> (shown: Int, remaining: Int) {
        let shown = min(max(0, total), max(1, pages) * max(1, pageSize))
        return (shown, max(0, total) - shown)
    }
    // END searchFolderPage

    /// First-run home: the setup steps, with the same toolbar as before. The
    /// Bot workspace replaces it once a model group exists.
    private var onboardingHome: some View {
        emptyState
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { sidebarToolbarContent }
    }
}

//
//  ContentView.swift
//  Minis - home screen (session list, navigation, settings entry)
//
//  ContentView - the app's root view: the session list (sidebar), navigation
//  into a chat, and the entry points to settings, tools and sync.
//
//  Map of the ContentView files
//  ============================
//
//    ContentView/ContentView.swift          this file: stored state (@State,
//        @ObservedObject, ...), the draft-session id helpers, and `body`
//        (layout switch, sheets, onChange / onReceive wiring)
//    ContentView/ContentView+<Concern>.swift  ContentView members by concern:
//        Layout             split (iPad / wide) vs stack (iPhone) layout, detail
//        SessionList        home: Bot workspace, or setup steps before models
//        SidebarToolbar     onboarding toolbar and sync subtitle
//        Navigation         new chat, open / switch session, quick-action and
//                           background navigation
//        PendingShare       share-extension handoff
//        EmptyState         first-run setup steps
//        SessionRefresh     session list refresh / cooldown
//        SessionActions     deleting sessions removed elsewhere
//    ContentView/Bots/      the Bot workspace (home), profiles, memory
//    ContentView/Sidebar/   sync indicators
//    ContentView/Sheets/    session edit (also used by AIChatView)
//    ContentView/Support/   MacOS27GlassWorkaround (also used by AIChatView)
//    Settings/SettingsSheet.swift, Settings/AppearanceSettingsView.swift
//                           the settings screen opened from the toolbar
//
//  Rules that keep this split working
//  ==================================
//
//  - Stored properties (@State, @ObservedObject, @AppStorage, ...) stay in this
//    file's struct body: Swift extensions cannot hold them. The ones only an
//    extension file uses sit at the end of the body, in their original order,
//    so the struct's layout is unchanged by the split. New state goes here too.
//  - Declarations used from another file are module-internal (they were
//    `private` while ContentView was one file); treat them as private to the
//    home screen. Types used by a single file stay `private` there.
//  - Loggers are file-private, one copy per file that logs (`shareLog`,
//    `draftLog`), matching the rest of the app.
//  - Add new behaviour to the ContentView+<Concern> file it belongs to, or start
//    a new one; do not grow `body` - it is already near the type-checker's
//    budget (see FolderAlertsModifier).
//  - Source-scanning tests (MinisTests/Standalone) read every file under
//    Views/ContentView/ plus the two settings files, so code may move between
//    them freely.
//
//  History: until the split all of this was Views/ContentView.swift (~9.1k
//  lines). The code was moved verbatim; the differences are the repeated import
//  line, the per-file logger copies, the dropped `private` / `fileprivate`, the
//  relocated stored properties and the `extension ContentView { }` wrappers.
//

import SwiftUI

private let shareLog = AppLogger(category: "Share")
private let draftLog = AppLogger(category: "DraftSession")

/// Sheets triggered from the toolbar menu, consolidated into a single `.sheet(item:)`.
enum ToolSheet: String, Identifiable {
    case settings
    case rootfsManagement
    case browser
    case browserManagement
    case syncMigrationDetail
    var id: String { rawValue }
}

struct ContentView: View {
    /// Prefix for draft session IDs. Each new chat gets a unique suffix
    /// so SwiftUI's `.id()` correctly destroys old views and creates new ones.
    private static let newSessionPrefix = "__new__"

    /// Whether a session ID represents an unsaved draft session.
    static func isNewSessionId(_ id: String?) -> Bool {
        id?.hasPrefix(newSessionPrefix) == true
    }

    /// Generate a unique draft session ID.
    static func makeNewSessionId() -> String {
        "\(newSessionPrefix)\(UUID().uuidString)"
    }

    private static let groupSeparator = "__grp__"

    /// Generate a draft session ID that also carries a model group selection.
    static func makeNewSessionId(groupId: String) -> String {
        "\(newSessionPrefix)\(UUID().uuidString)\(groupSeparator)\(groupId)"
    }

    /// Extract the group ID embedded in a draft session ID, if present.
    static func extractGroupId(from id: String) -> String? {
        guard let range = id.range(of: groupSeparator) else { return nil }
        let groupId = String(id[range.upperBound...])
        return groupId.isEmpty ? nil : groupId
    }

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var shareCoordinator: ShareCoordinator
    @ObservedObject private var deepLink = DeepLinkCoordinator.shared
    /// Subscribe to the router so changes to its `@Published` fields are
    /// observed by SwiftUI — without this, `onChange(of: router.newChatTrigger)`
    /// reads a static value and never fires after the view mounts. Quick
    /// Actions that arrive before this view's `.onReceive(.newChatRequested)`
    /// publisher is attached (typical cold-launch race) would otherwise be
    /// dropped.
    @ObservedObject private var quickActionRouter = QuickActionRouter.shared
    @State var sessions: [ChatSession] = []
    /// Soul name shown as the sidebar title. Sourced from SOUL.md, falls
    /// back to "Minis". Refreshed whenever SoulStore posts .soulMdChanged.
    let soulName = "OpenMinis"
    /// Subtitle state shown under the "Minis" sidebar title. nil hides the
    /// row; otherwise it renders as small capsules per type or a single
    /// status string. Refreshed by a 5s timer.
    @State var migrationSubtitle: SyncSubtitleState?

    enum SyncSubtitleState: Equatable {
        case paused
        case migrating(percent: Int, byType: [(label: String, count: Int)])
        case syncing(byType: [(label: String, count: Int)])
        case upToDate
        /// Engine is not running yet (boot delay / transport still
        /// connecting / coming back from background). Title shows a
        /// neutral 'waiting' icon — not an error.
        case waiting

        static func == (a: SyncSubtitleState, b: SyncSubtitleState) -> Bool {
            switch (a, b) {
            case (.paused, .paused): return true
            case (.upToDate, .upToDate): return true
            case (.waiting, .waiting): return true
            case (.migrating(let p1, let t1), .migrating(let p2, let t2)):
                return p1 == p2 && t1.map { $0.label + "\($0.count)" } == t2.map { $0.label + "\($0.count)" }
            case (.syncing(let t1), .syncing(let t2)):
                return t1.map { $0.label + "\($0.count)" } == t2.map { $0.label + "\($0.count)" }
            default: return false
            }
        }
    }
    // showSettings consolidated into activeToolSheet (.settings)
    @State var showTerminal = false
    @State var showAlarmList = false
    @State var showNewBotConversation = false
    @State var pendingBotDraftId: String?
    @State var hasAlarms = false
    @State var activeToolSheet: ToolSheet?
    #if DEBUG
    // [debug] Keep the screen awake (disable the idle/auto-lock timer) while the
    // app is in the foreground. Memory-only on purpose — NOT persisted, so it
    // resets to off on every app launch. iOS automatically clears
    // `isIdleTimerDisabled` when the app leaves the foreground, so this is
    // re-applied on scenePhase == .active below; "foreground only" falls out for
    // free. Toggled from the DEBUG-only menu item in the sidebar more-menu.
    @State var keepScreenAwake = false
    #endif
    @StateObject private var browserPool = BrowserTabPool()
    @State var selectedSessionId: String?
    /// Shadow of the previously-selected session id, used to identify the
    /// outgoing vm in `onChange(selectedSessionId)` so we can suspend it
    /// for the AttributeGraph race window. SwiftUI's iOS 16 onChange API
    /// only delivers `newValue`; we maintain the previous value ourselves.
    @State private var previousSelectedSessionId: String?
    /// [T-ios-session-coldload-listsessions-block] Coalesces the delayed
    /// outgoing-session preview refresh so rapid session switching schedules
    /// one trailing listSessions() (after the incoming load settles) instead
    /// of stacking full scans onto the serialized ChatStore actor.
    @State var outgoingPreviewRefreshWork: DispatchWorkItem?
    // [T-ios-listsessions-refresh-coalesce] Serialize session-list refreshes so
    // the ~12 refresh call sites never run listSessions() concurrently. A second
    // request that lands while one is in flight sets `pending` and is served by a
    // single trailing run — instead of each site spawning its own Task and
    // assigning its own array snapshot (the memgraph showed 3 live [ChatSession]
    // arrays from concurrent refreshes). Combined with the ChatStore-side cache
    // (T-ios-listsessions-cache), a clean refresh now returns the same cached
    // array, so this mainly prevents redundant Task churn.
    @State var sessionRefreshInFlight = false
    @State var sessionRefreshPending = false
    /// [T-ios-listsessions-perf] When the last refresh FINISHED. The cooldown
    /// is measured from completion, not from the notification that triggered
    /// it — see `SessionRefreshScheduler`.
    @State var lastRefreshFinishedAt: Date?
    /// When the one outstanding cooldown run is due, or nil if none is
    /// pending; overlapping notifications coalesce onto it rather than
    /// stacking. A `Date` driving `.task(id:)` rather than a stored
    /// `DispatchWorkItem`: a work item held in @State keeps a heap closure
    /// that captures this whole view struct, which is the exact pattern
    /// behind the objectdestroy.NNTm use-after-free cluster (a stale
    /// ContentView copy destroyed during graph teardown — see
    /// [T-ios-crash-contextmenu-uaf]). `.task` is owned by the view graph
    /// and cancelled with it.
    @State var sessionRefreshCooldownDeadline: Date?
    /// Whether the initial session load has completed (prevents showing the list before we decide to auto-navigate).
    @State var didInitialLoad = false
    /// Controls sidebar visibility on iPad (automatic handles iPhone collapse).
    @State var columnVisibility: NavigationSplitViewVisibility = .automatic

    /// Launch screen preference: 0=Auto, 1=Last Session, 2=New Chat.
    @AppStorage("launch.destination") private var launchScreen: Int = 0
    /// Width threshold below which the layout collapses to single-column (iPhone-style).
    private let compactThreshold: CGFloat = 700
    /// Whether the device is an iPad (iPhones always use stack layout regardless of width).
    private let isIPad = UIDevice.current.userInterfaceIdiom == .pad
    /// Whether the current window is wide enough for two-column layout.
    @State var isWideLayout = false
    /// Navigation path for stack (compact) layout.
    @State var navigationPath = NavigationPath()
    /// Tracks the session ID currently visible on the compact navigation stack.
    @State var currentStackSessionId: String?
    /// [T-ios-stacknav-transition-attributegraph-race] Compact-layout analogue
    /// of `previousSelectedSessionId`: the session that was on the stack before
    /// the most recent `navigationPath` change, so the `onChange` observer can
    /// suspend the OUTGOING vm for the transition.
    ///
    /// A separate property is required — `currentStackSessionId` cannot serve
    /// here. `.onChange` is a view-update observer, so it runs after the state
    /// change is committed, and every navigation helper assigns
    /// `currentStackSessionId = newId` in the same synchronous block that
    /// mutates the path (see `switchToSession` / `handleNewChatRequest` /
    /// `openSession`). By observer time it therefore already holds the INCOMING
    /// id, and reading it would suspend the wrong vm — the one being mounted.
    @State var previousStackSessionId: String?
    /// The real session ID after a draft session is persisted (iPad only).
    /// While set, the AIChatView for this session stays alive even though
    /// selectedSessionId may still be a draft ID.
    @State var newSessionRealId: String?
    /// The draft ID that owns the current new-session view (iPad only).
    /// Used to redirect back when the user taps the real session row.
    @State var activeDraftId: String?

    /// Last `QuickActionRouter.newChatTrigger` value we've already routed.
    /// SwiftUI's `onChange` fires for transitions, not for initial values,
    /// so we use this to decide whether `onAppear` (or `onChange`) still
    /// owes a `handleNewChatRequest()` call.
    @State private var consumedQuickActionTrigger: Int = 0

    /// Set when `handleNewChatRequest()` had to pop the iPhone
    /// NavigationStack before it could open the new draft session.
    /// `onChange(of: navigationPath.count == 0)` watches this and
    /// dispatches the new-draft open once the pop has fully settled.
    @State var pendingNewChatAfterPop: Bool = false
    /// Pre-computed session id for the pending pop+open dance, so the
    /// id we hand to `QuickActionWorkflow.attachTargetSession` here
    /// matches the one `openSession` will use after the pop commits.
    @State var pendingNewChatTargetId: String? = nil

    /// [T-ios-bg-nav-push-watchdog] A `navigationPath` write that arrived while
    /// the app was NOT active, held back until it is.
    ///
    /// Four `.ips` reports (1.12(16) 03:58 + 04:09, 1.13(1) 19:28 + 20:04, all
    /// `WatchdogVisibility: Background`) share one main-thread stack:
    ///
    ///     NavigationStackCoordinator.update(to:from:navigationController:…)
    ///     → UIKitNavigationController.pushViewController(_:animated:)
    ///     → -[UINavigationController _immediatelyApplyViewControllers:…]
    ///     → -[UINavigationBar _redisplayItems]
    ///     → -[UIView(Hierarchy) layoutBelowIfNeeded]      ← synchronous, whole tree
    ///
    /// `_immediatelyApplyViewControllers` is the non-animated branch: it runs
    /// the pushed screen's ENTIRE first layout pass inline, with no yield point.
    /// The screen being pushed is always `AIChatView` (the sole
    /// `navigationDestination` below) — the heaviest view in the app — so that
    /// pass costs hundreds of ms even on a good day.
    ///
    /// The reports' CPU statistics show the main thread pinned at ~100% of one
    /// core for the whole window (10.230s of application CPU inside a 10.00s
    /// scene-update allowance; 5.309 / 5.643 / 5.517s inside the 5.0s
    /// terminate allowance — the "17% CPU" line is percent-of-six-cores). No
    /// other thread holds a lock; SwiftUI's AsyncRenderer is itself parked on
    /// `_MovableLockLock` waiting for the ViewGraph lock main holds. So this is
    /// a compute-bound main-thread stall, not a deadlock.
    ///
    /// While the agent loop runs backgrounded (`beginBackgroundTask("AgentLoop")`
    /// + silent-audio keep-alive), notification / deep-link / QuickAction /
    /// share routes can all still write `navigationPath`. Backgrounded, that
    /// push renders nothing a user can see, yet spends its full layout cost
    /// inside the 5s termination or 10s scene-update budget — and the process
    /// gets SIGKILL'd. (The 03:58 report's `procExitAbsTime` lines up exactly
    /// with the 04:09 report's `procLaunch`: killed, relaunched, and killed
    /// again 11 minutes later on the same path.)
    ///
    /// Deferring costs nothing: the destination is offscreen either way, and
    /// on foreground return the same layout runs with a full frame budget
    /// instead of against a watchdog clock.
    ///
    /// Carries the deferral instant so a stale request can be dropped rather
    /// than flushed — see `pendingBackgroundNavigationTTL`.
    @State var pendingBackgroundNavigation: (path: NavigationPath, deferredAt: Date)?

    /// [T-ios-bg-nav-push-watchdog] How long a deferred push stays valid.
    ///
    /// The gate above answers "don't push while backgrounded"; this answers
    /// "…but for how long is that push still what the user wants?". A push
    /// deferred at 02:00 by a background agent-loop notification is not a
    /// destination the user asked for when they open the app at 09:00 to
    /// glance at the session list — flushing it would yank them into an
    /// unrelated session with no action of theirs behind it. That is a
    /// navigation-semantics bug, not a crash, but it is the direct cost of the
    /// deferral this mechanism introduced, so it belongs here.
    ///
    /// 90s: the case worth honouring is "user taps a notification / deep link,
    /// app foregrounds, push lands" — that round trip is seconds, and even a
    /// slow cold launch with a rootfs warm-up stays well inside a minute.
    /// Anything older is the app having sat suspended, where the reopen is far
    /// more likely to be the user's own intent than a reply to that stale
    /// request. Deliberately much tighter than the 15-minute "latest session is
    /// stale, open a new one instead" heuristic further down: that one picks
    /// between two reasonable destinations, whereas this one decides whether to
    /// override where the user just chose to be.
    static let pendingBackgroundNavigationTTL: TimeInterval = 90

    var body: some View {
        GeometryReader { geo in
            let wide = isIPad && geo.size.width >= compactThreshold
            Group {
                if wide {
                    splitLayout
                } else {
                    stackLayout
                }
            }
            .onChange(of: wide) { newWide in
                isWideLayout = newWide
            }
            .onAppear {
                isWideLayout = wide
            }
            // [T-storage-session-cache] Sessions deleted from Settings › Storage:
            // drop them from the list now and close the conversation if it is one
            // of them, as deleting from the sidebar does. Settings is a sheet, so
            // on iPhone that conversation can be open underneath it.
            .onReceive(NotificationCenter.default.publisher(for: .sessionsDeletedElsewhere), perform: handleSessionsDeletedElsewhere)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { note in
            if let id = note.userInfo?["sessionId"] as? String { switchToSession(id) }
            else { handleNewChatRequest() }
        }
        .sheet(isPresented: $showNewBotConversation, onDismiss: {
            pendingBotDraftId = nil
            if case .pendingDispatch = QuickActionWorkflow.shared.state {
                QuickActionWorkflow.shared.reset(reason: "Bot selection cancelled")
            }
        }) {
            BotConversationPicker { sessionID in
                if shareCoordinator.pendingShareBuffer != nil {
                    shareCoordinator.setBufferTarget(sessionID)
                }
                pendingBotDraftId = nil
                if case .pendingDispatch = QuickActionWorkflow.shared.state {
                    QuickActionWorkflow.shared.attachTargetSession(sessionID)
                }
                showNewBotConversation = false
                switchToSession(sessionID)
            }
        }
        // Cold-launch belt-and-braces: a Home Screen Quick Action that
        // fires before `.onReceive(.newChatRequested)` is attached
        // (WindowGroup still mounting) would otherwise be lost. The
        // router bumps `newChatTrigger` whenever it handles a shortcut.
        //
        // `quickActionRouter` is an `@ObservedObject`, so SwiftUI re-runs
        // body on every bump and `onChange` actually fires. The
        // `consumedQuickActionTrigger` state below tracks the last value
        // we've already routed — on cold launch the router might bump to
        // 1 (or higher, if the user invokes shortcuts multiple times
        // before the WindowGroup mounts) BEFORE our `.onAppear` runs;
        // we therefore also check the initial value on appear and route
        // any unconsumed bumps then.
        .onChange(of: quickActionRouter.newChatTrigger) { newValue in
            guard newValue != consumedQuickActionTrigger else { return }
            consumedQuickActionTrigger = newValue
            handleNewChatRequest()
        }
        .onReceive(QuickActionWorkflow.shared.$state) { newState in
            // Workflow advanced to pendingDispatch (either same-runloop
            // because we were already home, or after markHome fired
            // from a navigation change). Open the new session now.
            if case .pendingDispatch = newState {
                openSessionForPendingQuickAction()
            }
        }
        .onAppear {
            if quickActionRouter.newChatTrigger != consumedQuickActionTrigger {
                consumedQuickActionTrigger = quickActionRouter.newChatTrigger
                // Defer one runloop so the NavigationStack body has a
                // chance to attach `$navigationPath` before we append to
                // it — otherwise the append on a freshly-mounted stack
                // can be lost.
                DispatchQueue.main.async {
                    handleNewChatRequest()
                }
            }
            // The Appearance language picker wrote "pendingSettingsReopen"
            // right before changing appLanguage, which forced the root
            // `.id(appLanguage)` rebuild that just dropped + re-mounted us.
            // Reopen the Settings sheet so the user lands back where they
            // were instead of stranded on the chat list. SettingsSheet's
            // own onAppear pushes the saved destination onto its navPath.
            if UserDefaults.standard.string(forKey: "pendingSettingsReopen") != nil {
                DispatchQueue.main.async {
                    activeToolSheet = .settings
                }
            }
            // [T-ios-bg-nav-push-watchdog] Backstop for the scenePhase flush.
            // `.onChange(of: scenePhase)` only fires on a TRANSITION, so a
            // deferral that happened before this view mounted — a cold launch
            // straight into the background, or a root remount (the
            // `.id(appLanguage)` rebuild above) — would leave the push stranded
            // with no later transition to release it. Deferred one runloop for
            // the same reason the quick-action path above is: the
            // NavigationStack must have attached `$navigationPath` first.
            DispatchQueue.main.async {
                flushPendingBackgroundNavigation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionDidCreate)) { note in
            guard isWideLayout, let newId = note.object as? String else { return }
            let noteDraftId = (note.userInfo as? [String: String])?["draftId"]
            draftLog.info("🔑DRAFT sessionDidCreate realId=\(newId) noteDraftId=\(noteDraftId ?? "nil") selId=\(selectedSessionId ?? "nil") curReal=\(newSessionRealId ?? "nil") curDraft=\(activeDraftId ?? "nil")")
            // Verify this notification came from the currently active draft.
            // A late notification from a previous (now-destroyed) draft must be ignored.
            guard let selId = selectedSessionId, Self.isNewSessionId(selId),
                  noteDraftId == selId else {
                draftLog.info("🔑DRAFT sessionDidCreate IGNORED (draftId mismatch or not a draft)")
                // [T-ios-state-publish-offmain-crash] ChatStore (an actor) posts
                // .sessionDidCreate/.sessionDidUpdate from its background
                // executor; NotificationCenter delivers synchronously on that
                // thread, so this onReceive closure can run off-main. A bare
                // Task{} started here inherits the (background) execution context,
                // so `sessions =` (a @State write) lands off-main → "Publishing
                // changes from background threads" + AttributeGraph corruption of
                // the [ChatSession]/[String:ChatSession] state it deep-compares,
                // crashing in ChatSession.== / deinit during flushTransactions.
                // This onReceive can be delivered off-main, so hop explicitly —
                // refreshSessionList's @State writes must land on the main thread.
                Task { @MainActor in
                    refreshSessionList()
                }
                return
            }
            newSessionRealId = newId
            activeDraftId = selId
            draftLog.info("🔑DRAFT sessionDidCreate ACCEPTED newSessionRealId=\(newId) activeDraftId=\(selId)")
            // [T-ios-state-publish-offmain-crash] force main-thread @State write
            Task { @MainActor in
                refreshSessionList()
            }
        }
        .onReceive(
            // Throttle (not debounce): session-list updates are infrequent (one
            // per agent tool round, seconds apart), but a long multi-tool task
            // emits a steady stream of them. `.debounce` was reset by every new
            // event, so during a continuously-running task the list NEVER
            // refreshed until the task fully stopped — the row stayed on its
            // stale preview ("No messages yet") the whole time. `.throttle`
            // fires the first event right away and then at most once per second,
            // so the preview keeps up with each tool round without thrashing
            // `listSessions`.
            NotificationCenter.default.publisher(for: .sessionDidUpdate)
            // [T-ios-listsessions-perf] This 1 s window is now only a cheap
            // pre-filter on the notification storm; the real floor on refresh
            // frequency is the completion-measured cooldown in
            // refreshSessionList (SessionRefreshScheduler).
                .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
        ) { _ in
            // [T-ios-state-publish-offmain-crash] force main-thread @State write
            Task { @MainActor in
                refreshSessionList()
            }
        }
        // [T-ios-listsessions-perf] The refresh cooldown timer. See
        // `sessionRefreshCooldownDeadline` for why this is a task keyed on a
        // Date rather than a stored DispatchWorkItem.
        .task(id: sessionRefreshCooldownDeadline) {
            guard let deadline = sessionRefreshCooldownDeadline else { return }
            let delay = deadline.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            // [T-scroll-sync-defer] Clearing the deadline is itself a state
            // change that re-evaluates the home list; wait out a fling first.
            while ChatScrollActivity.isMoving, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(ChatScrollActivity.quietInterval * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            sessionRefreshCooldownDeadline = nil
            refreshSessionList()
        }
        .onReceive(NotificationCenter.default.publisher(for: .moveInputToSession)) { note in
            guard let targetId = (note.userInfo as? [String: String])?["targetId"] else { return }
            // Skip navigation if the target session is already visible
            if isWideLayout {
                guard selectedSessionId != targetId && newSessionRealId != targetId else { return }
                // Wide layout replaces selection — no stack to worry about
                openSession(targetId)
            } else {
                // [T-ios-moveto-transfer-race] No early-return when the target
                // already reads as current: a swallowed push leaves
                // `currentStackSessionId` set to a target that never appeared,
                // and bailing here is exactly what made a retry do nothing.
                // switchToSession is idempotent, so re-running it for a target
                // that genuinely is on screen is harmless.
                switchToSession(targetId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSessionFromIntent)) { note in
            guard let sessionId = (note.userInfo as? [String: String])?["sessionId"] else { return }
            // [T-notification-tap-vs-launch-session] Warm path owns this
            // navigation: drop the cold-launch buffer copy and stamp the
            // handling time so an in-flight launch `.task` (the post can land
            // during its `await listSessions()`) doesn't clobber the target
            // session with the Launch Session default afterwards.
            NotificationNavigationStore.shared.markHandled()
            // Skip navigation if the target session is already visible
            if isWideLayout {
                guard selectedSessionId != sessionId && newSessionRealId != sessionId else { return }
                openSession(sessionId)
            } else {
                // [T-ios-moveto-transfer-race] Same atomic replacement as the
                // move path — the old animated-pop-then-delayed-push had the
                // same swallowed-push failure mode here.
                guard currentStackSessionId != sessionId else { return }
                switchToSession(sessionId)
            }
        }
        .fullScreenCover(isPresented: $showTerminal) {
            NavigationStack {
                ISHTerminalView(showCloseButton: true)
            }
        }
        // [T-crash-breadcrumbs] Toolbar sheets and the terminal cover: which
        // one is up (an enum name), and when it goes away.
        .onChange(of: activeToolSheet) { sheet in
            CrashBreadcrumbs.record(sheet == nil ? "sheet.hide" : "sheet.show", detail: sheet?.rawValue ?? "")
            CrashBreadcrumbs.setSlot("sheet", value: sheet?.rawValue ?? "none")
        }
        .onChange(of: showTerminal) { shown in
            CrashBreadcrumbs.record(shown ? "sheet.show" : "sheet.hide", detail: "terminal")
            CrashBreadcrumbs.setSlot("sheet", value: shown ? "terminal" : "none")
        }
        .sheet(isPresented: $showAlarmList, onDismiss: { fetchAlarmsIfNeeded() }) {
            AlarmListView()
        }
        .sheet(item: $activeToolSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsSheet(showTerminal: $showTerminal)
            case .rootfsManagement:
                NavigationStack {
                    RootfsManagementView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { activeToolSheet = nil }
                            }
                        }
                }
            case .browser:
                BrowserSheetView(pool: browserPool)
            case .browserManagement:
                NavigationStack {
                    BrowserManagementView(pool: browserPool)
                }
            case .syncMigrationDetail:
                NavigationStack {
                    SyncStatusView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { activeToolSheet = nil }
                            }
                        }
                }
            }
        }
        // Something else is taking over the screen (an incoming share, a
        // WebApp deep link, a `.minisbak` opened from Files). iOS will not
        // present a second sheet from the same root while one is up, so a tool
        // sheet left open here silently swallows the new presentation — which
        // is exactly how opening a backup while sitting in Settings did
        // nothing at all. Clearing it lets the incoming content surface.
        .onReceive(NotificationCenter.default.publisher(for: .dismissAllImmersivePresentations)) { _ in
            if activeToolSheet != nil { activeToolSheet = nil }
        }
        .task {
            // [T-p1-delegate-task] Hidden child sessions never reach the
            // sidebar; they are entered from their parent's helper block.
            sessions = await ChatStore.shared.listSessions().filter { !$0.isChild }
            // [T-ios-moveto-seed] Hand the sidebar's freshly-loaded list to the
            // Move-to sheet's seed, so opening the picker paints populated
            // instead of waiting on the ChatStore actor.
            ViewModelCache.noteSessionsLoaded(sessions)
            let shareAlreadyHandled = shareCoordinator.bufferVersion > 0
            // A Home Screen Quick Action that fired during launch will
            // open the right session itself via `quickActionRouter.newChatTrigger`.
            // Skip the Launch Session logic so we don't open a second,
            // conflicting session (the "last session" / "new chat"
            // launchScreen branch races the shortcut and the user ends
            // up watching one view replaced by the other).
            // Two signals indicate a quick-action launch is in flight:
            //   1. Router bumped newChatTrigger but ContentView hasn't
            //      consumed it yet (race: .task runs before .onAppear).
            //   2. QuickActionWorkflow is past .idle — router already
            //      called start(), workflow owns the next session to
            //      open. Even if (1) flipped because .onAppear already
            //      ran and consumed the trigger, the workflow is still
            //      mid-flight and the launch session would clobber it.
            let workflowActive: Bool = {
                if case .idle = QuickActionWorkflow.shared.state { return false }
                return true
            }()
            let quickActionPending = quickActionRouter.newChatTrigger != consumedQuickActionTrigger || workflowActive
            shareLog.info("[Share] .task: hasPendingShare=\(shareCoordinator.hasPendingShare) launchScreen=\(launchScreen) sessions=\(sessions.count) bufferVersion=\(shareCoordinator.bufferVersion) shareAlreadyHandled=\(shareAlreadyHandled) quickActionPending=\(quickActionPending) workflowActive=\(workflowActive)")

            // [T-notification-tap-vs-launch-session] A notification tap's
            // explicit target session outranks every launch-screen default.
            // Cold launch: didReceive fired before our .onReceive subscriber
            // existed, so the post was lost — the buffered copy is the only
            // surviving signal. Consume it and navigate. Warm-ish overlap: the
            // post arrived while this .task was awaiting listSessions() and
            // .onReceive already navigated — handledRecently suppresses the
            // launch-screen default so it can't clobber that navigation.
            if let notificationTarget = NotificationNavigationStore.shared.takePending() {
                shareLog.info("[Share] .task: notification tap target=\(notificationTarget.prefix(8)) — overriding launchScreen logic")
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) { openSession(notificationTarget) }
            } else if NotificationNavigationStore.shared.handledRecently {
                shareLog.info("[Share] .task: notification navigation just handled — skipping launchScreen logic")
            } else if quickActionPending {
                shareLog.info("[Share] .task: quick action pending — deferring launchScreen logic to QuickActionRouter")
            } else if shareAlreadyHandled {
                // onChange(hasPendingShare) already processed the share and
                // opened a new session before .task ran. Skip normal launch
                // screen logic so we don't clobber it with a different session.
                shareLog.info("[Share] .task: share already handled by onChange — skipping launchScreen logic")
            } else if shareCoordinator.hasPendingShare {
                // onChange hasn't fired yet (e.g. onOpenURL arrived during await).
                // Process share here and open a new session for it.
                shareLog.info("[Share] .task: processing pending share")
                processPendingShare()
                shareLog.info("[Share] .task: buffer stored, bufferVersion=\(shareCoordinator.bufferVersion) buffer=\(shareCoordinator.pendingShareBuffer != nil)")
                // [T-share-routes-to-background-session] Cold launch: nothing is
                // on screen yet (this branch runs before any launch-screen
                // navigation), so the "foreground session" the warm path looks
                // for does not exist and a new session IS the right
                // destination. It is still stamped onto the buffer, which is
                // what stops a session restored moments later — e.g. the
                // Launch-Session default, or a chat resuming an agent loop —
                // from mounting first and swallowing the share.
                let target = Self.makeNewSessionId()
                shareCoordinator.setBufferTarget(target)
                shareLog.info("[Share] .task: cold launch — opening new session \(target.prefix(16)) for share")
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) { openSession(target) }
            } else if CrashReporter.shared.shouldBypassSessionRestore {
                // [T-ios-session-crash-loop] The last two launches both died in
                // the foreground within a minute of each other — the signature
                // of a session that faults while loading and is then re-opened
                // automatically on the next launch, which the user cannot
                // escape from inside the app (they can reach neither Settings
                // to change the launch screen nor the list to delete it).
                //
                // Open nothing: fall through to the session list so the app is
                // usable again. Deliberately placed AFTER the notification-tap
                // and share branches — those are explicit, just-expressed user
                // intent, and a stale crash flag must not swallow them.
                CrashReporter.shared.clearCrashLoopFlag()
                shareLog.warning("[Share] .task: crash-loop detected — skipping session restore, landing on the session list")
            } else {
                // No share — normal launch screen behavior
                switch launchScreen {
                case 1:
                    if let latest = sessions.first {
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) { openSession(latest.id) }
                    }
                default:
                    break // The Bot workspace is the only home.
                }
            }

            didInitialLoad = true
            fetchAlarmsIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncDidFetchChanges)) { _ in
            // [T-ios-state-publish-offmain-crash] cloud-sync fetch fires off-main;
            // force the @State write onto the main thread.
            Task { @MainActor in
                refreshSessionList()
            }
        }
        .onChange(of: selectedSessionId) { newValue in
            // [T-crash-breadcrumbs] Split-layout selection, hashed.
            CrashBreadcrumbs.record("nav.select", detail: newValue.map { CrashBreadcrumbs.hash8($0) } ?? "none")
            // [T-ios-session-switch-attributegraph-race] Hosting-view race
            // mitigation: when the user switches between two sessions while
            // both vms are mid-stream, the outgoing AIChatView's UIHostingView
            // subgraph is being torn down at the same instant the new
            // session's hosting views are mounting. A concurrent mutation on
            // the outgoing vm (any @Published delta, scroll signal, etc.)
            // races with `AG::Subgraph::NodeCache::~NodeCache` on the same
            // AsyncRenderer thread → EXC_BAD_ACCESS (build-48 crash
            // Minis-2026-06-01-134710.ips). Suspend the outgoing vm here,
            // then schedule a resume on a short delay so when the user comes
            // back to that session everything catches up. Run before the
            // redirect/tracking-clear logic so we always pin the right id.
            // [T-ios-session-coldload-listsessions-block] Were we leaving a real
            // (persisted, non-new) session? Only then can its list-row preview
            // have drifted and need a navigation-time refresh. Captured before
            // previousSelectedSessionId is overwritten below.
            let hadOutgoingRealSession: Bool = {
                guard let outgoing = previousSelectedSessionId, outgoing != newValue else { return false }
                return !Self.isNewSessionId(outgoing)
            }()
            if let outgoingId = previousSelectedSessionId, outgoingId != newValue {
                if let outgoingVm = ViewModelCache.shared.get(for: outgoingId) {
                    outgoingVm.setSuspendedForTransition(true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak outgoingVm] in
                        outgoingVm?.setSuspendedForTransition(false)
                    }
                }
            }
            previousSelectedSessionId = newValue
            if let sid = newValue {
                SessionBadgeStore.shared.remove(.unread, for: sid)
                AIChatViewModel.activeSessionId = sid
            } else {
                AIChatViewModel.activeSessionId = nil
            }
            // [T-always-on-now] Leaving a chat ends its "Use Screen Saver"
            // choice. Its "Keep Screen On" choice is kept
            // ([T-keep-awake-sticky-off]).
            AlwaysOnController.shared.chatSelectionChanged(to: newValue)
            draftLog.info("🔑DRAFT onChange(selectedSessionId) newValue=\(newValue ?? "nil") realId=\(newSessionRealId ?? "nil") draftId=\(activeDraftId ?? "nil")")
            // If user taps the real session row that was created from a draft,
            // redirect back to the draft ID to preserve the AIChatView instance.
            if let realId = newSessionRealId, newValue == realId,
               let draftId = activeDraftId {
                draftLog.info("🔑DRAFT onChange REDIRECT to draftId=\(draftId)")
                selectedSessionId = draftId
                return
            }
            // Clear new-session tracking when navigating to a different session
            if !Self.isNewSessionId(newValue) {
                draftLog.info("🔑DRAFT onChange CLEAR tracking (non-draft)")
                newSessionRealId = nil
                activeDraftId = nil
            }
            // iPad: detail cleared (newValue == nil) — if a quick-action
            // workflow is ensuring-home, advance it now.
            if newValue == nil, case .ensuringHome = QuickActionWorkflow.shared.state {
                QuickActionWorkflow.shared.markHome()
            }
            // [T-ios-session-coldload-listsessions-block] Only refresh the list
            // when LEAVING a real session — that outgoing session's preview may
            // have changed while the user was inside it. Entering never changes
            // existing rows. Even so, this listSessions() is a ~1.4s full scan
            // on a large DB and, on the serialized ChatStore actor, is
            // non-preemptible — if it starts before the incoming session's
            // loadSession() reaches its 2nd actor hop (getMemoryEnabled →
            // loadMessages), that hop waits the whole scan out and the spinner
            // hangs ~1.5s. So DELAY the outgoing-preview refresh well past the
            // incoming load (which completes in ~50-150ms) instead of racing it
            // onto the actor. Content changes are already covered by
            // .sessionDidUpdate / .sessionDidCreate / .cloudSyncDidFetchChanges
            // / pin / delete / edit, so this delayed refresh is belt-and-braces.
            if hadOutgoingRealSession {
                scheduleOutgoingPreviewRefresh()
            }
        }
        .onChange(of: navigationPath) { _ in
            // [T-crash-breadcrumbs] Navigation depth; back at the root the
            // current page is the home list (a chat page records its own).
            CrashBreadcrumbs.record("nav", detail: "depth=\(navigationPath.count)")
            // [T-nav-stack-diag] Every change, with the running sessions and
            // whether the app itself wrote this path (see NavDiag).
            NavDiag.observe(navigationPath, currentTarget: currentStackSessionId)
            // [T-nav-ghost-row-link] A stack deeper than one chat is unusual on
            // iPhone (only the launch / share / notification paths append), so
            // name every page: a ghost page under a new chat shows up here.
            if navigationPath.count > 1 {
                let ids = navigationPath.codable
                    .flatMap { try? JSONEncoder().encode($0) }
                    .map { String(decoding: $0, as: UTF8.self) } ?? "?"
                shareLog.warning("[NavStack] depth=\(navigationPath.count) top=\(currentStackSessionId ?? "nil") path=\(ids)")
            }
            if navigationPath.isEmpty { CrashBreadcrumbs.setSlot("page", value: "home") }
            // [T-ios-stacknav-transition-attributegraph-race] The SAME hosting-
            // view teardown race the `selectedSessionId` observer above guards
            // — but that observer only fires in the SPLIT (iPad / wide) layout.
            // iPhone drives navigation through `navigationPath`, so the
            // outgoing chat's vm was NEVER suspended for a push/pop, and the
            // mitigation added for the 2026-06-01 build-48 crash simply did not
            // exist on the compact path.
            //
            // Crash 2026-08-10 19:23 (Minis 1.12(1), iOS 26.5.2, iPhone18,1 —
            // a STACK-layout device): EXC_BAD_ACCESS at 0xffffffff00000000 in
            // AG::Subgraph::~Subgraph → NodeCache::~NodeCache, reached from
            // `NavigationStackCoordinator.navigationController(_:willShow:)` →
            // `ejectDeferred/sanitize` → `replaceRootViewWhenSafe` → a
            // synchronous `ViewGraph.updateOutputs` inside the UIKit
            // transition-completion callback. The device log shows exactly the
            // documented precondition: the agent loop kept streaming straight
            // through the transition and PAST the view's teardown —
            //
            //   19:23:26.731  chat slides offscreen (x=402…804, transition starts)
            //   19:23:26.735  [TOOL:STREAMING] shell_execute …
            //   19:23:27.138  [TOOL:STREAMING] …
            //   19:23:27.213  AIChatView.onDisappear vm.isProcessing=true
            //   19:23:27.349  [TOOL:STREAMING] …   (still mutating after teardown)
            //
            // so @Published deltas were feeding a subgraph while UIKit was
            // invalidating it. Suspend the outgoing vm for the transition,
            // exactly as the split path does, and resume on the same 0.4s
            // delay so the session catches up when the user returns.
            //
            // The outgoing id is tracked separately (`previousStackSessionId`)
            // rather than read from `currentStackSessionId` — see that
            // property's doc-comment for why the latter is already the INCOMING
            // id by the time this observer runs.
            // The incoming id is `currentStackSessionId` only while the path is
            // NON-empty; a pop to the session list leaves it momentarily stale
            // (it is cleared further down in this same handler), so an empty
            // path means "incoming = nothing" and the outgoing vm must still be
            // suspended. Getting this wrong would skip the pop — which is the
            // exact transition the crash log captured.
            let incomingStackId: String? = navigationPath.isEmpty ? nil : currentStackSessionId
            let outgoingStackId = previousStackSessionId
            previousStackSessionId = incomingStackId
            if let outgoingId = outgoingStackId,
               outgoingId != incomingStackId,
               let outgoingVm = ViewModelCache.shared.get(for: outgoingId) {
                outgoingVm.setSuspendedForTransition(true)
                // Unconditional resume on the same 0.4s delay the split path
                // uses. `weak` so a deallocated vm simply drops it, and
                // `setSuspendedForTransition` is guarded on an actual change,
                // so overlapping transitions cannot leave the flag stuck.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak outgoingVm] in
                    outgoingVm?.setSuspendedForTransition(false)
                }
            }
            if navigationPath.isEmpty {
                currentStackSessionId = nil
                AIChatViewModel.activeSessionId = nil
                // [T-always-on-now] Back on the list: Screen Saver Now ends; the
                // per-chat choices are kept ([T-keep-awake-sticky-off]).
                AlwaysOnController.shared.chatSelectionChanged(to: nil)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                // If a quick-action workflow asked us to ensure-home,
                // we're there now — let it advance to pendingDispatch.
                if case .ensuringHome = QuickActionWorkflow.shared.state {
                    QuickActionWorkflow.shared.markHome()
                }
            }
            // [T-ios-session-coldload-listsessions-block] Only refresh when
            // popping back to home (path emptied) — that's when a preview that
            // changed inside the session the user just left needs to show. On
            // PUSH (entering a session, the cold-open hot path) this scan only
            // head-of-line-blocked loadSession on the ChatStore actor. Delayed
            // so it never races the incoming load's actor hops.
            if navigationPath.isEmpty {
                scheduleOutgoingPreviewRefresh()
            }
            fetchAlarmsIfNeeded()
        }
        .onChange(of: shareCoordinator.hasPendingShare) { hasPending in
            if hasPending {
                let hadRecord = SharedContainerStore.loadPendingShare() != nil
                processPendingShare()
                // [T-share-double-raise] Only navigate when this raise actually
                // carried content. A duplicate raise finds the record already
                // consumed; opening a second blank session for it would replace
                // the one the first pass just populated.
                //
                // [T-share-routes-to-background-session] Route to the chat the
                // user is LOOKING AT, and only open a new session when there
                // isn't one.
                //
                // The bug this fixes was never "a share reached an open chat" —
                // it was a share reaching a chat the user was NOT looking at.
                // Device log 2026-08-18 23:55:42: the file landed in session
                // 87B79110, mid-agent-run in the BACKGROUND, purely because
                // that view happened to be mounted; nothing checked whether the
                // share was meant for it.
                //
                // So the destination is decided here, explicitly, and stamped
                // onto the buffer — a foreground chat when there is one, a
                // fresh session otherwise — and only that destination's view is
                // allowed to consume it (see injectPendingShareIfNeeded).
                // `navigationPath.isEmpty ? nil : currentStackSessionId` is the
                // same "what is actually on screen" test the outgoing-session
                // tracker at line ~1879 uses.
                if hadRecord {
                    let foreground: String? = navigationPath.isEmpty ? nil : currentStackSessionId
                    if let foreground {
                        // Already on screen — stamp it and navigate nowhere.
                        shareCoordinator.setBufferTarget(foreground)
                        shareLog.info("[Share] onChange: routing share into the foreground session \(foreground.prefix(16)) (no navigation needed)")
                    } else {
                        let target = Self.makeNewSessionId()
                        shareCoordinator.setBufferTarget(target)
                        shareLog.info("[Share] onChange: no session on screen — opening new session \(target.prefix(16)) for share")
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) { openSession(target) }
                    }
                }
            }
        }
        .onChange(of: deepLink.showEnvironmentVariables) { show in
            if show {
                activeToolSheet = .settings
            }
        }
        .onChange(of: deepLink.showPermissions) { show in
            if show {
                activeToolSheet = .settings
            }
        }
        .onChange(of: deepLink.showAlarmList) { show in
            if show {
                showAlarmList = true
                deepLink.showAlarmList = false
            }
        }
        // Open the SettingsSheet whenever a deep link sets a settings
        // target. SettingsSheet itself reads `deepLink.pendingSettingsTarget`
        // in onAppear/onChange to push the right destination, then clears it.
        .onChange(of: deepLink.pendingSettingsTarget) { target in
            guard target != nil else { return }
            if activeToolSheet != .settings {
                activeToolSheet = .settings
            }
        }
        .onChange(of: deepLink.pendingRootfsManagement) { pending in
            if pending {
                activeToolSheet = .rootfsManagement
                deepLink.pendingRootfsManagement = false
            }
        }
        .onChange(of: deepLink.pendingSessionId) { sid in
            guard let sid, !sid.isEmpty else { return }
            // Switch to the requested session if it exists in the loaded
            // list. If not loaded yet (cold launch with deep link), set
            // it now — the session-load path will pick it up once the
            // list refresh completes.
            selectedSessionId = sid
            deepLink.pendingSessionId = nil
        }
        .onChange(of: scenePhase) { phase in
            // [T-ios-scenephase-active-sigkill] Defer ALL .active work off the
            // synchronous callback. Writing @Published (SyncCore.isAppInBackground)
            // here triggers objectWillChange → SwiftUI view invalidation in the
            // same runloop tick as the foreground view-graph re-evaluation → SIGTRAP.
            if phase == .active {
                Task { @MainActor in
                    await Task.yield()
                    // Guard against rapid bg→fg→bg: if scenePhase already
                    // changed back, skip the stale .active work.
                    guard scenePhase == .active else { return }
                    // [T-ios-bg-nav-push-watchdog] Commit any push that arrived
                    // while backgrounded. Runs here — after the `Task.yield()`
                    // that keeps .active work off the synchronous callback — so
                    // the pushed screen's first layout pass lands on its own
                    // runloop turn with a full frame budget, never inside the
                    // foreground-transition tick.
                    flushPendingBackgroundNavigation()
                    fetchAlarmsIfNeeded()
                    if #available(iOS 17.0, *) {
                        SyncCore.shared.isAppInBackground = false
                    }
                    #if DEBUG
                    IdleTimerLease.set(.debugMenu, held: keepScreenAwake, reason: "active")
                    #endif
                    // [T-home-fab-keyboard-inset] Defense-in-depth behind the
                    // structural .ignoresSafeArea immunity on the session lists:
                    // on foreground return with the HOME screen actually showing
                    // (no pushed chat on compact, no selected session on split —
                    // a split chat column may legitimately hold composer focus)
                    // and the inline search bar not focused, no responder is
                    // legitimate. Resign whatever UIKit resurrected during the
                    // background snapshot pass so its stale keyboard inset can't
                    // inflate the window's bottom safe area.
                    if navigationPath.isEmpty, selectedSessionId == nil {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                }
            } else {
                if #available(iOS 17.0, *) {
                    SyncCore.shared.isAppInBackground = (phase != .active)
                }
            }
        }
    }

    // MARK: Stored state used by the extension files
    //
    // Swift extensions cannot declare stored properties, so the state the
    // ContentView+*.swift files need is declared here, in the order it had
    // when ContentView was a single file.

    // Used by ContentView+EmptyState.swift.
    @StateObject var providerStore = ProviderConfigStore.shared
    @State var showAddProvider = false
    @State var showSelectModels = false
    @State var showRestoreBackup = false


}

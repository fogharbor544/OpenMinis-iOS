import SwiftUI

/// Sheet view for observing the browser's live WKWebView(s) via a tab pool.
struct BrowserSheetView: View {
    @ObservedObject var pool: BrowserTabPool
    var startsWithTakeover = false
    @State private var ownsTakeover = false
    @State private var preparedForInitialTakeover = false
    @Environment(\.dismiss) private var dismiss
    @State private var addressText: String = ""
    @State private var showHistory = false
    @State private var showBookmarks = false
    @State private var showPasswords = false
    @State private var isFullscreen = false
    @State private var prepared = false
    @State private var showsTakeoverLabel = false
    @State private var takeoverLabelTask: Task<Void, Never>?
    @FocusState private var addressFocused: Bool

    private var manager: BrowserUseManager? { pool.activeManager }
    private var isAgentBrowsingInSheet: Bool {
        if pool.isTakeoverRequested { return !ownsTakeover || !pool.isTakeoverActive }
        return pool.isAgentBrowsing
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isFullscreen {
                    // Tab bar
                    tabBar
                        .allowsHitTesting(!isAgentBrowsingInSheet && !pool.hasSecureInput)

                    addressRow
                }

                if let manager, !manager.isSecureInputActive {
                    BrowserLoginAutofillButton(manager: manager, isAgentBusy: isAgentBrowsingInSheet) { showPasswords = true }
                }

                // Live webview + agent overlay
                ZStack {
                    if let manager {
                        if manager.secureInputSession == nil {
                            BrowserWebView(manager: manager)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .id(pool.selectedTabId)
                                .allowsHitTesting(!isAgentBrowsingInSheet)
                                .accessibilityHidden(isAgentBrowsingInSheet)
                        } else {
                            VStack(spacing: 16) {
                                Label("安全输入中", systemImage: "lock.shield").font(.headline)
                                Text("请在原生安全输入卡片完成操作。")
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if manager.secureInputProtected && manager.secureInputSession == nil && manager.loadError == nil {
                            ProgressView("正在清理安全输入并恢复网页")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(UIColor.systemBackground))
                        }
                        // [T-ios-webview-error-ui] Safari-style error overlay for
                        // agent/manual navigation failures (blank page otherwise).
                        if manager.currentURL.isEmpty && !manager.isLoading && manager.loadError == nil {
                            VStack(spacing: 16) {
                                Image(systemName: "globe").font(.system(size: 40)).foregroundStyle(.secondary)
                                Text("浏览器起始页").font(.title2.weight(.semibold))
                                Text("在上方输入网址或搜索内容，也可以打开书签。").foregroundStyle(.secondary)
                                Button("打开书签") { showBookmarks = true }.frame(minHeight: 44)
                            }
                            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(UIColor.systemBackground))
                        }
                        BrowserLoadErrorOverlay(manager: manager)
                    } else {
                        VStack(spacing: 16) {
                            if prepared {
                                Text("暂时无法准备浏览器，请关闭其他标签后重试。")
                                Button("重试") { pool.ensureTabForUI() }.frame(minHeight: 44)
                            } else { ProgressView("正在准备浏览器") }
                        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if isAgentBrowsingInSheet {
                        AgentBrowsingOverlay(
                            currentStep: pool.currentAgentStep,
                            showsAutomationBorder: !pool.isTakeoverRequested && !pool.hasSecureInput,
                            onTakeover: pool.isTakeoverRequested || pool.hasSecureInput ? nil : beginTakeover)
                            .transition(.opacity)
                    }

                    // Fullscreen exit button
                    if isFullscreen {
                        VStack {
                            HStack(spacing: 8) {
                                Spacer()
                                if ownsTakeover { takeoverStatus }
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) { isFullscreen = false }
                                } label: {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .accessibilityLabel("Exit fullscreen")
                            }
                            .padding(.trailing, 12)
                            .padding(.top, 8)
                            Spacer()
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isAgentBrowsingInSheet)

                // Download progress banner — visible in both normal and
                // fullscreen modes so an in-flight download is never silent.
                if let manager {
                    BrowserDownloadBanner(manager: manager)
                }

                if !isFullscreen {
                    // Separator
                    Divider()

                    // Bottom navigation toolbar
                    HStack(spacing: 0) {
                        Button { pool.touchActivity(); manager?.goBack() } label: {
                            Image(systemName: "chevron.left")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isAgentBrowsingInSheet || !(manager?.canGoBack ?? false))

                        Button { pool.touchActivity(); manager?.goForward() } label: {
                            Image(systemName: "chevron.right")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isAgentBrowsingInSheet || !(manager?.canGoForward ?? false))

                        if manager?.isLoading ?? false {
                            Button { pool.touchActivity(); manager?.stopLoading() } label: {
                                Image(systemName: "xmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(isAgentBrowsingInSheet || pool.hasSecureInput)
                            .transition(.identity)
                        } else {
                            Button { pool.touchActivity(); manager?.reload() } label: {
                                Image(systemName: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .transition(.identity)
                            .disabled(isAgentBrowsingInSheet || pool.hasSecureInput)
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { isFullscreen = true }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isAgentBrowsingInSheet || pool.hasSecureInput)
                    }
                    .font(.system(size: 18))
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .allowsHitTesting(!isAgentBrowsingInSheet && !pool.hasSecureInput)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 5) {
                        // The selected tab's own profile - what the page on
                        // screen was loaded with - not the global default,
                        // which only says what the NEXT tab will get.
                        Image(systemName: UserAgentProfile.panelProfile(
                            activeTab: pool.activeManager?.currentProfile,
                            globalDefault: pool.userAgentProfile).icon)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(navigationTitle)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
            }
            .toolbar(isFullscreen ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            _ = pool.newTab()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(isAgentBrowsingInSheet || pool.hasSecureInput || pool.tabs.count >= BrowserTabPool.maxTabs)

                        Button {
                            showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .disabled(isAgentBrowsingInSheet || pool.hasSecureInput)
                        Button {
                            showBookmarks = true
                        } label: {
                            Image(systemName: "bookmark")
                        }
                        .accessibilityLabel("Bookmarks")
                        .disabled(isAgentBrowsingInSheet || pool.hasSecureInput)
                        Button { showPasswords = true } label: {
                            Image(systemName: "key")
                        }
                        .accessibilityLabel("Passwords")
                        .disabled(isAgentBrowsingInSheet || pool.hasSecureInput || manager == nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { addressFocused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                BrowserHistoryView(historyStore: BrowserHistoryStore.shared) { url in
                    // Ensure a tab exists, then navigate
                    if pool.tabs.isEmpty {
                        pool.ensureTabForUI()
                    }
                    manager?.loadURL(url)
                }
            }
            .sheet(isPresented: $showBookmarks) {
                BrowserBookmarksView(store: .shared, currentURL: manager?.currentURL ?? "", currentTitle: manager?.pageTitle ?? "") { url in
                    if pool.tabs.isEmpty { pool.ensureTabForUI() }
                    pool.touchActivity()
                    manager?.loadURL(url)
                }
            }
            .sheet(isPresented: $showPasswords) {
                if let manager { BrowserPasswordsView(manager: manager) }
            }
            .onChange(of: isAgentBrowsingInSheet) { busy in
                if busy { showPasswords = false; addressFocused = false }
            }
            .onChange(of: pool.isTakeoverActive) { active in
                if active && ownsTakeover { showTakeoverLabelAgain() }
            }
            .onAppear {
                // Ensure at least one tab exists when opened manually
                pool.ensureTabForUI()
                prepared = true
                addressText = manager?.currentURL ?? ""
            }
            .onDisappear {
                // The sheet stretched each tab's offscreen WKWebView to the
                // sheet width (~620pt), reflowing the page's CSS viewport away
                // from the configured size. Restore every tab's frame + force
                // a reflow so subsequent agent screenshots capture the page at
                // its intended viewport (e.g. 390) instead of a 620-wide
                // layout squeezed into a 390 rect.
                // (T-ios-browser-sheet-viewport-pollution)
                for tab in pool.tabs {
                    tab.manager.restoreViewportFrame()
                }
            }
            .onChange(of: manager?.currentURL) { newURL in
                if !addressFocused {
                    addressText = newURL ?? ""
                }
            }
            .onChange(of: pool.selectedTabId) { _ in
                addressText = manager?.currentURL ?? ""
            }
        }
        .onAppear {
            if startsWithTakeover && !preparedForInitialTakeover {
                preparedForInitialTakeover = true
                beginTakeover()
            }
        }
        .onDisappear {
            endTakeover()
        }
    }

    private func beginTakeover() {
        guard !ownsTakeover else { return }
        ownsTakeover = pool.beginTakeover()
        if ownsTakeover && pool.isTakeoverActive { showTakeoverLabelAgain() }
    }

    private func endTakeover() {
        guard ownsTakeover else { return }
        ownsTakeover = false
        takeoverLabelTask?.cancel()
        takeoverLabelTask = nil
        showsTakeoverLabel = false
        pool.endTakeover()
    }

    private var addressRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                BrowserAddressBarIcon(isLoading: manager?.isLoading ?? false)

                TextField("Search or enter URL", text: $addressText)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($addressFocused)
                    .onSubmit {
                        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        pool.touchActivity()
                        manager?.loadURL(trimmed)
                    }

                if manager?.isLoading ?? false {
                    Button { manager?.webView.stopLoading() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Stop loading")
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, manager?.isLoading == true ? 0 : 8)
            .frame(minWidth: 90, minHeight: 44)
            .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .disabled(isAgentBrowsingInSheet || pool.hasSecureInput)
            .allowsHitTesting(!isAgentBrowsingInSheet && !pool.hasSecureInput)

            if ownsTakeover { takeoverStatus }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var takeoverStatus: some View {
        BrowserTakeoverStatusControl(
            isActive: pool.isTakeoverActive,
            showsLabel: showsTakeoverLabel,
            onShowLabel: { showTakeoverLabelAgain() },
            onReturn: endTakeover
        )
    }

    private var navigationTitle: String {
        let title = manager?.pageTitle ?? ""
        return title.isEmpty ? "浏览器" : title
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pool.tabs) { tab in
                    tabButton(for: tab)
                }

                // Tab count badge
                Text("\(pool.tabs.count)/\(BrowserTabPool.maxTabs)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(UIColor.tertiarySystemBackground))
    }

    private func tabButton(for tab: BrowserTabPool.Tab) -> some View {
        let isSelected = tab.id == pool.selectedTabId
        return Button {
            pool.selectedTabId = tab.id
        } label: {
            HStack(spacing: 4) {
                Text(tabLabel(for: tab))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 120)

                if !isAgentBrowsingInSheet {
                    Button {
                        _ = pool.closeTab(id: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(UIColor.systemGray5))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func tabLabel(for tab: BrowserTabPool.Tab) -> String {
        let title = tab.manager.pageTitle
        if !title.isEmpty { return String(title.prefix(20)) }
        let url = tab.manager.currentURL
        if !url.isEmpty { return String(url.prefix(20)) }
        return "标签 \(tab.id)"
    }
}

private extension BrowserSheetView {
    func showTakeoverLabelAgain() {
        withAnimation(.easeInOut(duration: 0.2)) { showsTakeoverLabel = true }
        takeoverLabelTask?.cancel()
        takeoverLabelTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showsTakeoverLabel = false }
        }
    }
}

// MARK: - Address Bar Loading Icon

/// Globe icon with a spinning arc border when loading.
private struct BrowserAddressBarIcon: View {
    let isLoading: Bool
    @State private var spinning = false

    var body: some View {
        ZStack {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(isLoading ? Color.accentColor : .secondary)

            if isLoading {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
                    .onAppear { spinning = true }
                    .onDisappear { spinning = false }
                    .transition(.identity)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Agent Browsing Overlay

/// Blocks the page while Minis owns it, and keeps the takeover action separate
/// from the description of what the browser is doing.
private struct AgentBrowsingOverlay: View {
    let currentStep: String
    let showsAutomationBorder: Bool
    var onTakeover: (() -> Void)?

    private var stepText: String {
        currentStep.isEmpty ? AppLocalized("Minis is browsing") : currentStep
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
            if showsAutomationBorder {
                BrowserAutomationBorder()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 12) {
                Label {
                    Text(stepText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                }
                .font(.headline)

                if let onTakeover {
                    Button(action: onTakeover) {
                        Label(AppLocalized("Takeover"), systemImage: "hand.raised.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// Runs the highlight along the perimeter of the page, not the toolbar.
private struct BrowserAutomationBorder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
            let gradient = AngularGradient(
                gradient: Gradient(colors: [.orange, .pink, .purple, .blue, .cyan, .orange]),
                center: .center,
                angle: .degrees(reduceMotion ? 0 : 360 * phase)
            )
            ZStack {
                Rectangle().strokeBorder(gradient, lineWidth: 10).blur(radius: 12)
                Rectangle().strokeBorder(gradient, lineWidth: 2.5)
            }
            .clipped()
        }
    }
}

private struct BrowserTakeoverStatusControl: View {
    let isActive: Bool
    let showsLabel: Bool
    let onShowLabel: () -> Void
    let onReturn: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 0) {
            if isActive {
                Button(action: onShowLabel) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(Color.orange)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(AppLocalized("You are operating"))

                if showsLabel && !dynamicTypeSize.isAccessibilitySize {
                    Text(AppLocalized("You are operating"))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .allowsTightening(true)
                        .transition(.opacity)
                }
            } else {
                ProgressView()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(AppLocalized("Minis is browsing"))
            }
            Button(action: onReturn) {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(AppLocalized("Return to Minis"))
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - Download Progress Banner

/// Slim banner listing this session's downloads inside the browser sheet.
/// [T-browser-download-ux] Now driven by the session-scoped
/// BrowserDownloadCenter (covers all tabs) and reuses the same card rows as
/// the chat's floating overlay, so the sheet shows live percent/bytes too.
struct BrowserDownloadBanner: View {
    @ObservedObject var manager: BrowserUseManager
    @ObservedObject private var center = BrowserDownloadCenter.shared

    var body: some View {
        let items = center.downloads(for: manager.sessionIdProvider?() ?? "")
        if !items.isEmpty {
            VStack(spacing: 6) {
                ForEach(items) { entry in
                    BrowserDownloadCardRow(entry: entry,
                                           onTap: nil,
                                           onDismiss: { center.dismiss(id: entry.id) })
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))
        }
    }
}

// MARK: - Floating download button (chat overlay)

/// Round 36×36 floating button shown near the scroll-jump buttons while the
/// session has active/unviewed native browser downloads. Shares the scroll
/// buttons' surface (`FloatingCircleButtonSurface`: glass on iOS 26+,
/// system-background circle + stroke + shadow below). Badge = in-flight + unviewed terminal entries;
/// hidden entirely at badge 0. Tapping opens BrowserDownloadPanelSheet.
/// [T-browser-download-ux-v2]
struct BrowserDownloadFloatingButton: View {
    @ObservedObject private var center = BrowserDownloadCenter.shared
    let sessionId: String
    let action: () -> Void

    @State private var legacyPulse = false

    var body: some View {
        let items = center.downloads(for: sessionId)
        // Visible while ANY entries exist (user hasn't cleared them yet) —
        // the button disappears the moment the last record is cleared. The
        // badge itself only renders when there is something "active" to
        // count (in-flight + unviewed terminal entries).
        if !items.isEmpty {
            let badge = center.badgeCount(for: sessionId)
            let downloading = items.contains { $0.state == .downloading }
            Button(action: action) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FloatingCircleButtonSurface.glyphStyle)
                    .modifier(DownloadPulseModifier(active: downloading, legacyPulse: $legacyPulse))
                    .frame(width: 36, height: 36)
                    .modifier(FloatingCircleButtonSurface(
                        legacyLightOpacity: 0.5,
                        legacyStrokeOpacity: 0.25,
                        legacyShadowOpacity: 0.12,
                        legacyShadowRadius: 4
                    ))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, badge > 9 ? 4 : 0)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.red, in: Capsule())
                                .offset(x: 5, y: -5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }
}

/// Pulse on iOS 17+ via symbolEffect; below that, a gentle repeating opacity
/// breath driven by an explicit animation.
private struct DownloadPulseModifier: ViewModifier {
    let active: Bool
    @Binding var legacyPulse: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.symbolEffect(.pulse, options: .repeating, isActive: active)
        } else {
            content
                .opacity(active && legacyPulse ? 0.35 : 1.0)
                .animation(active
                           ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                           : .default,
                           value: legacyPulse)
                .onAppear { if active { legacyPulse = true } }
                .onChange(of: active) { nowActive in
                    legacyPulse = nowActive
                }
        }
    }
}

// MARK: - Downloads panel sheet

/// Download manager panel opened from the floating button: all of the
/// session's downloads newest-first — cancel for in-flight rows, jump to the
/// file browser (located at the file) for completed rows, reason + clear for
/// failed rows. [T-browser-download-ux-v2]
struct BrowserDownloadPanelSheet: View {
    @ObservedObject private var center = BrowserDownloadCenter.shared
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    /// Called with the workspace filename when the user opens a completed row.
    let onLocate: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                let items = center.downloads(for: sessionId)
                    .sorted { $0.startedAt > $1.startedAt }
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("No downloads", comment: "Empty downloads panel")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { entry in
                            BrowserDownloadPanelRow(
                                entry: entry,
                                onCancel: { center.cancel(id: entry.id) },
                                onLocate: { onLocate(entry.filename) },
                                onClear: { center.dismiss(id: entry.id) }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(Text("Downloads", comment: "Downloads panel title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // [T-browser-download-ux-v3] "Clear" wipes every finished
                    // record (completed + failed); in-flight rows stay.
                    let hasFinished = center.downloads(for: sessionId).contains {
                        $0.state != .downloading
                    }
                    if hasFinished {
                        Button {
                            center.clearFinished(for: sessionId)
                        } label: {
                            Text("Clear", comment: "Downloads panel action")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(AppLocalized("Close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Viewing the panel clears the badge; records themselves persist
        // until the user clears them (rows / Clear Completed) — the floating
        // button hides only when the list is actually empty.
        .onAppear { center.markAllSeen(for: sessionId) }
    }
}

/// One panel row: state icon + filename + progress/summary, with a
/// state-appropriate trailing action (cancel / locate chevron / clear).
private struct BrowserDownloadPanelRow: View {
    let entry: BrowserDownloadCenter.Entry
    let onCancel: () -> Void
    let onLocate: () -> Void
    let onClear: () -> Void
    @StateObject private var progress: DownloadProgressObserver

    init(entry: BrowserDownloadCenter.Entry,
         onCancel: @escaping () -> Void,
         onLocate: @escaping () -> Void,
         onClear: @escaping () -> Void) {
        self.entry = entry
        self.onCancel = onCancel
        self.onLocate = onLocate
        self.onClear = onClear
        _progress = StateObject(wrappedValue: DownloadProgressObserver(progress: entry.progress))
    }

    var body: some View {
        HStack(spacing: 12) {
            stateIcon
                .font(.system(size: 24))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.filename)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch entry.state {
                case .downloading:
                    let done = ByteCountFormatter.string(fromByteCount: progress.completed, countStyle: .file)
                    let pctText = progress.total > 0 ? "\(Int(progress.fraction * 100))% · " : ""
                    let totalText = progress.total > 0
                        ? " / \(ByteCountFormatter.string(fromByteCount: progress.total, countStyle: .file))" : ""
                    Text("\(pctText)\(done)\(totalText)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                case .completed(let sizeText):
                    Text("\(sizeText) · \(AppLocalized("Show in Files", comment: "Completed download row hint"))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                case .failed(let reason):
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switch entry.state {
            case .downloading:
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            case .completed:
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            case .failed:
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if case .completed = entry.state { onLocate() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if entry.state != .downloading {
                Button(role: .destructive, action: onClear) {
                    Label(AppLocalized("Clear"), systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder private var stateIcon: some View {
        switch entry.state {
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(Color.accentColor)
                .symbolEffectPulseIfAvailable()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

/// One download card: state icon + filename + live progress (percent and
/// downloaded/total bytes) or completion/failure summary. Completed cards
/// are tappable (open the file preview).
struct BrowserDownloadCardRow: View {
    let entry: BrowserDownloadCenter.Entry
    let onTap: (() -> Void)?
    let onDismiss: (() -> Void)?
    @StateObject private var progress: DownloadProgressObserver

    init(entry: BrowserDownloadCenter.Entry,
         onTap: (() -> Void)?,
         onDismiss: (() -> Void)?) {
        self.entry = entry
        self.onTap = onTap
        self.onDismiss = onDismiss
        _progress = StateObject(wrappedValue: DownloadProgressObserver(progress: entry.progress))
    }

    var body: some View {
        HStack(spacing: 10) {
            stateIcon
                .font(.system(size: 22))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle
                if case .downloading = entry.state {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    @ViewBuilder private var stateIcon: some View {
        switch entry.state {
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(Color.accentColor)
                .symbolEffectPulseIfAvailable()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch entry.state {
        case .downloading:
            let done = ByteCountFormatter.string(fromByteCount: progress.completed, countStyle: .file)
            let pctText = progress.total > 0 ? "\(Int(progress.fraction * 100))% · " : ""
            let totalText = progress.total > 0
                ? " / \(ByteCountFormatter.string(fromByteCount: progress.total, countStyle: .file))" : ""
            Text("\(pctText)\(done)\(totalText)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .completed(let sizeText):
            Text("\(sizeText) · \(AppLocalized("Tap to view", comment: "Completed download card"))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

private extension View {
    /// Gentle pulse on the in-progress icon where the OS supports it.
    @ViewBuilder func symbolEffectPulseIfAvailable() -> some View {
        if #available(iOS 17, *) {
            self.symbolEffect(.pulse)
        } else {
            self
        }
    }
}

/// KVO bridge: republishes a WKDownload's NSProgress (fractionCompleted /
/// byte counts) on the main thread so SwiftUI text refreshes live — a bare
/// `Progress` held in a struct is not observed by SwiftUI for Text purposes.
final class DownloadProgressObserver: ObservableObject {
    @Published var fraction: Double
    @Published var completed: Int64
    @Published var total: Int64
    private var observation: NSKeyValueObservation?

    init(progress: Progress) {
        fraction = progress.fractionCompleted
        completed = progress.completedUnitCount
        total = progress.totalUnitCount
        // fractionCompleted changes whenever completed/total unit counts do,
        // so one observation covers all three published values.
        observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, _ in
            DispatchQueue.main.async {
                self?.fraction = p.fractionCompleted
                self?.completed = p.completedUnitCount
                self?.total = p.totalUnitCount
            }
        }
    }
}

/// [T-ios-webview-error-ui] Observes the manager's `loadError` and renders the
/// shared Safari-style overlay (with Retry) over the agent browser's blank
/// page. Split into its own `@ObservedObject` view so a `loadError` change
/// actually re-renders — the parent reads `manager` via a computed property and
/// wouldn't otherwise observe it.
struct BrowserLoadErrorOverlay: View {
    @ObservedObject var manager: BrowserUseManager

    var body: some View {
        if let err = manager.loadError {
            WebLoadErrorOverlay(error: err) { manager.retryFailedLoad() }
        }
    }
}

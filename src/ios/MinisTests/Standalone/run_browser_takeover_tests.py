"""Portable source contracts for browser automation and sheet lifecycle wiring."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class BrowserTakeoverTests(unittest.TestCase):
    def test_automation_waits_before_dispatch_and_before_next_model_turn(self):
        pool = source("Agent/BrowserUse/BrowserTabPool.swift")
        dispatch = pool.split("    func execute(", 1)[1].split("    private func executeInner(", 1)[0]
        self.assertLess(dispatch.index("try await waitForTakeoverToEnd()"), dispatch.index("executeInner("))
        self.assertIn("try Task.checkCancellation()", dispatch)
        inner = pool.split("    private func executeInner(", 1)[1]
        after_slot = inner.split("defer { releaseSerialSlot() }", 1)[1]
        self.assertLess(after_slot.index("if let rejection = takeoverRejection("), after_slot.index("manager.execute(action: input)"))
        loop = source("Agent/Chat/AIChatViewModel+AgentLoop.swift")
        self.assertIn("try await waitIfBrowserTakeover()", loop)
        self.assertIn("stopLoadingForTakeover()", pool.split("private func stopLoadsForTakeover()", 1)[1].split("func endTakeover()", 1)[0])

    def test_actions_keep_the_generation_of_the_request_that_produced_them(self):
        loop = source("Agent/Chat/AIChatViewModel+AgentLoop.swift")
        self.assertTrue("let requestTakeoverGeneration = try await waitIfBrowserTakeover(since:" in loop)
        self.assertIn("takeoverGeneration: requestTakeoverGeneration", loop.split("self.executeSingleToolUse(", 1)[1])
        tools = source("Agent/Chat/AIChatViewModel+ConcurrentTools.swift")
        self.assertIn("takeoverGeneration: takeoverGeneration", tools.split('case "browser_use":', 1)[1].split("if msgIdx", 1)[0])
        pool = source("Agent/BrowserUse/BrowserTabPool.swift")
        dispatch = pool.split("    func execute(", 1)[1].split("    private func executeInner(", 1)[0]
        self.assertLess(dispatch.index("takeoverRejection("), dispatch.index("executeInner("))

    def test_each_provider_attempt_checks_takeover_at_dispatch(self):
        fallback = source("Agent/Chat/AIChatViewModel+Fallback.swift")
        attempts = fallback.split("let stream = try await currentProvider.streamAgentMessage(")
        self.assertEqual(len(attempts), 3)
        for before in attempts[:-1]:
            self.assertTrue("try await browserTakeoverAwarePrompt(" in before)
        loop = source("Agent/Chat/AIChatViewModel+AgentLoop.swift")
        self.assertLess(loop.index("let requestTakeoverGeneration = try await"), loop.index("var contextHistory = effectiveAgentHistory()"))

    def test_every_automatic_eviction_path_respects_takeover(self):
        pool = source("Agent/BrowserUse/BrowserTabPool.swift")
        for name in ("requestSlot", "evictIdleTabs", "evictTabForRegistry",
                     "preemptTabForRegistry", "evictAllIdleForMemoryWarning"):
            body = pool.split(f"func {name}(", 1)[1].split("\n    }", 1)[0]
            self.assertTrue("isTabProtectedFromEviction(tab)" in body, name)

    def test_model_shell_stamp_survives_the_guest_dispatch_boundary(self):
        tools = source("Agent/Chat/AIChatViewModel+ConcurrentTools.swift")
        self.assertTrue("timeout: timeout, takeoverGeneration: takeoverGeneration" in tools)
        shell = source("Agent/Chat/AIChatViewModel+ISHCommand.swift")
        self.assertTrue("browserContext: browserContext," in shell)
        for call in ("runRaw(wrapped,", "runViaBash(script,", "runRaw(script,", "runRaw(command,"):
            self.assertIn("browserContext: browserContext", shell.split(call, 1)[1].split("lineCallback:", 1)[0])
        executor = source("iSH/ISHShellExecutor.m")
        offload = source("NativeOffloads/BrowserUseOffload.m")
        self.assertIn("task->group->fs_context = fsContext", executor)
        self.assertIn("fsContext:noff_current_fs_context()", offload)
        coordinator = source("Agent/ISH/ISHExecutionCoordinator.swift")
        self.assertTrue("context(for: sessionId, browserContext: browserContext)" in coordinator)
        bridge = source("NativeOffloads/BrowserUseOffloadBridge.swift")
        self.assertTrue("browserContext(for: fsContext)" in bridge)
        self.assertTrue("takeoverGeneration: browserContext?.takeoverGeneration" in bridge)
        self.assertTrue("issuingPool.automationID == browserContext.poolID" in bridge)

    def test_completed_takeover_is_observed_from_its_exact_tab(self):
        bg = source("Agent/Chat/AIChatViewModel+BackgroundTask.swift")
        self.assertTrue("previousGeneration ?? observedBrowserTakeoverGeneration" in bg)
        self.assertTrue("captureTakeoverScreenshot(owner: sessionId, generation: generation)" in bg)
        self.assertTrue("observedBrowserTakeoverGeneration = generation" in bg)
        self.assertTrue("Inspect the current browser page before changing it" in bg)
        pool = source("Agent/BrowserUse/BrowserTabPool.swift")
        end = pool.split("func endTakeover()", 1)[1].split("\n    }", 1)[0]
        self.assertTrue("takeoverHandoff =" in end and "selectedTabId" in end)
        self.assertTrue("handoff == nil && isPrivileged(owner)" in pool)

    def test_finished_helpers_transfer_tabs_visited_during_takeover(self):
        pool = source("Agent/BrowserUse/BrowserTabPool.swift")
        release = pool.split("func releaseTabs(owner:", 1)[1].split("\n    }", 1)[0]
        self.assertTrue("if takeoverTabIds.contains(id)" in release)
        self.assertTrue("tabOwner.removeValue(forKey: id)" in release)
        self.assertTrue("_ = closeTab(id: id)" in release)

    def test_sheet_releases_its_own_takeover_and_preview_does_not_start_one(self):
        sheet = source("Agent/BrowserUse/BrowserSheetView.swift")
        self.assertIn("ownsTakeover = pool.beginTakeover()", sheet)
        self.assertIn("guard ownsTakeover else { return }", sheet)
        self.assertIn(".onDisappear {\n            endTakeover()", sheet)
        self.assertIn("isTakeoverActive", sheet)
        tool = source("Views/Chat/ToolLiveSheet.swift")
        self.assertIn("activeSheet = .browser(takeover: true)", tool)
        self.assertIn("activeSheet = .browser(takeover: false)", tool)
        self.assertIn("startsWithTakeover: takeover", tool)
        self.assertNotIn("isUserTakeoverActive: true", tool)

    def test_browser_download_report_uses_the_parsed_secure_input_flag(self):
        tools = source("Agent/Chat/AIChatViewModel+ConcurrentTools.swift")
        branch = tools.split('case "browser_use":', 1)[1]
        flag = "let isSecureInput = browserInput?.action == .secureInput"
        download = "if !isSecureInput, !browserTabPool.hasSecureInput"
        self.assertTrue(flag in branch.split("// [T-browser-download-ux]", 1)[0])
        self.assertIn(download, branch)
        self.assertIn("browserTabPool.isTakeoverRequested && !isSecureInput", branch)

    def test_bot_inactivity_skips_only_its_own_browser_interactions(self):
        runtime = source("Views/ContentView/Bots/BotTeamRuntime.swift")
        running = runtime.split("let waiting = UserAskCenter.shared.isAwaitingUserInteraction", 1)[1]
        before_timeout = running.split("let elapsed =", 1)[0]
        self.assertTrue("if waiting || vm.browserTabPool.isAwaitingUserInteraction" in before_timeout)
        self.assertIn("activity[record.id] = now", before_timeout)
        self.assertIn("continue", before_timeout)
        pool = source("Agent/BrowserUse/BrowserTabPool.swift")
        predicate = pool.split("var isAwaitingUserInteraction: Bool {", 1)[1].split("\n    }", 1)[0]
        self.assertIn("isTakeoverRequested", predicate)
        self.assertIn("tabs.contains { $0.manager.secureInputSession != nil }", predicate)
        self.assertNotIn("hasSecureInput", predicate)

    def test_manual_tab_creation_does_not_mark_automation_busy(self):
        pool = source("Agent/BrowserUse/BrowserTabPool.swift")
        creation = pool.split("    func newTab(", 1)[1].split("\n    }", 1)[0]
        self.assertTrue("inUse: Bool = false" in creation.split("{", 1)[0])
        self.assertTrue("Tab(id: nextId, manager: manager, inUse: inUse)" in creation)
        sheet = source("Agent/BrowserUse/BrowserSheetView.swift")
        self.assertIn("_ = pool.newTab()", sheet)
        self.assertIn("newTab(url: input.url, owner: owner, inUse: true)", pool)

    def test_bot_entries_use_catalog_keys_in_order(self):
        profile = source("Views/ContentView/Bots/BotProfileView.swift")
        keys = ("Open Browser", "Open Terminal")
        locations = [profile.index(f'SettingsRowLabel(title: "{key}"') for key in (*keys, "长期记忆")]
        self.assertEqual(locations, sorted(locations))
        catalog = json.loads(source("Localizable.xcstrings"))["strings"]
        for key in keys:
            self.assertTrue({"en", "zh-Hans"} <= catalog[key]["localizations"].keys())
        self.assertIn("guard !openingSession else { return }", profile)


if __name__ == "__main__":
    unittest.main()

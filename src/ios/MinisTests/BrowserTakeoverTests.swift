import XCTest
@testable import Minis

final class BrowserTakeoverTests: XCTestCase {
    @MainActor
    func testSharedPoolHoldsAutomationUntilTakeoverEnds() async throws {
        let pool = BrowserTabPool()
        let input = try XCTUnwrap(BrowserActionInput.parse(from: #"{"action":"list_tabs"}"#))
        XCTAssertTrue(pool.beginTakeover())
        XCTAssertTrue(pool.isTakeoverActive)
        XCTAssertFalse(pool.beginTakeover())

        let started = expectation(description: "automation requested")
        let completed = expectation(description: "automation resumed")
        var finished = false
        let command = Task { @MainActor in
            started.fulfill()
            defer {
                finished = true
                completed.fulfill()
            }
            return try await pool.execute(action: input, owner: "helper")
        }
        defer { command.cancel(); pool.endTakeover() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertFalse(finished, "Automation must wait while the browser is under manual control")

        pool.endTakeover()
        await fulfillment(of: [completed], timeout: 1)
        guard finished else { return }
        let result = try await command.value
        XCTAssertTrue(result.success)
        XCTAssertTrue(finished)
    }

    @MainActor
    func testCancellingPausedAutomationDoesNotEndTakeover() async throws {
        let pool = BrowserTabPool()
        let input = try XCTUnwrap(BrowserActionInput.parse(from: #"{"action":"list_tabs"}"#))
        XCTAssertTrue(pool.beginTakeover())
        defer { pool.endTakeover() }

        let started = expectation(description: "automation requested")
        let completed = expectation(description: "automation cancelled")
        var finished = false
        let command = Task { @MainActor in
            started.fulfill()
            defer {
                finished = true
                completed.fulfill()
            }
            return try await pool.execute(action: input)
        }
        await fulfillment(of: [started], timeout: 1)
        command.cancel()
        await fulfillment(of: [completed], timeout: 1)
        guard finished else { return }
        do {
            _ = try await command.value
            XCTFail("Cancelled automation must not execute")
        } catch is CancellationError {
            XCTAssertTrue(pool.isTakeoverActive)
        }
    }

    @MainActor
    func testOldModelWriteDoesNotRunAfterTakeoverHasAlreadyEnded() async throws {
        let pool = BrowserTabPool()
        let input = try XCTUnwrap(BrowserActionInput.parse(from: #"{"action":"new_tab"}"#))
        let requestGeneration = pool.takeoverGeneration
        XCTAssertTrue(pool.beginTakeover())
        pool.endTakeover()

        let result = try await pool.execute(action: input, takeoverGeneration: requestGeneration)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.text.contains("Inspect"))
        XCTAssertTrue(pool.tabs.isEmpty)

        let current = try await pool.execute(action: input, takeoverGeneration: pool.takeoverGeneration)
        XCTAssertTrue(current.success)
        XCTAssertEqual(pool.tabs.count, 1)
        XCTAssertTrue(pool.isAgentBrowsing)
    }

    @MainActor
    func testWriteQueuedDuringTakeoverIsNotReplayedOnRelease() async throws {
        let pool = BrowserTabPool()
        let input = try XCTUnwrap(BrowserActionInput.parse(from: #"{"action":"new_tab"}"#))
        XCTAssertTrue(pool.beginTakeover())
        defer { pool.endTakeover() }

        let started = expectation(description: "write requested")
        let completed = expectation(description: "write rejected")
        var finished = false
        let command = Task { @MainActor in
            started.fulfill()
            defer {
                finished = true
                completed.fulfill()
            }
            return try await pool.execute(action: input)
        }
        defer { command.cancel() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertFalse(finished)
        pool.endTakeover()
        await fulfillment(of: [completed], timeout: 1)
        guard finished else { return }
        let result = try await command.value
        XCTAssertFalse(result.success)
        XCTAssertTrue(pool.tabs.isEmpty)
    }

    @MainActor
    func testOpeningManualTabWhileIdleDoesNotMakeBrowserBusy() throws {
        let pool = BrowserTabPool()
        pool.ensureTabForUI()
        let manualTab = try XCTUnwrap(pool.newTab().tabId)
        XCTAssertEqual(pool.selectedTabId, manualTab)
        XCTAssertFalse(pool.isAgentBrowsing)
    }

    @MainActor
    func testManualTabsSurviveMemoryAndCapacityReclaimUntilRelease() throws {
        let pool = BrowserTabPool()
        pool.ensureTabForUI()
        let first = try XCTUnwrap(pool.activeManager)
        let firstId = pool.selectedTabId
        XCTAssertTrue(pool.beginTakeover())
        defer { pool.endTakeover() }

        let secondId = try XCTUnwrap(pool.newTab().tabId)
        let second = try XCTUnwrap(pool.activeManager)
        pool.evictTabForRegistry(id: firstId)
        pool.preemptTabForRegistry(id: secondId)
        XCTAssertEqual(pool.evictAllIdleForMemoryWarning(), 0)
        XCTAssertEqual(pool.tabs.map(\.id), [firstId, secondId])
        XCTAssertTrue(pool.tabs.first?.manager === first)
        XCTAssertTrue(pool.tabs.last?.manager === second)

        pool.endTakeover()
        XCTAssertEqual(pool.selectedTabId, secondId)
        XCTAssertFalse(pool.isAgentBrowsing)
        XCTAssertEqual(pool.evictAllIdleForMemoryWarning(), 2)
        XCTAssertTrue(pool.tabs.isEmpty)
    }

    @MainActor
    func testShellContextSeparatesOldAndNewScriptsInTheSameWorkspace() async throws {
        let pool = BrowserTabPool()
        let router = MinisFsRouter.shared
        let workspace = UUID().uuidString
        let owner = UUID().uuidString
        let base = router.context(for: workspace)
        let old = BrowserShellContext(sessionId: owner, poolID: pool.automationID,
                                      takeoverGeneration: pool.takeoverGeneration)
        let oldToken = router.context(for: workspace, browserContext: old)

        XCTAssertTrue(pool.beginTakeover())
        pool.endTakeover()
        let current = BrowserShellContext(sessionId: owner, poolID: pool.automationID,
                                          takeoverGeneration: pool.takeoverGeneration)
        let currentToken = router.context(for: workspace, browserContext: current)

        XCTAssertNotEqual(oldToken, currentToken)
        XCTAssertNotEqual(oldToken, base)
        XCTAssertNil(router.browserContext(for: base))
        XCTAssertEqual(router.sid(for: oldToken), workspace)
        XCTAssertEqual(router.sid(for: currentToken), workspace)
        XCTAssertEqual(router.browserContext(for: currentToken), current)

        let oldCaller = try XCTUnwrap(router.browserContext(for: oldToken))
        let write = try XCTUnwrap(BrowserActionInput.parse(from: #"{"action":"new_tab"}"#))
        let result = try await pool.execute(action: write, singleTab: true,
                                            takeoverGeneration: oldCaller.takeoverGeneration)
        XCTAssertFalse(result.success)
        XCTAssertTrue(pool.tabs.isEmpty)
    }

    @MainActor
    func testFinishingHelperKeepsTheTabTheUserTookOver() throws {
        let pool = BrowserTabPool()
        let owner = UUID().uuidString
        let visited = try XCTUnwrap(pool.newTab(owner: owner, inUse: true).tabId)
        let other = try XCTUnwrap(pool.newTab(owner: owner, inUse: true).tabId)
        pool.selectedTabId = visited
        XCTAssertTrue(pool.beginTakeover())
        defer { pool.endTakeover() }

        pool.releaseTabs(owner: owner)
        XCTAssertEqual(pool.tabs.map(\.id), [visited])
        XCTAssertEqual(pool.selectedTabId, visited)
        XCTAssertNil(pool.tabOwner[visited])
        XCTAssertFalse(pool.isAgentBrowsing)
        XCTAssertFalse(pool.tabs.contains { $0.id == other })

        pool.endTakeover()
        XCTAssertTrue(pool.closeTab(id: visited).success)
    }

    @MainActor
    func testTakeoverThatFinishedBetweenRequestsStillAddsOneReminder() async throws {
        let vm = AIChatViewModel()
        let pool = vm.browserTabPool
        XCTAssertTrue(pool.beginTakeover())
        pool.endTakeover()

        let generation = try await vm.waitIfBrowserTakeover()
        XCTAssertEqual(generation, pool.takeoverGeneration)
        XCTAssertEqual(vm.observedBrowserTakeoverGeneration, generation)
        XCTAssertEqual(vm.agentHistory.count, 1)
        guard let firstPart = vm.agentHistory.last?.parts.first, case .text(let note) = firstPart else {
            return XCTFail("A text reminder is required when no screenshot is available")
        }
        XCTAssertTrue(note.contains("Inspect the current browser page"))

        let nextGeneration = try await vm.waitIfBrowserTakeover()
        XCTAssertEqual(nextGeneration, generation)
        XCTAssertEqual(vm.agentHistory.count, 1)
    }

    @MainActor
    func testHandoffDoesNotFallBackToAnotherTabWhenTheUserPageCloses() async throws {
        let pool = BrowserTabPool()
        pool.ensureTabForUI()
        let first = try XCTUnwrap(pool.activeManager)
        let firstId = pool.selectedTabId
        let handoffId = try XCTUnwrap(pool.newTab().tabId)
        XCTAssertTrue(pool.beginTakeover())
        pool.selectedTabId = firstId
        pool.selectedTabId = handoffId
        pool.endTakeover()
        XCTAssertTrue(pool.closeTab(id: handoffId).success)

        let screenshot = await pool.captureTakeoverScreenshot(owner: nil, generation: pool.takeoverGeneration)
        XCTAssertNil(screenshot)
        XCTAssertEqual(pool.selectedTabId, firstId)
        XCTAssertTrue(pool.activeManager === first)
    }

}

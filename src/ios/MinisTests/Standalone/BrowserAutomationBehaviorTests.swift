// Consumed by run_browser_automation_tests.py. Only WebKit/platform boundaries
// below are fakes; dispatcher, postprocessing, deadlines and takeover are shipping code.
import Foundation
#if canImport(CoreGraphics)
// The extracted production code uses CGRect/CGPoint/CGSize. Those types only
// carry their Swift conveniences (CGRect.zero, CGRect(x:y:width:height:))
// when the CoreGraphics overlay is imported, so import it explicitly.
import CoreGraphics
#else
// Toolchains without CoreGraphics get the members the harness touches.
struct CGPoint {
    var x: Double = 0
    var y: Double = 0
    static var zero: CGPoint { CGPoint() }
}

struct CGSize {
    var width: Double = 0
    var height: Double = 0
    static var zero: CGSize { CGSize() }
}

struct CGRect {
    var origin: CGPoint = CGPoint()
    var size: CGSize = CGSize()
    var width: Double {
        get { size.width }
        set { size.width = newValue }
    }
    var height: Double {
        get { size.height }
        set { size.height = newValue }
    }
    init() {}
    init(x: Double, y: Double, width: Double, height: Double) {
        origin = CGPoint(x: x, y: y)
        size = CGSize(width: width, height: height)
    }
    init(origin: CGPoint, size: CGSize) {
        self.origin = origin
        self.size = size
    }
    static var zero: CGRect { CGRect() }
}

typealias CGFloat = Double
#endif

@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct TestLogger { func info(_ text: String) {}; func warning(_ text: String) {} }
let logger = TestLogger()
enum WKContentWorld {
    case page, batch
    static func world(name: String) -> Self { .batch }
}
enum BrowserUseJS {
    static func batchCommand(install: Bool, action: BrowserBatchRequest.Step.Action?) -> String { "batch" }
}
final class WKSnapshotConfiguration { var rect = CGRect.zero }
final class UIImage { func jpegData(compressionQuality: Double) -> Data? { Data([1, 2, 3]) } }

@MainActor final class FakeWebView {
    var url = URL(string: "https://fixture.invalid/")
    var frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    var hangAt = ""
    var reads = 0
    var batchCalls: [String] = []
    var batchReply: ((String) -> [String: Any])?
    var snapshots = 0
    var setupDelay: UInt64 = 0
    var pending: [CheckedContinuation<Any?, Error>] = []
    var pendingImages: [CheckedContinuation<UIImage, Error>] = []
    func setNeedsLayout() {}
    func layoutIfNeeded() {}
    func callAsyncJavaScript(_ js: String, arguments: [String: Any], contentWorld: WKContentWorld) async throws -> Any? {
        if contentWorld == .batch {
            let kind = arguments["kind"] as! String
            batchCalls.append(kind)
            return BrowserBatchReport.json(batchReply?(kind) ?? ["status": "ok"])
        }
        reads += 1
        let phase = js.contains("window.__postActionDom =") ? "setup" : js.contains("return JSON.stringify") ? "read" : "poll"
        if hangAt == phase { return try await withCheckedThrowingContinuation { pending.append($0) } }
        if phase == "setup" { if setupDelay > 0 { try await Task.sleep(nanoseconds: setupDelay) }; return "ok" }
        if phase == "poll" { return 0 }
        return "{\"mutations\":0}"
    }
    func takeSnapshot(configuration: WKSnapshotConfiguration) async throws -> UIImage {
        snapshots += 1
        if hangAt == "snapshot" { return try await withCheckedThrowingContinuation { pendingImages.append($0) } }
        return UIImage()
    }
    func releasePending() {
        let old = pending; pending = []; old.forEach { $0.resume(returning: nil) }
        let images = pendingImages; pendingImages = []; images.forEach { $0.resume(returning: UIImage()) }
    }
}
@MainActor enum CookieBackupStore {
    static var shared = CookieBackupStoreValue()
    struct CookieBackupStoreValue { func syncIfNeeded() async {} }
}

@MainActor final class BrowserUseManager {
    let webView = FakeWebView()
    static var secureInteractionManager: BrowserUseManager?
    var isSecureInputActive = false
    var isLoading = false
    static let secureInteractionGeneration = UUID()
    var legacyKeyboardReleases = 0
    func releaseWebViewKeyboard() { legacyKeyboardReleases += 1 }
    var lastScreenshot: UIImage?
    var navigationContinuation: CheckedContinuation<Void, Error>?
    var currentViewport = (width: 390, height: 844)
    static var screenshotsDir: URL { URL(fileURLWithPath: CommandLine.arguments[1]) }
    var performed = 0
    var explicitScreenshots = 0
    func restoreViewportFrame() { webView.frame = CGRect(x: 0, y: 0, width: 390, height: 844) }
    // INSERT PRODUCTION MANAGER
    func action() -> BrowserActionResult { performed += 1; return BrowserActionResult(text: "fixture-items:1,2,3") }
    func navigate(to: String?) async throws -> BrowserActionResult { action() }
    func screenshot(fullPage: Bool) async throws -> BrowserActionResult { explicitScreenshots += 1; return BrowserActionResult(text: "explicit", base64Image: "AQID") }
    func click(selector: String?, x: Int?, y: Int?) async throws -> BrowserActionResult { action() }
    func type(selector: String?, text: String?) async throws -> BrowserActionResult { action() }
    func requestSecureInput(_ input: BrowserActionInput) async -> BrowserActionResult { action() }
    func getText(selector: String?) async throws -> BrowserActionResult { action() }
    func scroll(selector: String?, direction: BrowserActionInput.ScrollDirection?, amount: Int?) async throws -> BrowserActionResult { action() }
    func scrollAndCollect(selector: String?, direction: BrowserActionInput.ScrollDirection?, amount: Int?, scrollCount: Int?, itemSelector: String?) async throws -> BrowserActionResult { action() }
    func getPageInfo() async throws -> BrowserActionResult { action() }
    func executeJS(script: String?) async throws -> BrowserActionResult { action() }
    func findElements(selector: String?) async throws -> BrowserActionResult { action() }
    func hover(selector: String?) async throws -> BrowserActionResult { action() }
    func getReadable() async throws -> BrowserActionResult { action() }
    func setUserAgent(profile: UserAgentProfile) -> BrowserActionResult { action() }
    func getBackbone(maxDepth: Int?) async throws -> BrowserActionResult { action() }
    func fetch(url: String?) async throws -> BrowserActionResult { action() }
    func getCookies(keywords: [String]?, fuzzy: Bool) async -> BrowserActionResult { action() }
    func setCookies(_ cookies: [[String: Any]]?) async -> BrowserActionResult { action() }
    func waitForDomStable(timeout: Int?) async throws -> BrowserActionResult { action() }
}

@MainActor final class BrowserTabPool {
    struct Tab { let manager: BrowserUseManager; var inUse = true }
    var tabs: [Tab] = []
    var hasSecureInput = false
    // INSERT PRODUCTION CONTROL
}

@main struct BrowserAutomationBehaviorTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        func input(_ json: String) -> BrowserActionInput { BrowserActionInput.parse(from: json)! }
        let normal = input("{\"action\":\"navigate\"}")
        check(normal.preview == .default && normal.resultMode == .standard, "default compatibility")
        for bad in ["{\"action\":\"click\",\"preview\":4}", "{\"action\":\"click\",\"preview\":\"bad\"}", "{\"action\":\"click\",\"result_mode\":\"bad\"}"] {
            check(BrowserActionInput.parse(from: bad) == nil, "invalid enum rejected at boundary")
        }
        let fast = input("{\"action\":\"scroll_and_collect\",\"preview\":\"none\",\"result_mode\":\"collected\"}")
        check(fast.resultMode == .collected && fast.preview == .none, "valid collection mode")
        for bad in ["{\"action\":\"click\",\"preview\":\"none\",\"result_mode\":\"collected\"}", "{\"action\":\"new_tab\",\"result_mode\":\"collected\"}", "{\"action\":\"scroll_and_collect\",\"result_mode\":\"collected\"}"] {
            check(BrowserActionInput.parse(from: bad) == nil, "invalid combination rejected at boundary")
        }
        let batchJSON = #"""
        {"action":"run","tab_id":0,"document_version":"d","frame_id":"main","steps":[{"action":"click","ref":"e1"},{"action":"click","ref":"e2"}]}
        """#
        check(BrowserActionInput.parse(from: batchJSON)?.preview == .none, "run accepts a pinned scope and defaults to no preview")
        for invalid in [
            batchJSON.replacingOccurrences(of: "\"tab_id\":0,", with: ""),
            batchJSON.replacingOccurrences(of: "\"tab_id\":0", with: "\"tab_id\":true"),
            batchJSON.replacingOccurrences(of: "\"main\"", with: "\"child\""),
            batchJSON.replacingOccurrences(of: "\"click\"", with: "\"execute_js\""),
        ] {
            check(BrowserActionInput.parse(from: invalid) == nil, "invalid batch input is rejected")
        }
        for stop in ["stale_ref", "navigation", "takeover"] {
            let batchManager = BrowserUseManager()
            var dispatched = 0
            batchManager.webView.batchReply = { [weak batchManager] kind in
                if kind != "step" { return ["status": "ok"] }
                dispatched += 1
                if dispatched == 1 {
                    if stop == "navigation" { batchManager?.navigationForTest() }
                    if stop == "takeover" { batchManager?.requestUserTakeover() }
                    return ["status": "ok", "applied": true]
                }
                return ["status": "stale_ref"]
            }
            let result = try await batchManager.execute(action: input(batchJSON))
            check(!result.success && result.batchReport?.stopReason == stop, "reports batch stop reason")
            check(result.batchReport?.completedSteps == [0], "reports the applied step exactly once")
            check(dispatched == (stop == "stale_ref" ? 2 : 1), "does not dispatch after interruption")
            check(batchManager.webView.reads == 0, "batch never runs legacy settling")
        }
        for status in ["ok", "timeout"] {
            let batchManager = BrowserUseManager()
            batchManager.webView.batchReply = { kind in
                kind == "step" ? ["status": status, "applied": true] : ["status": "ok"]
            }
            let typeJSON = #"""
            {"action":"run","tab_id":0,"document_version":"d","frame_id":"main","steps":[{"action":"type","ref":"e1","text":""}]}
            """#
            let result = try await batchManager.execute(action: input(typeJSON))
            check(result.batchReport?.completedSteps == [0], "type dispatch remains confirmed")
            check(result.batchReport?.failedStep == (status == "timeout" ? 0 : nil), "reports type timeout with confirmed progress")
            check(result.batchReport?.uncertainStep == nil, "does not treat confirmed input as uncertain")
            check(batchManager.legacyKeyboardReleases == 0, "batch does not enqueue unguarded keyboard release")
        }
        let manager = BrowserUseManager()
        let collected = try await manager.execute(action: fast)
        check(collected.text.contains("fixture-items:1,2,3"), "collection payload retained")
        check(manager.webView.reads == 0 && manager.webView.snapshots == 0, "fast mode skips only final observation/preview")
        let noPreview = try await manager.execute(action: input("{\"action\":\"type\",\"preview\":\"none\"}"))
        check(noPreview.imageFilePath == nil && noPreview.base64Image == nil, "no stale image")
        check(manager.webView.reads > 0 && manager.webView.snapshots == 0, "preview none retains DOM observation")
        let standard = try await manager.execute(action: normal)
        check(standard.imageFilePath != nil && manager.webView.snapshots == 1, "default retains implicit image")
        let screenshot = try await manager.execute(action: input("{\"action\":\"screenshot\",\"preview\":\"none\"}"))
        check(screenshot.base64Image != nil && manager.explicitScreenshots == 1, "explicit screenshot unaffected")
        for phase in ["setup", "poll", "read"] {
            let stalled = BrowserUseManager(); stalled.webView.hangAt = phase
            let start = ProcessInfo.processInfo.systemUptime
            do { _ = try await stalled.summaryForTest(timeout: phase == "read" ? 1.8 : 0.8); preconditionFailure("missing timeout") }
            catch is BrowserUseManager.JSEvalTimeout {}
            check(ProcessInfo.processInfo.systemUptime - start < 3, "shared deadline bounds " + phase)
            stalled.webView.releasePending()
        }
        let interrupted = BrowserUseManager(); interrupted.webView.hangAt = "setup"
        let action = Task { try await interrupted.execute(action: normal) }
        try await Task.sleep(nanoseconds: 30_000_000)
        interrupted.requestUserTakeover()
        let interruptedResult = try await action.value
        check(interruptedResult.success && interrupted.performed == 1, "executed action remains executed")
        check(interruptedResult.text.contains("interrupted") && interrupted.webView.snapshots == 0, "takeover cancels postprocessing")
        interrupted.webView.releasePending()
        interrupted.endUserTakeover()
        let cancelled = BrowserUseManager(); cancelled.webView.hangAt = "setup"
        let cancelledAction = Task { try await cancelled.execute(action: normal) }
        try await Task.sleep(nanoseconds: 30_000_000); cancelledAction.cancel()
        do { _ = try await cancelledAction.value; preconditionFailure("cancellation swallowed") } catch is CancellationError {}
        check(cancelled.webView.snapshots == 0, "cancelled action does not snapshot")
        cancelled.webView.releasePending()
        let previewing = BrowserUseManager(); previewing.webView.hangAt = "snapshot"
        previewing.webView.frame.size.width = 640
        let previewAction = Task { try await previewing.execute(action: normal) }
        for _ in 0..<300 {
            if previewing.webView.snapshots > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        check(previewing.webView.snapshots == 1, "reached actual preview wait")
        previewing.requestUserTakeover()
        let previewResult = try await previewAction.value
        check(previewResult.success && previewResult.imageFilePath == nil, "cancelled preview supplies no stale image")
        check(previewing.webView.frame.width == 390, "viewport restored on cancellation")
        previewing.webView.releasePending()
        let navigating = BrowserUseManager()
        let navigationWait = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                navigating.navigationContinuation = continuation
            }
        }
        for _ in 0..<100 {
            if navigating.navigationContinuation != nil { break }
            await Task.yield()
        }
        check(navigating.navigationContinuation != nil, "navigation wait installed")
        navigating.requestUserTakeover()
        do { try await navigationWait.value; preconditionFailure("navigation wait not interrupted") }
        catch is BrowserUseManager.UserTakeoverRequested {}
        check(navigating.webView.url?.absoluteString == "https://fixture.invalid/", "navigation takeover preserves page")
        let pool = BrowserTabPool(); pool.tabs = [.init(manager: manager)]
        check(!pool.isAgentBrowsing, "15s reservation alone does not lock UI")
        let oldGeneration = pool.generationForTest()
        pool.setExecutingForTest(1); pool.beginUserTakeover()
        check(pool.isUserTakeoverActive && pool.isTakeoverPending, "immediate pending feedback")
        check(!pool.queuedAction(generation: oldGeneration).success, "queued action blocked")
        pool.setExecutingForTest(0)
        check(!pool.isTakeoverPending && pool.isUserTakeoverActive, "manual control after action drains")
        let a = Task { await pool.waitForUserTakeover() }
        let b = Task { await pool.waitForUserTakeover() }
        await Task.yield(); a.cancel(); await a.value
        check(pool.isUserTakeoverActive, "one helper cancellation cannot end takeover")
        pool.endUserTakeover(); await b.value
        check(!pool.isUserTakeoverActive, "all shared waiters resume on end")
        check(!pool.queuedAction(generation: oldGeneration).success, "stale queued call rejected after dismissal")
        pool.hasSecureInput = true; pool.beginUserTakeover()
        check(!pool.isUserTakeoverActive, "native secure interaction stays separate")
        print("PASS: \(checks) extracted production Swift automation assertions (fake WebKit)")
    }
}

import Foundation
import CoreFoundation

// MARK: - Browser Action Enum

enum BrowserAction: String, CaseIterable {
    case navigate
    case observe
    case run
    case screenshot
    case click
    case type
    case secureInput = "secure_input"
    case getText = "get_text"
    case scroll
    case getPageInfo = "get_page_info"
    case executeJS = "execute_js"
    case findElements = "find_elements"
    case hover
    case getReadable = "get_readable"
    case setUserAgent = "set_user_agent"
    case setViewport = "set_viewport"
    case getBackbone = "get_backbone"
    case fetch
    case newTab = "new_tab"
    case closeTab = "close_tab"
    case listTabs = "list_tabs"
    case getCookies = "get_cookies"
    case setCookies = "set_cookies"
    case scrollAndCollect = "scroll_and_collect"
    case waitForDomStable = "wait_for_dom_stable"
}

// MARK: - Browser Action Input

struct BrowserActionInput {
    let action: BrowserAction
    let url: String?
    let selector: String?
    let text: String?
    let coordinateX: Int?
    let coordinateY: Int?
    let direction: ScrollDirection?
    let amount: Int?
    let script: String?
    let userAgent: UserAgentProfile?
    let maxDepth: Int?
    let tabId: Int?
    var scrollCount: Int? = nil
    var itemSelector: String? = nil
    var keywords: [String]? = nil
    var fuzzy: Bool? = nil
    var timeout: Int? = nil
    /// Custom viewport width in CSS pixels for `set_viewport`.
    var viewportWidth: Int? = nil
    /// Custom viewport height in CSS pixels for `set_viewport`.
    var viewportHeight: Int? = nil
    /// When true with `set_viewport`, clear the session-level viewport
    /// override and fall back to the global setting.
    var viewportReset: Bool? = nil
    /// When true with `screenshot`, capture the entire scrollable page by
    /// temporarily resizing the WebView to `document.documentElement.scrollHeight`.
    /// Default false captures only the current viewport.
    var fullPage: Bool? = nil
    /// Cookies to write (set_cookies). Each entry is a loosely-typed dict with
    /// keys: name, value (required), and optional domain, path, secure,
    /// http_only, expires (Unix seconds).
    var cookies: [[String: Any]]? = nil
    /// The `user_agent` argument exactly as the caller sent it, kept so a
    /// `set_user_agent` with a value `userAgent` could not be parsed from can
    /// name that value in its error instead of silently picking a profile.
    var userAgentRaw: String? = nil
    var secretKind: String? = nil
    var purpose: String? = nil
    var preview: Preview = .default
    var resultMode: ResultMode = .standard
    var batchRequest: BrowserBatchRequest? = nil

    enum Preview: String { case `default`, none }
    enum ResultMode: String { case standard, collected }

    enum ScrollDirection: String {
        case up, down
    }

    static func parse(from json: String) -> BrowserActionInput? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionStr = dict["action"] as? String,
              let action = BrowserAction(rawValue: actionStr),
              let preview = Preview(rawValue: dict["preview"] as? String ?? (action == .observe || action == .run ? "none" : "default")),
              let resultMode = ResultMode(rawValue: dict["result_mode"] as? String ?? "standard"),
              dict["preview"] == nil || dict["preview"] is String,
              dict["result_mode"] == nil || dict["result_mode"] is String else {
            return nil
        }

        guard resultMode != .collected || (action == .scrollAndCollect && preview == .none) else {
            return nil
        }

        let batchRequest: BrowserBatchRequest?
        if action == .observe || action == .run {
            guard let parsed = BrowserBatchRequest.parse(action: action, dict: dict, preview: preview) else { return nil }
            batchRequest = parsed
        } else {
            batchRequest = nil
        }

        return BrowserActionInput(
            action: action,
            url: dict["url"] as? String,
            selector: dict["selector"] as? String,
            text: dict["text"] as? String,
            coordinateX: dict["coordinate_x"] as? Int,
            coordinateY: dict["coordinate_y"] as? Int,
            direction: (dict["direction"] as? String).flatMap(ScrollDirection.init),
            amount: dict["amount"] as? Int,
            script: dict["script"] as? String,
            userAgent: UserAgentProfile.parse(dict["user_agent"] as? String),
            maxDepth: dict["max_depth"] as? Int,
            tabId: dict["tab_id"] as? Int,
            scrollCount: dict["scroll_count"] as? Int,
            itemSelector: dict["item_selector"] as? String,
            keywords: {
                if let arr = dict["keywords"] as? [String] {
                    let tokens = arr.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    return tokens.isEmpty ? nil : tokens
                } else if let str = dict["keywords"] as? String {
                    let tokens = str.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    return tokens.isEmpty ? nil : tokens
                }
                return nil
            }(),
            fuzzy: dict["fuzzy"] as? Bool,
            timeout: dict["timeout"] as? Int,
            viewportWidth: dict["viewport_width"] as? Int,
            viewportHeight: dict["viewport_height"] as? Int,
            viewportReset: dict["reset"] as? Bool,
            fullPage: dict["full_page"] as? Bool,
            cookies: Self.parseCookies(dict["cookies"]),
            userAgentRaw: dict["user_agent"] as? String,
            secretKind: dict["secret_kind"] as? String,
            purpose: dict["purpose"] as? String,
            preview: preview,
            resultMode: resultMode,
            batchRequest: batchRequest
        )
    }

    /// `cookies` may arrive either as a real JSON array (`[[String: Any]]`) or —
    /// because the tool schema can only type it as a string — as a JSON-encoded
    /// STRING like `"[{\"name\":...}]"`. Accept both so a schema-faithful model
    /// (which emits the string form) isn't silently dropped to empty.
    private static func parseCookies(_ raw: Any?) -> [[String: Any]]? {
        if let arr = raw as? [[String: Any]] { return arr }
        if let str = raw as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return nil
            }
            return arr
        }
        return nil
    }
}

// MARK: - Same-document automation input

enum BrowserBatchRequest {
    struct Condition {
        enum Kind: String { case visible, enabled, urlContains = "url_contains" }
        let kind: Kind
        let value: String

        var arguments: [String: Any] {
            ["kind": kind.rawValue, kind == .urlContains ? "value" : "selector": value]
        }

        static func parse(_ raw: Any) -> Condition? {
            guard let object = BrowserBatchRequest.jsonValue(raw) as? [String: Any],
                  let key = object["kind"] as? String, let kind = Kind(rawValue: key),
                  let value = BrowserBatchRequest.boundedString(object[kind == .urlContains ? "value" : "selector"], limit: 256) else { return nil }
            return Condition(kind: kind, value: value)
        }
    }

    struct Step {
        enum Action: String { case click, type }
        let action: Action
        let ref: String
        let text: String?
        let until: Condition?

        static func parse(_ object: [String: Any]) -> Step? {
            guard let key = object["action"] as? String, let action = Action(rawValue: key),
                  let ref = BrowserBatchRequest.boundedString(object["ref"], limit: 32) else { return nil }
            let text = object["text"] as? String
            let until = object["until"].flatMap(Condition.parse)
            guard object["until"] == nil || until != nil else { return nil }
            switch action {
            case .click: guard object["text"] == nil else { return nil }
            case .type: guard let text, text.utf16.count <= 512 else { return nil }
            }
            return Step(action: action, ref: ref, text: text, until: until)
        }
    }

    struct Run {
        let version: String
        let steps: [Step]
        let until: Condition?
        let timeout: TimeInterval
    }

    case observe(selector: String?)
    case run(Run)

    static let invalidInputMessage = "Invalid browser_use input. For run, provide tab_id, document_version, frame_id=main and 1–12 click/type steps with refs from observe. Conditions are visible/enabled (selector) or url_contains (value); timeout is 100–15000 ms. For scroll_and_collect, collected requires preview=none."

    static func parse(action: BrowserAction, dict: [String: Any], preview: BrowserActionInput.Preview) -> Self? {
        if let tab = dict["tab_id"], integer(tab).map({ $0 >= 0 }) != true { return nil }
        if action == .observe {
            let selector = boundedString(dict["selector"], limit: 256)
            guard preview == .none, dict["selector"] == nil || selector != nil else { return nil }
            return .observe(selector: selector)
        }
        guard dict["tab_id"] != nil, dict["frame_id"] as? String == "main",
              let version = boundedString(dict["document_version"], limit: 64),
              let rawSteps = jsonValue(dict["steps"]) as? [[String: Any]],
              (1...12).contains(rawSteps.count) else { return nil }
        let steps = rawSteps.compactMap(Step.parse)
        let until = dict["until"].flatMap(Condition.parse)
        let timeout = dict["timeout"].map { integer($0) ?? -1 } ?? 8_000
        guard steps.count == rawSteps.count, dict["until"] == nil || until != nil,
              (100...15_000).contains(timeout) else { return nil }
        return .run(Run(version: version, steps: steps, until: until, timeout: Double(timeout) / 1_000))
    }

    private static func boundedString(_ raw: Any?, limit: Int) -> String? {
        guard let s = raw as? String, s.utf16.count <= limit,
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    private static func integer(_ raw: Any) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return raw as? Int
    }

    private static func jsonValue(_ raw: Any?) -> Any? {
        guard let string = raw as? String else { return raw }
        guard string.utf8.count <= 48_000 else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(string.utf8))
    }
}

struct BrowserBatchReport {
    var completedSteps: [Int] = []
    var failedStep: Int?
    var uncertainStep: Int?
    var stopReason = "completed"
    var observation: [String: Any]?

    var payload: [String: Any] {
        var result: [String: Any] = ["completedSteps": completedSteps, "stopReason": stopReason]
        result["failedStep"] = failedStep
        result["uncertainStep"] = uncertainStep
        result["observation"] = observation
        return result
    }

    func result(previewPath: String? = nil) -> BrowserActionResult {
        var text = Self.json(payload)
        if stopReason != "completed" {
            text += "\nObserve the current page before continuing; do not blindly replay the batch."
        }
        return BrowserActionResult(text: text, success: stopReason == "completed",
                                   imageFilePath: previewPath, batchReport: self)
    }

    static func json(_ payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - User Agent Profile

enum UserAgentProfile: String {
    case mobileSafari = "mobile_safari"
    case desktopSafari = "desktop_safari"
    case custom = "custom"

    /// Returns a UA string, or `nil` for `.custom` (caller uses the custom string stored externally).
    var userAgentString: String? {
        switch self {
        case .custom:
            return nil
        case .desktopSafari:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        case .mobileSafari:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        }
    }

    var displayName: String {
        switch self {
        case .desktopSafari: return "Desktop Safari"
        case .mobileSafari: return "Mobile Safari"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .desktopSafari: return "desktopcomputer"
        case .mobileSafari: return "iphone"
        case .custom: return "pencil.line"
        }
    }

    /// Logical viewport size for the profile. Only takes effect for headless
    /// agent usage — once the WKWebView is embedded in SwiftUI its bounds are
    /// driven by the container. Desktop rendering in the visible browser is
    /// forced separately via a viewport-meta override script.
    var viewportSize: (width: Int, height: Int) {
        switch self {
        case .desktopSafari: return (1280, 800)
        case .mobileSafari, .custom: return (390, 844)
        }
    }
}

// MARK: - User Agent Profile: arguments and the panel icon

extension UserAgentProfile {
    /// Parse a `user_agent` argument. Accepts the raw values plus the short
    /// aliases models reach for (`desktop`, `mobile`), ignoring case, outer
    /// whitespace and `-` vs `_`. Returns nil for a missing or unknown value:
    /// the caller reports an error, it does not fall back to a profile.
    /// (An unknown value used to become mobile Safari without a word, so
    /// `user_agent: "desktop"` switched the browser to MOBILE.)
    static func parse(_ raw: String?) -> UserAgentProfile? {
        guard let raw else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch key {
        case "desktop": return .desktopSafari
        case "mobile": return .mobileSafari
        default: return UserAgentProfile(rawValue: key)
        }
    }

    /// Error text for a `set_user_agent` whose `user_agent` is missing or not
    /// one of the accepted values.
    static func invalidArgumentMessage(raw: String?) -> String {
        let got = raw.map { "\"\($0)\" is not a user agent profile" } ?? "user_agent is missing"
        return "set_user_agent: \(got). Use desktop_safari or mobile_safari (aliases: desktop, mobile). Nothing was changed."
    }

    /// Which profile the browser panel's title icon stands for: the selected
    /// tab's own profile, because that is what the page on screen was loaded
    /// with; the global default only when no tab is open yet.
    static func panelProfile(activeTab: UserAgentProfile?, globalDefault: UserAgentProfile) -> UserAgentProfile {
        activeTab ?? globalDefault
    }
}

// MARK: - Browser Action Result

struct BrowserActionResult {
    var text: String
    let success: Bool
    /// Base64-encoded image data for the API (vision).
    let base64Image: String?
    /// Local file path where the screenshot/image was saved to disk.
    let imageFilePath: String?
    /// Raw downloaded file data (for fetch action).
    let fetchedFileData: Data?
    /// Determined filename for the fetched file (for fetch action).
    let fetchedFileName: String?
    /// The page URL at the time this action was executed.
    var pageURL: String?
    /// The tab id this action actually ran on. Stamped by `BrowserTabPool.execute`
    /// at the point of dispatch using the verified `targetId`, NOT the global
    /// `selectedTabId` — which is overwritten when the fan-out branch spawns
    /// a fresh tab for a concurrent navigate. Without this, the agent had to
    /// guess tab_id for its follow-up reads/scrolls and routinely picked the
    /// wrong one, sometimes surfacing as empty get_text results.
    /// [T-ios-browser-result-tab-id]
    var tabId: Int?
    var batchReport: BrowserBatchReport?

    init(text: String, success: Bool = true, base64Image: String? = nil, imageFilePath: String? = nil,
         fetchedFileData: Data? = nil, fetchedFileName: String? = nil, pageURL: String? = nil,
         tabId: Int? = nil, batchReport: BrowserBatchReport? = nil) {
        self.text = text
        self.success = success
        self.base64Image = base64Image
        self.imageFilePath = imageFilePath
        self.fetchedFileData = fetchedFileData
        self.fetchedFileName = fetchedFileName
        self.pageURL = pageURL
        self.tabId = tabId
        self.batchReport = batchReport
    }

    static func error(_ message: String) -> BrowserActionResult {
        BrowserActionResult(text: "Error: \(message)", success: false)
    }
}

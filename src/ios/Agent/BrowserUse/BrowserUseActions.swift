import Foundation

// MARK: - Browser Action Enum

enum BrowserAction: String, CaseIterable {
    case navigate
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

extension BrowserAction {
    var displayTitle: String {
        switch self {
        case .navigate: return AppLocalized("Navigating")
        case .screenshot: return AppLocalized("Taking screenshot")
        case .click: return AppLocalized("Clicking")
        case .type: return AppLocalized("Typing")
        case .secureInput: return AppLocalized("Secure input")
        case .getText: return AppLocalized("Reading text")
        case .scroll: return AppLocalized("Scrolling")
        case .getPageInfo: return AppLocalized("Reading page info")
        case .executeJS: return AppLocalized("Executing script")
        case .findElements: return AppLocalized("Finding elements")
        case .hover: return AppLocalized("Hovering")
        case .getReadable: return AppLocalized("Reading page")
        case .setUserAgent: return AppLocalized("Setting user agent")
        case .setViewport: return AppLocalized("Setting viewport")
        case .getBackbone: return AppLocalized("Reading page structure")
        case .fetch: return AppLocalized("Downloading file")
        case .newTab: return AppLocalized("Opening new tab")
        case .closeTab: return AppLocalized("Closing tab")
        case .listTabs: return AppLocalized("Viewing tabs")
        case .getCookies: return AppLocalized("Reading cookies")
        case .setCookies: return AppLocalized("Writing cookies")
        case .scrollAndCollect: return AppLocalized("Scrolling and collecting")
        case .waitForDomStable: return AppLocalized("Waiting for page")
        }
    }

    static func displayTitle(for rawValue: String) -> String {
        BrowserAction(rawValue: rawValue)?.displayTitle ?? rawValue
    }

    static var stepLanguage: String {
        let selected = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        return selected.isEmpty
            ? Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
            : selected
    }

    // A site-first title can end in a product or file type like PDF.
    // Exclude common English browser commands from the site prefix instead.
    private static let chineseStepTitlePattern =
        #"(?i)^[^\p{L}\p{N}]*(?:\p{Han}|\p{N}+(?:[.,]\p{N}+)?\s*\p{Han}|"#
        + #"(?!(?:click|open|read|view|check|find|search|wait|type|enter|fill|scroll|switch|select|"#
        + #"press|close|load|reload|refresh|take|run|execute|go|navigate|visit|download|hover|expand|submit|list|inspect|please)"#
        + #"(?:s|ed|ing)?(?![\p{Latin}\p{N}_]))"#
        + #"[\p{Latin}\p{N}][\p{Latin}\p{N} ._&+/-]*[:：]?\s*\p{Han}{2})"#

    /// Titles from the model are optional, including on existing chat history.
    static func stepTitle(for rawValue: String, summary: String?, language: String = BrowserAction.stepLanguage) -> String {
        let title = String((summary ?? "").prefix(96)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if !title.isEmpty,
           !language.lowercased().hasPrefix("zh") ||
            title.range(of: chineseStepTitlePattern, options: .regularExpression) != nil {
            return title
        }
        if rawValue == BrowserAction.executeJS.rawValue { return AppLocalized("Interacting with page") }
        return BrowserAction(rawValue: rawValue)?.displayTitle ?? AppLocalized("Browser action")
    }
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
    var toolTitle: String? = nil

    enum ScrollDirection: String {
        case up, down
    }

    static func parse(from json: String) -> BrowserActionInput? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionStr = dict["action"] as? String,
              let action = BrowserAction(rawValue: actionStr) else {
            return nil
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
            toolTitle: dict["tool_title"] as? String
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

    init(text: String, success: Bool = true, base64Image: String? = nil, imageFilePath: String? = nil,
         fetchedFileData: Data? = nil, fetchedFileName: String? = nil, pageURL: String? = nil,
         tabId: Int? = nil) {
        self.text = text
        self.success = success
        self.base64Image = base64Image
        self.imageFilePath = imageFilePath
        self.fetchedFileData = fetchedFileData
        self.fetchedFileName = fetchedFileName
        self.pageURL = pageURL
        self.tabId = tabId
    }

    static func error(_ message: String) -> BrowserActionResult {
        BrowserActionResult(text: "Error: \(message)", success: false)
    }
}

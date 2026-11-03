
import AppKit
import Foundation
import WebKit

@MainActor
private final class BatchTestPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let world = WKContentWorld.world(name: "OpenMinis.BrowserBatch.Tests")
    var navigation: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ html: String, path: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "https://fixture.invalid/\(path)")!)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.navigation?.resume()
        self.navigation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: error)
        self.navigation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: error)
        self.navigation = nil
    }

    func command(_ kind: String, args: [String: Any], action: BrowserBatchRequest.Step.Action? = nil,
                 deadline: Double? = nil) async throws -> [String: Any] {
        var payload = args
        payload["runId"] = "run-a"
        payload["deadline"] = deadline ?? (Date().timeIntervalSince1970 * 1_000 + 2_000)
        let value = try await webView.callAsyncJavaScript(
            BrowserUseJS.batchCommand(install: kind == "observe", action: action),
            arguments: ["kind": kind, "epoch": "0", "payload": payload], in: nil, contentWorld: world
        )
        let raw = value as! String
        return try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
    }
}

@main
struct BrowserBatchWebKitTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let page = BatchTestPage()
        try await page.load("""
        <form id="form">
          <input id="q" aria-label="Query" value="old query">
          <input id="other" aria-label="Other">
          <button id="submit" type="submit">Search</button>
        </form>
        <script>
          window.__minisBrowserBatch = {command: () => {throw Error('page world should not run the batch')}};
          const query = document.querySelector('#q');
          let appValue = query.value;
          window.queryBlurs = [];
          window.readQueryState = () => appValue;
          query.addEventListener('input', () => { appValue = query.value; });
          query.addEventListener('blur', event => queryBlurs.push(event.isTrusted));
          document.querySelector('#form').onsubmit = event => {
            event.preventDefault();
            document.querySelector('#submit').remove();
            const result = document.createElement('p');
            result.id = 'done';
            result.textContent = appValue;
            document.body.append(result);
          };
        </script>
        """, path: "start")
        let observed = try await page.command("observe", args: ["version": "a"])
        let observation = observed["observation"] as! [String: Any]
        let elements = observation["elements"] as! [[String: Any]]
        let input = elements.first { $0["name"] as? String == "Query" }!["ref"] as! String
        let submit = elements.first { $0["name"] as? String == "Search" }!["ref"] as! String
        let begun = try await page.command("begin", args: ["version": "a"])
        precondition(begun["status"] as? String == "ok")
        let typed = try await page.command("step", args: [
            "version": "a", "ref": input, "action": "type", "text": "quote ' and slash \\",
        ], action: .type)
        precondition(typed["applied"] as? Bool == true)
        let typedValue = try await page.webView.evaluateJavaScript("window.readQueryState()")
        precondition(typedValue as? String == "quote ' and slash \\")
        let activeAfterType = try await page.webView.evaluateJavaScript("document.activeElement.id")
        precondition(activeAfterType as? String == "")
        let blurEvents = try await page.webView.evaluateJavaScript("JSON.stringify(window.queryBlurs)")
        precondition(blurEvents as? String == "[true]")
        let cleared = try await page.command("step", args: [
            "version": "a", "ref": input, "action": "type", "text": "",
        ], action: .type)
        precondition(cleared["status"] as? String == "ok" && cleared["applied"] as? Bool == true)
        let clicked = try await page.command("step", args: [
            "version": "a", "ref": submit, "action": "click",
            "goal": ["kind": "visible", "selector": "#done"],
        ], action: .click)
        precondition(clicked["status"] as? String == "ok" && clicked["applied"] as? Bool == true)
        let text = try await page.webView.evaluateJavaScript("document.querySelector('#done').textContent")
        precondition(text as? String == "")

        _ = try await page.webView.evaluateJavaScript("""
        document.querySelector('#q').addEventListener('change',
            () => document.querySelector('#other').focus(), {once: true});
        """)
        let transferred = try await page.command("step", args: [
            "version": "a", "ref": input, "action": "type", "text": "move focus",
        ], action: .type)
        precondition(transferred["status"] as? String == "ok")
        let activeAfterTransfer = try await page.webView.evaluateJavaScript("document.activeElement.id")
        precondition(activeAfterTransfer as? String == "other")
        let afterTransfer = try await page.webView.evaluateJavaScript("JSON.stringify(window.queryBlurs)")
        precondition(afterTransfer as? String == "[true,true,true]")

        let deadline = Date().timeIntervalSince1970 * 1_000 + 1_000
        _ = try await page.webView.evaluateJavaScript("""
        document.querySelector('#q').addEventListener('change', () => {
            while (Date.now() <= \(deadline)) {}
        }, {once: true});
        """)
        let late = try await page.command("step", args: [
            "version": "a", "ref": input, "action": "type", "text": "before deadline",
        ], action: .type, deadline: deadline)
        precondition(late["status"] as? String == "timeout" && late["applied"] as? Bool == true)
        let activeAfterDeadline = try await page.webView.evaluateJavaScript("document.activeElement.id")
        precondition(activeAfterDeadline as? String == "q")
        let afterDeadline = try await page.webView.evaluateJavaScript("JSON.stringify(window.queryBlurs)")
        precondition(afterDeadline as? String == "[true,true,true]")

        try await page.load("<button>Replacement page</button>", path: "replacement")
        let stale = try await page.command("begin", args: ["version": "a"])
        precondition(stale["status"] as? String == "stale_document")
        print("PASS: real WKWebView isolated-world bridge, type/clear/submit, scoped blur, and navigation invalidation")
    }
}

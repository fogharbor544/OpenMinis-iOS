#!/usr/bin/env python3
"""Run the shipping capture/fill JavaScript inside an ephemeral macOS WKWebView."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Agent/BrowserUse/BrowserPasswords.swift').read_text(encoding='utf-8')
scripts = re.findall(r'callAsyncJavaScript\("""\n(.*?)\n\s*""", arguments:', source, re.S)
assert len(scripts) == 2
capture, fill = scripts
secure_fill = re.search(r'// BEGIN NativeSecureFillScript.*?static let fillScript = """\n(.*?)\n\s*"""', source, re.S).group(1)
program = '''import AppKit
import WebKit

@MainActor final class Page: NSObject, WKNavigationDelegate {
    let web: WKWebView
    var ready: CheckedContinuation<Void, Error>?
    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        super.init()
        web.navigationDelegate = self
    }
    func load(_ html: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            web.loadHTMLString(html, baseURL: URL(string: "https://example.com/login")!)
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready?.resume(); ready = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        ready?.resume(throwing: error); ready = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        ready?.resume(throwing: error); ready = nil
    }
}
@main struct BrowserForms {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let page = Page()
        let capture = """
''' + capture + '''
"""
        let fill = """
''' + fill + '''
"""
        let secureFill = """
''' + secure_fill + '''
"""
        let html = """
        <html><body><form onsubmit="window.submitted=true;return false">
        <input id="user" autocomplete="username"><input id="password" type="password">
        <button>Submit</button></form><script>
        window.events=[];window.submitted=false;
        for (const field of document.querySelectorAll('input')) {
            for (const type of ['input','change']) field.addEventListener(type,()=>window.events.push(field.id+':'+type));
        }
        </script></body></html>
        """
        try await page.load(html)
        let secret = UUID().uuidString
        let arguments: [String: Any] = ["origin": "https://example.com", "username": "test-user", "password": secret]
        let filled = try await page.web.callAsyncJavaScript(fill, arguments: arguments, in: nil, contentWorld: .defaultClient)
        precondition(filled as? Bool == true)
        let values = try await page.web.evaluateJavaScript("[document.querySelector('#user').value,document.querySelector('#password').value]") as! [String]
        precondition(values == ["test-user", secret])
        let events = try await page.web.evaluateJavaScript("window.events") as! [String]
        precondition(events == ["user:input", "user:change", "password:input", "password:change"])
        let submitted = try await page.web.evaluateJavaScript("window.submitted") as! Bool
        precondition(!submitted)
        let captured = try await page.web.callAsyncJavaScript(capture, arguments: ["origin": "https://example.com"], in: nil, contentWorld: .defaultClient) as! [String: String]
        precondition(captured["username"] == "test-user" && captured["password"] == secret)
        var mismatch = arguments
        mismatch["origin"] = "https://different.example"
        let rejected = try await page.web.callAsyncJavaScript(fill, arguments: mismatch, in: nil, contentWorld: .defaultClient)
        precondition(rejected as? Bool == false)
        let wrongCapture = try await page.web.callAsyncJavaScript(capture, arguments: ["origin": "https://different.example"], in: nil, contentWorld: .defaultClient)
        precondition(wrongCapture is NSNull)
        _ = try await page.web.evaluateJavaScript("document.querySelector('#password').autocomplete='new-password'")
        let signup = try await page.web.callAsyncJavaScript(fill, arguments: arguments, in: nil, contentWorld: .defaultClient)
        precondition(signup as? Bool == false)
        _ = try await page.web.evaluateJavaScript("document.querySelector('#password').autocomplete='current-password';document.querySelector('#password').readOnly=true")
        let readonly = try await page.web.callAsyncJavaScript(fill, arguments: arguments, in: nil, contentWorld: .defaultClient)
        precondition(readonly as? Bool == false)
        _ = try await page.web.evaluateJavaScript("document.querySelector('#password').readOnly=false;const extra=document.createElement('input');extra.type='password';document.body.append(extra)")
        let ambiguous = try await page.web.callAsyncJavaScript(fill, arguments: arguments, in: nil, contentWorld: .defaultClient)
        precondition(ambiguous as? Bool == false)
        try await page.load(html)
        let nativeArgs: [String: Any] = ["origin": "https://example.com", "selector": "#password", "secret": secret, "kind": "password"]
        let native = try await page.web.callAsyncJavaScript(secureFill, arguments: nativeArgs, in: nil, contentWorld: .defaultClient)
        precondition(native as? Bool == true)
        let nativeValue = try await page.web.evaluateJavaScript("document.querySelector('#password').value") as! String
        precondition(nativeValue == secret)
        _ = try await page.web.evaluateJavaScript("window.dispatchEvent(new Event('pagehide'))")
        let clearedValue = try await page.web.evaluateJavaScript("document.querySelector('#password').value") as! String
        precondition(clearedValue.isEmpty)
        var otpArgs = nativeArgs
        otpArgs["kind"] = "otp"
        _ = try await page.web.evaluateJavaScript("document.querySelector('#password').type='tel'")
        let otp = try await page.web.callAsyncJavaScript(secureFill, arguments: otpArgs, in: nil, contentWorld: .defaultClient)
        precondition(otp as? Bool == true)
        let masked = try await page.web.evaluateJavaScript("document.querySelector('#password').type") as! String
        precondition(masked == "password")
        otpArgs["origin"] = "https://other.example"
        let crossOrigin = try await page.web.callAsyncJavaScript(secureFill, arguments: otpArgs, in: nil, contentWorld: .defaultClient)
        precondition(crossOrigin as? Bool == false)
        print("PASS: real WebKit capture/fill, native password/OTP masking and erasure, no auto-submit, origin mismatch, invalid field rejection")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='minis-browser-forms-') as temp:
    temp = Path(temp)
    swift = temp / 'Forms.swift'
    swift.write_text(program, encoding='utf-8')
    binary = temp / 'form-tests'
    subprocess.run(['swiftc', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=90)

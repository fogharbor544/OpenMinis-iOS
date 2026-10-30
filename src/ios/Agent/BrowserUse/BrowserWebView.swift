import SwiftUI
import WebKit

/// The manager owns the WebView; UI hosts only mount it, never recreate it.
struct BrowserWebView: UIViewRepresentable {
    let manager: BrowserUseManager

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        mount(in: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) { mount(in: uiView) }

    private func mount(in container: UIView) {
        let webView = manager.webView
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}

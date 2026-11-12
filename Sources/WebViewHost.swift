import SwiftUI
import WebKit

struct WebViewHost: UIViewRepresentable {
    let tab: BrowserTab

    func makeUIView(context: Context) -> WKWebView {
        tab.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

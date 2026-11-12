import Foundation
import WebKit
import UIKit
import Combine

@MainActor final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    let id = UUID()
    let isPrivate: Bool
    let webView: WKWebView

    @Published var title: String = ""
    @Published var url: URL? = nil
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var desktopMode: Bool = false {
        didSet {
            guard desktopMode != oldValue else { return }
            webView.customUserAgent = desktopMode ? Self.desktopUserAgent : nil
            webView.reload()
        }
    }

    var pendingURL: URL? = nil
    var popupFilter: (WKNavigationAction) -> Bool = { _ in true }
    var onOpenInNewTab: ((URL) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    init(isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        setupObservations()
    }

    deinit {
        for observation in observations {
            observation.invalidate()
        }
    }

    private func setupObservations() {
        observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.progress = webView.estimatedProgress
            }
        })

        observations.append(webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.title = webView.title ?? ""
            }
        })

        observations.append(webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.url = webView.url
            }
        })

        observations.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.canGoBack = webView.canGoBack
            }
        })

        observations.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.canGoForward = webView.canGoForward
            }
        })

        observations.append(webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.isLoading = webView.isLoading
            }
        })
    }

    func load(_ url: URL) {
        pendingURL = nil
        self.url = url
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func stop() {
        webView.stopLoading()
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "http" || scheme == "https" || scheme == "about" {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if popupFilter(navigationAction) {
            if let url = navigationAction.request.url {
                onOpenInNewTab?(url)
            }
        }
        return nil
    }
}

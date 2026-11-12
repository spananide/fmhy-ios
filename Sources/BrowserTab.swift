import Foundation
import WebKit
import UIKit
import Combine

struct BlockedNavigation: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let reason: String

    init(id: UUID = UUID(), url: URL, reason: String) {
        self.id = id
        self.url = url
        self.reason = reason
    }
}

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
    @Published var adBlockActive: Bool = false
    @Published var blockedNavigation: BlockedNavigation? = nil

    var pendingURL: URL? = nil
    var popupFilter: (WKNavigationAction) -> Bool = { _ in true }
    var onOpenInNewTab: ((URL) -> Void)?
    var unsafeCheck: (@MainActor (URL) -> String?)?

    private var allowedUnsafeHosts: Set<String> = []
    private var lastPopupTime: Date?
    private var observations: [NSKeyValueObservation] = []

    init(isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        AdBlocker.shared.install(in: config.userContentController)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView

        super.init()

        self.adBlockActive = AdBlocker.shared.isEnabled

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
                self?.updateAdBlockActive()
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

    func proceedAnyway(_ blocked: BlockedNavigation) {
        if let host = Self.normalizeHost(blocked.url.host) {
            allowedUnsafeHosts.insert(host)
        }
        blockedNavigation = nil
        load(blocked.url)
    }

    func dismissBlocked() {
        blockedNavigation = nil
    }

    func toggleAdBlockForCurrentSite() {
        guard let host = Self.normalizeHost(webView.url?.host ?? self.url?.host), !host.isEmpty else {
            return
        }
        let currentlyAllowlisted = AdBlocker.shared.isAllowlisted(host: host)
        AdBlocker.shared.setAllowlisted(host, !currentlyAllowlisted)
        AdBlocker.shared.apply(to: webView.configuration.userContentController, host: host)
        updateAdBlockActive()
        webView.reload()
    }

    private func updateAdBlockActive() {
        let host = Self.normalizeHost(webView.url?.host ?? self.url?.host)
        adBlockActive = AdBlocker.shared.shouldBlock(host: host)
    }

    private static func normalizeHost(_ host: String?) -> String? {
        guard let host = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
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
        let isMain = navigationAction.targetFrame?.isMainFrame == true || navigationAction.targetFrame == nil

        if (scheme == "http" || scheme == "https") && isMain {
            let normalizedHost = Self.normalizeHost(url.host)
            AdBlocker.shared.apply(to: webView.configuration.userContentController, host: normalizedHost)

            if let check = unsafeCheck, let reason = check(url) {
                let hostKey = normalizedHost ?? (url.host?.lowercased() ?? "")
                if !allowedUnsafeHosts.contains(hostKey) {
                    self.blockedNavigation = BlockedNavigation(url: url, reason: reason)
                    decisionHandler(.cancel)
                    return
                }
            }
        }

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

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateAdBlockActive()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateAdBlockActive()
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
        guard let popupURL = navigationAction.request.url,
              !popupURL.absoluteString.isEmpty,
              popupURL.absoluteString != "about:blank" else {
            return nil
        }

        let currentHost = Self.normalizeHost(webView.url?.host ?? self.url?.host)
        if AdBlocker.shared.shouldBlock(host: currentHost) {
            if let last = lastPopupTime, Date().timeIntervalSince(last) < 2.0 {
                return nil
            }
        }

        if popupFilter(navigationAction) {
            lastPopupTime = Date()
            onOpenInNewTab?(popupURL)
        }
        return nil
    }
}

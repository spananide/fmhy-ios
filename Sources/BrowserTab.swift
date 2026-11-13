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
    static let minZoom: Double = 1.0
    static let maxZoom: Double = 5.0
    static let zoomStep: Double = 0.25

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
    @Published var lastDownloadStartedAt: Date? = nil
    @Published var zoom: Double = 1.0 {
        didSet {
            let clamped = Self.clampZoom(zoom)
            if zoom != clamped {
                zoom = clamped
                return
            }
            webView.pageZoom = CGFloat(clamped)
        }
    }

    var pendingURL: URL? = nil
    var popupFilter: (WKNavigationAction) -> Bool = { _ in true }
    var onOpenInNewTab: ((URL) -> Void)?
    var onOpenInBackground: ((URL) -> Void)?
    var onOpenInPrivate: ((URL) -> Void)?
    var onDownload: ((WKDownload, URL?) -> Void)?
    var unsafeCheck: (@MainActor (URL) -> String?)?
    weak var siteSettings: SiteSettingsStore?

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

    nonisolated static func normalizeHost(_ host: String?) -> String? {
        let norm = SiteSettingsStore.normalizeHost(host)
        return norm.isEmpty ? nil : norm
    }

    var canResetZoom: Bool {
        Self.canResetZoom(zoom)
    }

    func zoomIn() {
        zoom = Self.stepUpZoom(zoom)
    }

    func zoomOut() {
        zoom = Self.stepDownZoom(zoom)
    }

    func resetZoom() {
        zoom = 1.0
    }

    nonisolated static func clampZoom(_ level: Double) -> Double {
        min(max(level, minZoom), maxZoom)
    }

    nonisolated static func stepUpZoom(_ level: Double) -> Double {
        let eps = 1e-4
        let next = (floor((level + eps) / zoomStep) + 1) * zoomStep
        let rounded = (next * 1000).rounded() / 1000
        return clampZoom(rounded)
    }

    nonisolated static func stepDownZoom(_ level: Double) -> Double {
        let eps = 1e-4
        let next = (ceil((level - eps) / zoomStep) - 1) * zoomStep
        let rounded = (next * 1000).rounded() / 1000
        return clampZoom(rounded)
    }

    nonisolated static func zoomPercentage(_ level: Double) -> Int {
        Int((clampZoom(level) * 100).rounded())
    }

    nonisolated static func canResetZoom(_ level: Double) -> Bool {
        abs(level - 1.0) >= 0.005
    }

    func applyDarkPage() {
        let host = Self.normalizeHost(webView.url?.host ?? self.url?.host)
        let isDark = siteSettings?.config(for: host).darkPage ?? false
        let css = "html{filter:invert(1) hue-rotate(180deg)} img,video,picture,canvas{filter:invert(1) hue-rotate(180deg)}"
        if isDark {
            let js = """
            (function() {
                var el = document.getElementById('fmhy-dark-page-style');
                if (!el) {
                    el = document.createElement('style');
                    el.id = 'fmhy-dark-page-style';
                    el.textContent = '\(css)';
                    (document.head || document.documentElement).appendChild(el);
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            let js = """
            (function() {
                var el = document.getElementById('fmhy-dark-page-style');
                if (el) { el.remove(); }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel, preferences)
            return
        }

        let scheme = (url.scheme ?? "").lowercased()
        let isMain = navigationAction.targetFrame?.isMainFrame == true || navigationAction.targetFrame == nil

        if (scheme == "http" || scheme == "https") && isMain {
            let normalizedHost = Self.normalizeHost(url.host)
            AdBlocker.shared.apply(to: webView.configuration.userContentController, host: normalizedHost)

            if let config = siteSettings?.config(for: normalizedHost) {
                preferences.allowsContentJavaScript = config.javaScript
                let isDesktop = config.desktop || desktopMode
                preferences.preferredContentMode = isDesktop ? .desktop : .mobile
                webView.customUserAgent = isDesktop ? Self.desktopUserAgent : nil
            } else {
                preferences.allowsContentJavaScript = true
                preferences.preferredContentMode = desktopMode ? .desktop : .mobile
                webView.customUserAgent = desktopMode ? Self.desktopUserAgent : nil
            }

            if let check = unsafeCheck, let reason = check(url) {
                let hostKey = normalizedHost ?? (url.host?.lowercased() ?? "")
                if !allowedUnsafeHosts.contains(hostKey) {
                    self.blockedNavigation = BlockedNavigation(url: url, reason: reason)
                    decisionHandler(.cancel, preferences)
                    return
                }
            }
        }

        if scheme == "http" || scheme == "https" || scheme == "about" {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel, preferences)
                return
            }
            decisionHandler(.allow, preferences)
        } else {
            UIApplication.shared.open(url)
            decisionHandler(.cancel, preferences)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        if let http = navigationResponse.response as? HTTPURLResponse {
            let disposition = http.allHeaderFields.first { key, _ in
                (key as? String)?.caseInsensitiveCompare("Content-Disposition") == .orderedSame
            }?.value as? String
            if let disposition = disposition?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               disposition.hasPrefix("attachment") {
                decisionHandler(.download)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        lastDownloadStartedAt = Date()
        let sourceURL = download.originalRequest?.url ?? webView.url
        onDownload?(download, sourceURL)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        lastDownloadStartedAt = Date()
        let sourceURL = download.originalRequest?.url ?? webView.url
        onDownload?(download, sourceURL)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateAdBlockActive()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateAdBlockActive()
        webView.pageZoom = CGFloat(zoom)
        applyDarkPage()
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

    nonisolated static func hasRealAddress(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        let raw = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return false }
        if raw.lowercased().hasPrefix("javascript:") { return false }
        if raw == "#" || raw.lowercased().hasPrefix("about:blank") { return false }
        return true
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
    ) {
        guard let linkURL = elementInfo.linkURL, Self.hasRealAddress(linkURL) else {
            completionHandler(nil)
            return
        }

        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let openAction = UIAction(title: "Open", image: UIImage(systemName: "safari")) { _ in
                self?.load(linkURL)
            }
            let newTabAction = UIAction(title: "Open in new tab", image: UIImage(systemName: "plus.square")) { _ in
                self?.onOpenInNewTab?(linkURL)
            }
            let backgroundAction = UIAction(title: "Open in background tab", image: UIImage(systemName: "square.on.square")) { _ in
                self?.onOpenInBackground?(linkURL)
            }
            let privateAction = UIAction(title: "Open in private tab", image: UIImage(systemName: "shield")) { _ in
                self?.onOpenInPrivate?(linkURL)
            }
            let copyAction = UIAction(title: "Copy link", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = linkURL.absoluteString
            }
            let shareAction = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                guard let self = self else { return }
                let activityVC = UIActivityViewController(activityItems: [linkURL], applicationActivities: nil)
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = self.webView
                    popover.sourceRect = CGRect(x: self.webView.bounds.midX, y: self.webView.bounds.midY, width: 0, height: 0)
                }
                self.topViewController()?.present(activityVC, animated: true)
            }
            return UIMenu(title: linkURL.absoluteString, children: [
                openAction,
                newTabAction,
                backgroundAction,
                privateAction,
                copyAction,
                shareAction
            ])
        }

        completionHandler(config)
    }

    @MainActor
    private func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController?
        if let base = base {
            root = base
        } else {
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            root = windowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? windowScene?.windows.first?.rootViewController
        }

        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }

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
        if let config = siteSettings?.config(for: currentHost), !config.popups {
            return nil
        }

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

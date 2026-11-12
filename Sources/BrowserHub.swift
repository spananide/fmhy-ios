import Foundation
import Combine

@MainActor final class BrowserHub: ObservableObject {
    @Published var requestedTab: Int?
    @Published var safariTarget: SafariTarget?

    private weak var tabs: TabManager?

    init(tabs: TabManager) {
        self.tabs = tabs
    }

    func open(_ url: URL) {
        if UserDefaults.standard.bool(forKey: "openInSafari") {
            safariTarget = SafariTarget(url: url)
        } else {
            if let selected = tabs?.selected, selected.url == nil && selected.pendingURL == nil {
                selected.load(url)
            } else {
                _ = tabs?.newTab(url: url, isPrivate: false, select: true)
            }
            requestedTab = 4
        }
    }

    func open(_ urlString: String) {
        guard let target = SafariTarget(urlString: urlString) else { return }
        open(target.url)
    }
}

import Foundation
import Combine
import WebKit

private struct SavedTab: Codable {
    let url: String?
    let title: String
}

private struct SavedSession: Codable {
    let tabs: [SavedTab]
    let selectedIndex: Int?
}

@MainActor final class TabManager: ObservableObject {
    private let storageKey = "browser.tabs.v1"
    private var tabCancellables: [UUID: Set<AnyCancellable>] = [:]

    @Published var tabs: [BrowserTab] = []
    @Published var selectedId: UUID? = nil

    var unsafeCheck: (@MainActor (URL) -> String?)? {
        didSet {
            for tab in tabs {
                tab.unsafeCheck = unsafeCheck
            }
        }
    }

    var downloadHandler: ((WKDownload, URL?) -> Void)? {
        didSet {
            for tab in tabs {
                tab.onDownload = downloadHandler
            }
        }
    }

    var selected: BrowserTab? {
        tabs.first(where: { $0.id == selectedId })
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let session = try? JSONDecoder().decode(SavedSession.self, from: data),
           !session.tabs.isEmpty {
            var restoredTabs: [BrowserTab] = []
            let prefixTabs = Array(session.tabs.prefix(20))
            for saved in prefixTabs {
                let tab = BrowserTab(isPrivate: false)
                tab.title = saved.title
                if let urlString = saved.url, let url = URL(string: urlString) {
                    tab.url = url
                    tab.pendingURL = url
                }
                tab.unsafeCheck = unsafeCheck
                tab.onDownload = downloadHandler
                wireTab(tab)
                restoredTabs.append(tab)
            }
            self.tabs = restoredTabs

            let targetIndex: Int
            if let idx = session.selectedIndex, idx >= 0 && idx < restoredTabs.count {
                targetIndex = idx
            } else {
                targetIndex = 0
            }

            let selectedTab = restoredTabs[targetIndex]
            self.selectedId = selectedTab.id
            if let pending = selectedTab.pendingURL {
                selectedTab.load(pending)
            }
        }
    }

    @discardableResult
    func newTab(url: URL? = nil, isPrivate: Bool = false, select: Bool = true) -> BrowserTab {
        let tab = BrowserTab(isPrivate: isPrivate)
        tab.unsafeCheck = unsafeCheck
        tab.onDownload = downloadHandler
        wireTab(tab)
        if let url = url {
            tab.load(url)
        }
        tabs.append(tab)

        if select || selectedId == nil {
            self.selectedId = tab.id
        }

        enforceMaxTabs()
        save()
        return tab
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        tabCancellables.removeValue(forKey: tab.id)

        let isClosingSelected = (selectedId == tab.id)
        tabs.remove(at: index)

        if isClosingSelected {
            if tabs.isEmpty {
                selectedId = nil
            } else {
                let newIndex = min(index, tabs.count - 1)
                let newSelected = tabs[newIndex]
                selectedId = newSelected.id
                if let pending = newSelected.pendingURL {
                    newSelected.load(pending)
                }
            }
        }

        save()
    }

    func select(_ tab: BrowserTab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        selectedId = tab.id
        if let pending = tab.pendingURL {
            tab.load(pending)
        }
        save()
    }

    func closeAllPrivate() {
        let privateTabs = tabs.filter { $0.isPrivate }
        guard !privateTabs.isEmpty else { return }

        for tab in privateTabs {
            tabCancellables.removeValue(forKey: tab.id)
        }

        let isSelectedPrivate = selected?.isPrivate ?? false
        tabs.removeAll(where: { $0.isPrivate })

        if isSelectedPrivate {
            if let first = tabs.first {
                selectedId = first.id
                if let pending = first.pendingURL {
                    first.load(pending)
                }
            } else {
                selectedId = nil
            }
        }

        save()
    }

    private func wireTab(_ tab: BrowserTab) {
        tab.onOpenInNewTab = { [weak self] url in
            _ = self?.newTab(url: url, isPrivate: tab.isPrivate, select: true)
        }

        var cancellables = Set<AnyCancellable>()
        tab.$url.dropFirst().sink { [weak self] _ in
            self?.save()
        }.store(in: &cancellables)

        tab.$title.dropFirst().sink { [weak self] _ in
            self?.save()
        }.store(in: &cancellables)

        tab.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        tabCancellables[tab.id] = cancellables
    }

    private func enforceMaxTabs() {
        while tabs.count > 20 {
            if let oldestNonSelected = tabs.first(where: { $0.id != selectedId }) {
                close(oldestNonSelected)
            } else {
                break
            }
        }
    }

    private func save() {
        let nonPrivate = tabs.filter { !$0.isPrivate }
        let savedTabs = nonPrivate.map { tab in
            SavedTab(
                url: tab.url?.absoluteString ?? tab.pendingURL?.absoluteString,
                title: tab.title
            )
        }

        let selectedIndex: Int?
        if let selectedId = selectedId, let idx = nonPrivate.firstIndex(where: { $0.id == selectedId }) {
            selectedIndex = idx
        } else {
            selectedIndex = nil
        }

        let session = SavedSession(tabs: savedTabs, selectedIndex: selectedIndex)
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

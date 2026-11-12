import SwiftUI

@main
struct FMHYApp: App {
    @StateObject private var store: WikiStore
    @StateObject private var bookmarks = Bookmarks()
    @StateObject private var tabs: TabManager
    @StateObject private var hub: BrowserHub
    @StateObject private var changes: ChangesStore
    @StateObject private var follows: Follows

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let tabManager = TabManager()
        let wikiStore = WikiStore()
        let changesStore = ChangesStore()
        let followsStore = Follows()

        _tabs = StateObject(wrappedValue: tabManager)
        _hub = StateObject(wrappedValue: BrowserHub(tabs: tabManager))
        _store = StateObject(wrappedValue: wikiStore)
        _changes = StateObject(wrappedValue: changesStore)
        _follows = StateObject(wrappedValue: followsStore)

        Notifier.configure(changes: changesStore, follows: followsStore, store: wikiStore)
        Notifier.registerBackgroundRefresh()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(bookmarks)
                .environmentObject(tabs)
                .environmentObject(hub)
                .environmentObject(changes)
                .environmentObject(follows)
                .tint(fmhyPurple)
                .task {
                    await store.load()
                }
                .task {
                    await changes.load()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        Task { @MainActor in
                            let shouldRefresh: Bool
                            if let last = changes.lastFetched {
                                shouldRefresh = Date().timeIntervalSince(last) > 3600
                            } else {
                                shouldRefresh = true
                            }
                            if shouldRefresh {
                                await changes.refresh()
                                Notifier.notifyIfNeeded(
                                    changes: changes,
                                    follows: follows,
                                    sections: store.sections
                                )
                            }
                        }
                    case .background:
                        Notifier.scheduleBackgroundRefresh()
                    default:
                        break
                    }
                }
        }
    }
}

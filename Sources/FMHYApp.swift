import SwiftUI

@main
struct FMHYApp: App {
    @StateObject private var store = WikiStore()
    @StateObject private var bookmarks = Bookmarks()
    @StateObject private var tabs: TabManager
    @StateObject private var hub: BrowserHub

    init() {
        let tabManager = TabManager()
        _tabs = StateObject(wrappedValue: tabManager)
        _hub = StateObject(wrappedValue: BrowserHub(tabs: tabManager))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(bookmarks)
                .environmentObject(tabs)
                .environmentObject(hub)
                .tint(fmhyPurple)
                .task {
                    await store.load()
                }
        }
    }
}

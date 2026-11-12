import SwiftUI

@main
struct FMHYApp: App {
    @StateObject var store = WikiStore()
    @StateObject var bookmarks = Bookmarks()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(bookmarks)
                .tint(fmhyPurple)
                .task {
                    await store.load()
                }
        }
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: WikiStore
    @State private var selectedTab: Int

    init() {
        let initialTab = UserDefaults.standard.integer(forKey: "tab")
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        Group {
            if store.isLoading && store.entries.isEmpty {
                ProgressView("Loading wiki…")
            } else {
                TabView(selection: $selectedTab) {
                    HomeView()
                        .tabItem {
                            Label("Wiki", systemImage: "books.vertical")
                        }
                        .tag(0)

                    SearchView()
                        .tabItem {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .tag(1)

                    SavedView()
                        .tabItem {
                            Label("Saved", systemImage: "bookmark")
                        }
                        .tag(2)

                    CheckLinkView()
                        .tabItem {
                            Label("Check", systemImage: "checkmark.shield")
                        }
                        .tag(3)
                }
            }
        }
    }
}

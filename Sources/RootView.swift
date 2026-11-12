import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var hub: BrowserHub
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

                    BrowserView()
                        .tabItem {
                            Label("Browser", systemImage: "safari")
                        }
                        .tag(4)
                }
            }
        }
        .onChange(of: hub.requestedTab) { _, newValue in
            if let target = newValue {
                selectedTab = target
                hub.requestedTab = nil
            }
        }
        .fullScreenCover(item: $hub.safariTarget) { target in
            SafariView(url: target.url)
                .ignoresSafeArea()
        }
        .task {
            if let launchUrlString = UserDefaults.standard.string(forKey: "url"),
               let target = SafariTarget(urlString: launchUrlString) {
                hub.open(target.url)
            }
        }
    }
}

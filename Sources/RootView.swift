import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var hub: BrowserHub
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var changes: ChangesStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var settings: AppSettings
    @State private var selectedTab: Int

    init() {
        let rawTab = UserDefaults.standard.integer(forKey: "tab")
        let initialTab = (rawTab == 3) ? 1 : rawTab
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

                    BrowserView()
                        .tabItem {
                            Label("Browser", systemImage: "safari")
                        }
                        .tag(4)

                    ChangesView()
                        .tabItem {
                            Label("What's new", systemImage: "bell")
                        }
                        .badge(changes.newCount(followed: follows.sectionIds) > 0 ? changes.newCount(followed: follows.sectionIds) : 0)
                        .tag(5)
                }
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .tint(settings.accent.color)
        .dynamicTypeSize(settings.textSize.dynamicTypeSize)
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
        .fullScreenCover(isPresented: $settings.isShowingOnboarding) {
            OnboardingView()
                .environmentObject(settings)
        }
        .task {
            if let launchUrlString = UserDefaults.standard.string(forKey: "url"),
               let target = SafariTarget(urlString: launchUrlString) {
                hub.open(target.url)
            }
        }
        .task {
            _ = await AdBlocker.shared.compileAll()
        }
        .task(id: store.entries.count) {
            tabs.unsafeCheck = { url in
                let v = store.safeGuard?.check(url.absoluteString)
                return v?.status == .unsafe ? (v?.reason ?? "On the FMHY unsafe list") : nil
            }
        }
    }
}

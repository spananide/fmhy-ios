import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var hub: BrowserHub
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var changes: ChangesStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var downloadChecks: DownloadChecks
    @EnvironmentObject var checkPrefs: CheckPrefs
    @EnvironmentObject var vtSiteChecks: VtSiteChecks
    @EnvironmentObject var bookmarks: Bookmarks
    @ObservedObject private var shortcuts = AppShortcuts.shared
    @State private var selectedTab: Int

    init() {
        let rawTab = UserDefaults.standard.integer(forKey: "tab")
        let initialTab = (rawTab == 3) ? 1 : rawTab
        _selectedTab = State(initialValue: initialTab)
    }

    private var mainContent: some View {
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
    }

    private var layerOne: some View {
        mainContent
            .preferredColorScheme(settings.theme.colorScheme)
            .tint(settings.accent.color)
            .dynamicTypeSize(settings.textSize.dynamicTypeSize)
            .onChange(of: hub.requestedTab) { _, newValue in
                if let target = newValue {
                    selectedTab = target
                    hub.requestedTab = nil
                }
            }
    }

    private var layerTwo: some View {
        layerOne
            .fullScreenCover(item: $hub.safariTarget) { target in
                SafariView(url: target.url)
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $settings.isShowingOnboarding) {
                OnboardingView()
                    .environmentObject(settings)
            }
            .sheet(item: $shortcuts.activeSheet) { destination in
                sheetContent(for: destination)
            }
    }

    private var layerThree: some View {
        layerTwo
            .onAppear {
                shortcuts.hub = hub
            }
            .task {
                shortcuts.hub = hub
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

    var body: some View {
        layerThree
    }

    @ViewBuilder
    private func sheetContent(for destination: RootSheetDestination) -> some View {
        switch destination {
        case .checkLink:
            CheckLinkSheetContainer()
                .environmentObject(store)
                .environmentObject(downloadChecks)
                .environmentObject(vtSiteChecks)
                .environmentObject(bookmarks)
                .environmentObject(hub)
        case .downloads:
            DownloadsView()
                .environmentObject(downloads)
                .environmentObject(downloadChecks)
                .environmentObject(checkPrefs)
        }
    }
}

private struct CheckLinkSheetContainer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CheckLinkView()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
    }
}

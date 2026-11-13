import SwiftUI

@main
struct FMHYApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: WikiStore
    @StateObject private var bookmarks = Bookmarks()
    @StateObject private var tabs: TabManager
    @StateObject private var hub: BrowserHub
    @StateObject private var changes: ChangesStore
    @StateObject private var follows: Follows
    @StateObject private var settings = AppSettings()
    @StateObject private var downloads: DownloadManager
    @StateObject private var checkPrefs: CheckPrefs
    @StateObject private var scanStore: ScanStore
    @StateObject private var downloadChecks: DownloadChecks
    @StateObject private var vtSiteChecks: VtSiteChecks
    @StateObject private var homeLayoutStore = HomeLayoutStore()
    @StateObject private var visitTracker = VisitTracker()
    @StateObject private var siteSettings: SiteSettingsStore

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let tabManager = TabManager()
        let siteSettingsStore = SiteSettingsStore()
        tabManager.siteSettings = siteSettingsStore
        let wikiStore = WikiStore()
        let changesStore = ChangesStore()
        let followsStore = Follows()
        let checkPrefs = CheckPrefs()
        let scanStore = ScanStore()
        let downloadChecks = DownloadChecks(prefs: checkPrefs, store: scanStore)
        let downloadManager = DownloadManager()
        let vtSiteChecks = VtSiteChecks()
        downloadManager.checks = downloadChecks

        tabManager.downloadHandler = { download, url in
            downloadManager.adopt(download, suggestedFilename: nil, sourceURL: url)
        }

        _tabs = StateObject(wrappedValue: tabManager)
        _siteSettings = StateObject(wrappedValue: siteSettingsStore)
        _hub = StateObject(wrappedValue: BrowserHub(tabs: tabManager))
        _store = StateObject(wrappedValue: wikiStore)
        _changes = StateObject(wrappedValue: changesStore)
        _follows = StateObject(wrappedValue: followsStore)
        _checkPrefs = StateObject(wrappedValue: checkPrefs)
        _scanStore = StateObject(wrappedValue: scanStore)
        _downloadChecks = StateObject(wrappedValue: downloadChecks)
        _vtSiteChecks = StateObject(wrappedValue: vtSiteChecks)
        _downloads = StateObject(wrappedValue: downloadManager)

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
                .environmentObject(settings)
                .environmentObject(downloads)
                .environmentObject(checkPrefs)
                .environmentObject(scanStore)
                .environmentObject(downloadChecks)
                .environmentObject(vtSiteChecks)
                .environmentObject(homeLayoutStore)
                .environmentObject(visitTracker)
                .environmentObject(siteSettings)
                .preferredColorScheme(settings.theme.colorScheme)
                .tint(settings.accent.color)
                .dynamicTypeSize(settings.textSize.dynamicTypeSize)
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
                                let allowed = await NetworkPolicy.allowsRefresh(wifiOnly: settings.wifiOnlyRefresh)
                                if allowed {
                                    await changes.refresh()
                                    Notifier.notifyIfNeeded(
                                        changes: changes,
                                        follows: follows,
                                        sections: store.sections
                                    )
                                }
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

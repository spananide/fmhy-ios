import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var bookmarks: Bookmarks
    @EnvironmentObject var hub: BrowserHub
    @EnvironmentObject var changes: ChangesStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var checkPrefs: CheckPrefs
    @EnvironmentObject var vtSiteChecks: VtSiteChecks
    @EnvironmentObject var siteSettings: SiteSettingsStore
    @EnvironmentObject var postsStore: PostsStore

    @ObservedObject private var adBlocker = AdBlocker.shared

    @State private var notificationStatus: String = "Checking…"
    @State private var exportURL: URL?
    @State private var showFileImporter = false
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false
    @AppStorage("downloads.warnRisky") private var warnRiskyFiles: Bool = true
    @State private var showDownloadsSheet = false
    @State private var editingKeyService: ScanService?
    @State private var keyInput: String = ""
    @State private var showForgetSitesConfirm = false
    @State private var showReportSheet = false

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private var wikiStatusText: String {
        let countFormatted = NumberFormatter.localizedString(from: NSNumber(value: store.totalSites), number: .decimal)
        let sitesText = store.totalSites == 1 ? "\(countFormatted) site" : "\(countFormatted) sites"
        if let date = store.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "\(sitesText) · updated \(formatter.localizedString(for: date, relativeTo: Date()))"
        } else {
            return "Bundled wiki"
        }
    }

    private var feedStatusText: String {
        if let date = changes.lastFetched {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "What's new feed: updated \(formatter.localizedString(for: date, relativeTo: Date()))"
        } else {
            return "What's new feed: not updated yet"
        }
    }

    private struct FollowedRowItem: Identifiable {
        let id: String
        let title: String
    }

    private var followedItems: [FollowedRowItem] {
        let sectionMap = Dictionary(store.sections.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return follows.sectionIds.sorted().map { id in
            FollowedRowItem(id: id, title: sectionMap[id] ?? id.capitalized)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                browserSection
                downloadsSection
                fileChecksSection
                dataSection
                notificationsSection
                followingSection
                backupSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .fmhyListStyle()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDownloadsSheet) {
                DownloadsView()
            }
            .sheet(isPresented: $showReportSheet) {
                ReportSheet()
            }
            .task {
                await updateNotificationStatus()
                refreshExportFile()
            }
            .alert(
                editingKeyService == .virusTotal ? "VirusTotal key" : "Hybrid Analysis key",
                isPresented: Binding(
                    get: { editingKeyService != nil },
                    set: { if !$0 { editingKeyService = nil } }
                )
            ) {
                TextField("API key", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Save") {
                    if let s = editingKeyService {
                        checkPrefs.setKey(keyInput, for: s)
                    }
                    editingKeyService = nil
                }

                if let s = editingKeyService, !checkPrefs.maskedKey(for: s).isEmpty {
                    Button("Remove", role: .destructive) {
                        checkPrefs.setKey(nil, for: s)
                        editingKeyService = nil
                    }
                }

                Button("Cancel", role: .cancel) {
                    editingKeyService = nil
                }
            } message: {
                if editingKeyService == .virusTotal {
                    Text("Get a free key from your VirusTotal account (Profile → API key). Free keys have usage limits.")
                } else {
                    Text("Get a free key from your Hybrid Analysis profile (API key tab). Free keys have usage limits.")
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json]
            ) { result in
                handleImportResult(result)
            }
            .alert(backupAlertTitle, isPresented: $showBackupAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupAlertMessage)
            }
            .confirmationDialog(
                "Forget checked sites?",
                isPresented: $showForgetSitesConfirm,
                titleVisibility: .visible
            ) {
                Button("Forget checked sites", role: .destructive) {
                    vtSiteChecks.forgetAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all remembered clean site marks from VirusTotal.")
            }
        }
    }

    // MARK: - 1. Appearance

    private var appearanceSection: some View {
        SwiftUI.Section {
            Picker("Theme", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .fmhyRowBackground()

            Picker("Accent colour", selection: $settings.accent) {
                ForEach(AccentChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .onChange(of: settings.accent) { _, _ in
                refreshExportFile()
            }
            .fmhyRowBackground()

            Picker("Text size", selection: $settings.textSize) {
                ForEach(TextSizeChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .fmhyRowBackground()

            Text("Aa Bb Cc. Sites and descriptions look like this.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(settings.textSize.dynamicTypeSize)
                .fmhyRowBackground()
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - 2. Browser

    private var browserSection: some View {
        SwiftUI.Section {
            Picker("Open links in", selection: $settings.openInSafari) {
                Text("In-app browser").tag(false)
                Text("Safari").tag(true)
            }
            .fmhyRowBackground()

            Picker("Search engine", selection: $settings.searchEngine) {
                ForEach(SearchEngineChoice.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .fmhyRowBackground()

            Toggle("Ad blocking", isOn: $adBlocker.isEnabled)
                .fmhyRowBackground()

            NavigationLink {
                AllowlistSettingsView()
                    .environmentObject(settings)
            } label: {
                HStack {
                    Text("Sites with blocking off")
                    Spacer()
                    Text("\(adBlocker.allowlist.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .fmhyRowBackground()

            NavigationLink {
                ConfiguredSitesSettingsView()
                    .environmentObject(siteSettings)
            } label: {
                HStack {
                    Text("Sites with custom settings")
                    Spacer()
                    Text("\(siteSettings.hosts.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .fmhyRowBackground()
        } header: {
            Text("Browser")
        }
    }

    // MARK: - Downloads

    private var downloadsSection: some View {
        SwiftUI.Section {
            Button {
                showDownloadsSheet = true
            } label: {
                HStack {
                    Label("Downloads", systemImage: "arrow.down.circle")
                    Spacer()
                    if downloads.activeCount > 0 {
                        Text("\(downloads.activeCount) active")
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .fmhyRowBackground()

            Toggle("Warn before opening risky files", isOn: $warnRiskyFiles)
                .fmhyRowBackground()
        } header: {
            Text("Downloads")
        }
    }

    // MARK: - File and Link Checks

    private var fileChecksSection: some View {
        SwiftUI.Section {
            Toggle("VirusTotal", isOn: $checkPrefs.vtEnabled)
                .fmhyRowBackground()

            HStack {
                Text("VirusTotal API key")
                    .font(.subheadline)
                Spacer()
                Text(checkPrefs.maskedKey(for: .virusTotal).isEmpty ? "Not set" : checkPrefs.maskedKey(for: .virusTotal))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(checkPrefs.maskedKey(for: .virusTotal).isEmpty ? "Set" : "Replace") {
                    keyInput = ""
                    editingKeyService = .virusTotal
                }
                .font(.footnote)
                .buttonStyle(.borderless)

                if !checkPrefs.maskedKey(for: .virusTotal).isEmpty {
                    Button("Remove", role: .destructive) {
                        checkPrefs.setKey(nil, for: .virusTotal)
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                }
            }
            .fmhyRowBackground()

            SwiftUI.Link("Get a VirusTotal key", destination: URL(string: "https://www.virustotal.com/gui/my-apikey")!)
                .font(.footnote)
                .fmhyRowBackground()

            Toggle("Hybrid Analysis", isOn: $checkPrefs.haEnabled)
                .fmhyRowBackground()

            HStack {
                Text("Hybrid Analysis API key")
                    .font(.subheadline)
                Spacer()
                Text(checkPrefs.maskedKey(for: .hybridAnalysis).isEmpty ? "Not set" : checkPrefs.maskedKey(for: .hybridAnalysis))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(checkPrefs.maskedKey(for: .hybridAnalysis).isEmpty ? "Set" : "Replace") {
                    keyInput = ""
                    editingKeyService = .hybridAnalysis
                }
                .font(.footnote)
                .buttonStyle(.borderless)

                if !checkPrefs.maskedKey(for: .hybridAnalysis).isEmpty {
                    Button("Remove", role: .destructive) {
                        checkPrefs.setKey(nil, for: .hybridAnalysis)
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                }
            }
            .fmhyRowBackground()

            SwiftUI.Link("Get a Hybrid Analysis key", destination: URL(string: "https://hybrid-analysis.com/my-account?tab=%23api-key-tab")!)
                .font(.footnote)
                .fmhyRowBackground()

            Toggle("Hold downloads until checked", isOn: $checkPrefs.hold)
                .fmhyRowBackground()

            Toggle("Auto-check risky files", isOn: $checkPrefs.autoRisky)
                .fmhyRowBackground()

            Button("Forget checked sites", role: .destructive) {
                showForgetSitesConfirm = true
            }
            .disabled(!vtSiteChecks.hasMarks)
            .fmhyRowBackground()
        } header: {
            Text("File and link checks")
        } footer: {
            Text("What is sent: link checks send the web address, only when you tap “Check link first”. File checks send the file's fingerprint (SHA-256), not the file. Files are uploaded only after you agree. Without a key, the check opens the service's website instead.")
        }
    }

    // MARK: - 3. Data

    private var dataSection: some View {
        SwiftUI.Section {
            Toggle("Refresh only on Wi-Fi", isOn: $settings.wifiOnlyRefresh)
                .fmhyRowBackground()

            VStack(alignment: .leading, spacing: 4) {
                Text(wikiStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if let error = store.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .fmhyRowBackground()

            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                HStack {
                    Text("Update wiki now")
                    if store.isRefreshing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(store.isRefreshing)
            .fmhyRowBackground()

            VStack(alignment: .leading, spacing: 4) {
                Text(feedStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if let error = changes.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .fmhyRowBackground()

            Button {
                Task {
                    await changes.refresh()
                }
            } label: {
                HStack {
                    Text("Refresh feed")
                    if changes.isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(changes.isLoading)
            .fmhyRowBackground()
        } header: {
            Text("Data")
        }
    }

    // MARK: - 4. Notifications

    private var notificationsSection: some View {
        SwiftUI.Section {
            HStack {
                Text("Notification status")
                Spacer()
                Text(notificationStatus)
                    .foregroundStyle(.secondary)
            }
            .fmhyRowBackground()

            if notificationStatus == "Not asked" || notificationStatus == "Not allowed" {
                Button("Allow notifications") {
                    Task {
                        _ = await Notifier.requestAuthorization()
                        await updateNotificationStatus()
                    }
                }
                .fmhyRowBackground()
            }

            Text("iOS may delay background checks depending on battery usage and system scheduling.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fmhyRowBackground()
        } header: {
            Text("Notifications")
        }
    }

    // MARK: - 5. Following

    private var followingSection: some View {
        SwiftUI.Section {
            NavigationLink {
                FollowingView()
            } label: {
                HStack {
                    Text("Followed categories")
                    Spacer()
                    Text("\(follows.sectionIds.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .fmhyRowBackground()
        } header: {
            Text("Following")
        }
    }

    // MARK: - 6. Backup

    private var backupSection: some View {
        SwiftUI.Section {
            if let exportURL = exportURL {
                ShareLink(item: exportURL) {
                    Label("Export backup", systemImage: "square.and.arrow.up")
                }
                .fmhyRowBackground()
            } else {
                Button {
                    refreshExportFile()
                } label: {
                    Label("Export backup", systemImage: "square.and.arrow.up")
                }
                .fmhyRowBackground()
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Import backup", systemImage: "square.and.arrow.down")
            }
            .fmhyRowBackground()
        } header: {
            Text("Backup")
        }
    }

    // MARK: - 7. About

    private var aboutSection: some View {
        SwiftUI.Section {
            LabeledContent("Version", value: appVersionString)
                .fmhyRowBackground()

            LabeledContent("License", value: "GPL-3.0-or-later")
                .fmhyRowBackground()

            NavigationLink {
                PostsView()
            } label: {
                Label("News & posts", systemImage: "newspaper")
                    .badge(postsStore.unreadCount)
            }
            .fmhyRowBackground()

            NavigationLink {
                LegendView()
            } label: {
                Label("Icon legend", systemImage: "questionmark.circle")
            }
            .fmhyRowBackground()

            Button("Source code") {
                dismiss()
                hub.open("https://github.com/spananide/fmhy-ios")
            }
            .fmhyRowBackground()

            Button("Report a problem") {
                showReportSheet = true
            }
            .fmhyRowBackground()

            Button("FMHY") {
                dismiss()
                hub.open("https://fmhy.net")
            }
            .fmhyRowBackground()

            Button("Suggest a site") {
                dismiss()
                hub.open("https://fmhy.net/other/contributing")
            }
            .fmhyRowBackground()

            Button("Original Android app") {
                dismiss()
                hub.open("https://github.com/omeg4-dev/fmhy-android")
            }
            .fmhyRowBackground()

            Button("Show welcome screen again") {
                dismiss()
                settings.isShowingOnboarding = true
            }
            .fmhyRowBackground()
        } header: {
            Text("About")
        } footer: {
            Text("Community port of FMHY for Android by omeg4-dev, not an official FMHY project. No accounts, no analytics: the app only talks to GitHub (wiki data), omeg4-dev's GitHub Pages (What's new feed) and the sites you open.")
        }
    }

    // MARK: - Helpers

    private func updateNotificationStatus() async {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        switch notificationSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationStatus = "Allowed"
        case .denied:
            notificationStatus = "Not allowed"
        case .notDetermined:
            notificationStatus = "Not asked"
        @unknown default:
            notificationStatus = "Not asked"
        }
    }

    private func refreshExportFile() {
        let file = BackupFile(
            version: 1,
            exportedAt: Date(),
            bookmarks: bookmarks.ids,
            follows: Array(follows.sectionIds).sorted(),
            settings: settings.exportSettingsMap()
        )
        self.exportURL = try? BackupIO.makeTempFile(file)
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                let backup = try BackupIO.decode(data)
                let addedBookmarks = bookmarks.merge(ids: backup.bookmarks)
                let addedFollows = follows.merge(ids: backup.follows)
                settings.importSettingsMap(backup.settings)

                backupAlertTitle = "Backup Imported"
                backupAlertMessage = "Imported \(addedBookmarks) bookmarks and \(addedFollows) followed categories"
                showBackupAlert = true
                refreshExportFile()
            } catch {
                backupAlertTitle = "Import Failed"
                backupAlertMessage = error.localizedDescription
                showBackupAlert = true
            }
        case .failure(let error):
            backupAlertTitle = "Import Failed"
            backupAlertMessage = error.localizedDescription
            showBackupAlert = true
        }
    }
}

struct AllowlistSettingsView: View {
    @ObservedObject private var adBlocker = AdBlocker.shared
    @EnvironmentObject var settings: AppSettings

    private var sortedHosts: [String] {
        Array(adBlocker.allowlist).sorted()
    }

    var body: some View {
        List {
            if sortedHosts.isEmpty {
                ContentUnavailableView("No Sites", systemImage: "shield.checkerboard", description: Text("Sites where you turn ad blocking off appear here."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(sortedHosts, id: \.self) { host in
                    Text(host)
                        .fmhyRowBackground()
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let host = sortedHosts[index]
                        adBlocker.setAllowlisted(host, false)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
        .navigationTitle("Sites with blocking off")
    }
}

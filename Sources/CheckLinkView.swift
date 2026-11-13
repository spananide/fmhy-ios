import SwiftUI

// MARK: - CheckLinkView

struct CheckLinkView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var downloadChecks: DownloadChecks
    @EnvironmentObject var vtSiteChecks: VtSiteChecks
    @Environment(\.openURL) private var openURL

    @State private var urlInput = ""
    @State private var currentVerdict: Verdict?
    @State private var selectedEntry: Entry?
    @State private var recentChecks: [RecentCheck] = []
    @State private var clipboardHost: String?
    @State private var clipboardUrl: String?
    @State private var showAllMatches = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var linkScanResult: ScanResult?
    @State private var isScanningLink = false
    @State private var isSubmittingLink = false
    @State private var showingScanSheet = false
    @State private var showSubmitConfirm = false

    private var hasReadyServices: Bool {
        !downloadChecks.prefs.readyServices.isEmpty
    }

    private var displayedMatches: [Entry] {
        guard let verdict = currentVerdict else { return [] }
        if showAllMatches || verdict.matches.count <= 5 {
            return verdict.matches
        }
        return Array(verdict.matches.prefix(5))
    }

    // MARK: - Logic Helpers

    private func handleQueryChange(_ newValue: String) {
        debounceTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            currentVerdict = nil
            linkScanResult = nil
            showAllMatches = false
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let safeGuard = store.safeGuard else { return }
                currentVerdict = safeGuard.check(trimmed)
                linkScanResult = nil
                showAllMatches = false
            }
        }
    }

    private func runImmediateCheck(_ input: String) {
        debounceTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            currentVerdict = nil
            linkScanResult = nil
            return
        }
        guard let safeGuard = store.safeGuard else { return }
        let verdict = safeGuard.check(trimmed)
        currentVerdict = verdict
        linkScanResult = nil
        showAllMatches = false
        saveRecentCheck(url: trimmed, status: verdict.status)
    }

    private func saveRecentCheck(url: String, status: SafetyStatus) {
        guard status != .invalid else { return }
        let cleanUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty else { return }
        let newItem = RecentCheck(url: cleanUrl, status: status, ts: Date())
        let filtered = recentChecks.filter { $0.url.caseInsensitiveCompare(cleanUrl) != .orderedSame }
        let updated = Array(([newItem] + filtered).prefix(10))
        recentChecks = updated
        saveRecentChecksList(updated)
    }

    private func clearRecents() {
        recentChecks = []
        UserDefaults.standard.removeObject(forKey: "check_recent")
    }

    private func saveRecentChecksList(_ list: [RecentCheck]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "check_recent")
        }
    }

    private func loadRecentChecks() {
        guard let data = UserDefaults.standard.data(forKey: "check_recent") else { return }
        do {
            let items = try JSONDecoder().decode([RecentCheck].self, from: data)
            let pruned = UrlExtractor.pruneRecentChecks(items)
            recentChecks = pruned
            if pruned.count != items.count {
                saveRecentChecksList(pruned)
            }
        } catch {
            recentChecks = []
        }
    }

    private func checkClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return
        }
        let extracted = UrlExtractor.extractFirstUrl(text)
        guard UrlExtractor.looksLikeUrl(extracted) else { return }
        guard let host = UrlExtractor.extractHost(from: extracted) else { return }
        clipboardHost = host
        clipboardUrl = extracted
    }

    private func runLinkScan() {
        guard let verdict = currentVerdict else { return }
        let target = verdict.normalizedUrl ?? (urlInput.contains("://") ? urlInput : "https://\(urlInput)")
        isScanningLink = true
        isSubmittingLink = false
        Task {
            let res = await downloadChecks.checkLink(url: target, services: downloadChecks.prefs.readyServices)
            await MainActor.run {
                self.linkScanResult = res
                self.isScanningLink = false
                if let host = verdict.host,
                   let vt = res.services.first(where: { $0.service == .virusTotal }),
                   vt.error == nil,
                   VtSiteChecks.shouldRemember(vt.verdict) {
                    vtSiteChecks.remember(host: host, flagged: vt.flagged, engines: vt.engines)
                }
            }
        }
    }

    private func submitLinkForScan() {
        guard let verdict = currentVerdict else { return }
        let target = verdict.normalizedUrl ?? (urlInput.contains("://") ? urlInput : "https://\(urlInput)")
        isScanningLink = true
        isSubmittingLink = true
        Task {
            let service = downloadChecks.prefs.readyServices.first ?? .virusTotal
            let res = await downloadChecks.submitLink(url: target, service: service)
            await MainActor.run {
                self.linkScanResult = res
                self.isScanningLink = false
                if let host = verdict.host,
                   let vt = res.services.first(where: { $0.service == .virusTotal }),
                   vt.error == nil,
                   VtSiteChecks.shouldRemember(vt.verdict) {
                    vtSiteChecks.remember(host: host, flagged: vt.flagged, engines: vt.engines)
                }
            }
        }
    }

    private func scanChips(for res: ScanResult) -> [CheckChipData] {
        CheckChips.build(
            result: res,
            readyServices: downloadChecks.prefs.readyServices,
            fileSize: 0
        )
    }

    private func targetUrlToOpen(_ verdict: Verdict) -> URL? {
        let raw = verdict.normalizedUrl ?? (verdict.input.contains("://") ? verdict.input : "https://\(verdict.input)")
        return URL(string: raw)
    }

    private func targetUrlString(_ verdict: Verdict) -> String {
        verdict.normalizedUrl ?? (verdict.input.contains("://") ? verdict.input : "https://\(verdict.input)")
    }

    private func sectionTitle(for entry: Entry) -> String? {
        store.sections.first(where: { $0.id == entry.sectionId })?.title
    }

    private func breadcrumbs(for entry: Entry) -> String {
        let secTitle = sectionTitle(for: entry)
        let parts = UrlExtractor.matchBreadcrumb(sectionTitle: secTitle, headingPath: entry.headingPath)
        return parts.joined(separator: " › ")
    }

    // MARK: - Subviews

    private var inputSection: some View {
        SwiftUI.Section {
            HStack {
                TextField("Enter URL or domain (e.g. example.com)", text: $urlInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        runImmediateCheck(urlInput)
                    }

                if !urlInput.isEmpty {
                    Button {
                        urlInput = ""
                        currentVerdict = nil
                        linkScanResult = nil
                        showAllMatches = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear input")
                }
            }

            if urlInput.isEmpty, let host = clipboardHost {
                Button {
                    let target = clipboardUrl ?? host
                    urlInput = target
                    runImmediateCheck(target)
                } label: {
                    Label("Paste \(host)", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            HStack(spacing: 12) {
                Button {
                    if let paste = UIPasteboard.general.string {
                        urlInput = paste
                        runImmediateCheck(paste)
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    runImmediateCheck(urlInput)
                } label: {
                    Label("Check", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var recentSection: some View {
        SwiftUI.Section {
            ForEach(recentChecks) { item in
                Button {
                    urlInput = item.url
                    runImmediateCheck(item.url)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.status.symbolName)
                            .foregroundStyle(item.status.color)
                            .font(.system(size: 20))

                        Text(item.url)
                            .font(.body.monospaced())
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text("Recent checks")
                Spacer()
                Button("Clear") {
                    clearRecents()
                }
                .font(.footnote)
            }
        }
    }

    private func verdictCard(_ verdict: Verdict) -> some View {
        SwiftUI.Section {
            VStack(spacing: 12) {
                Image(systemName: verdict.status.symbolName)
                    .font(.system(size: 48))
                    .foregroundStyle(verdict.status.color)
                    .padding(.top, 8)

                Text(verdict.status.title)
                    .font(.title2.bold())
                    .foregroundStyle(verdict.status.color)
                    .multilineTextAlignment(.center)

                if let host = verdict.host, !host.isEmpty {
                    Text(host)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if let reason = verdict.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }

                if let host = UrlExtractor.hostForCheckJustHost(verdict: verdict) {
                    Button("Check just \(host)") {
                        urlInput = host
                        runImmediateCheck(host)
                    }
                    .font(.subheadline)
                    .padding(.top, 2)
                }

                if verdict.status != .invalid {
                    HStack(spacing: 12) {
                        if let url = targetUrlToOpen(verdict) {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open", systemImage: "safari")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            UIPasteboard.general.string = targetUrlString(verdict)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }
    }

    private var scanSection: some View {
        SwiftUI.Section("VirusTotal / Hybrid Analysis") {
            if isScanningLink {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text(isSubmittingLink ? "Submitting link for scan…" : "Scanning link…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let res = linkScanResult {
                VStack(alignment: .leading, spacing: 8) {
                    CheckChipRow(chips: scanChips(for: res)) { chip in
                        _ = chip
                        showingScanSheet = true
                    }

                    if CheckUiText.anyUnknown(res) {
                        Button("Submit for scan") {
                            showSubmitConfirm = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    runLinkScan()
                } label: {
                    Label("Scan link", systemImage: "shield.checkerboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func crumbsText(for entry: Entry) -> some View {
        let crumbs = breadcrumbs(for: entry)
        return Group {
            if !crumbs.isEmpty {
                Text(crumbs)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func matchRow(_ entry: Entry) -> some View {
        Button {
            selectedEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if entry.tier > 0 {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Color(red: 1.0, green: 0.75, blue: 0.3))
                    }

                    Spacer()

                    Text(entry.url.hostOnly)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                crumbsText(for: entry)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func matchesSection(_ verdict: Verdict) -> some View {
        SwiftUI.Section(verdict.status == .domainListed ? "Listed pages on this domain" : "Matched FMHY Sites") {
            ForEach(displayedMatches) { entry in
                matchRow(entry)
            }

            if verdict.matches.count > 5 && !showAllMatches {
                Button("Show all \(verdict.matches.count)") {
                    showAllMatches = true
                }
                .font(.subheadline)
            }
        }
    }

    private func lookalikesSection(_ verdict: Verdict) -> some View {
        SwiftUI.Section("Possible clones of") {
            ForEach(verdict.lookalikes) { entry in
                EntryRow(entry: entry) { selected in
                    selectedEntry = selected
                }
            }
        }
    }

    // MARK: - Layered Body

    private var layerOne: some View {
        List {
            inputSection

            if urlInput.isEmpty && currentVerdict == nil && !recentChecks.isEmpty {
                recentSection
            }

            if let verdict = currentVerdict {
                verdictCard(verdict)

                if hasReadyServices {
                    scanSection
                }

                if !verdict.matches.isEmpty {
                    matchesSection(verdict)
                }

                if !verdict.lookalikes.isEmpty {
                    lookalikesSection(verdict)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Check Link")
        .onChange(of: urlInput) { _, newValue in
            handleQueryChange(newValue)
        }
        .onAppear {
            loadRecentChecks()
            checkClipboard()
        }
    }

    private var layerTwo: some View {
        layerOne
            .sheet(item: $selectedEntry) { entry in
                EntryDetailSheet(entry: entry)
            }
            .sheet(isPresented: $showingScanSheet) {
                if let res = linkScanResult {
                    ScanResultSheet(result: res, isLink: true)
                }
            }
    }

    private var layerThree: some View {
        layerTwo
            .confirmationDialog(
                "Submit for scan?",
                isPresented: $showSubmitConfirm,
                titleVisibility: .visible
            ) {
                Button("Submit") {
                    submitLinkForScan()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(CheckUiText.sendNote(downloadChecks.prefs.readyServices))
            }
    }

    var body: some View {
        NavigationStack {
            layerThree
        }
    }
}

// MARK: - SafetyStatus Visual Helpers

private extension SafetyStatus {
    var title: String {
        switch self {
        case .starred:
            return "Starred on FMHY"
        case .fmhySite, .listed, .domainListed:
            return "Listed on FMHY"
        case .potentiallyUnsafe:
            return "Potentially unsafe"
        case .unsafe:
            return "Unsafe \u{2014} on the FMHY unsafe list"
        case .searchEngine:
            return "Search engine"
        case .noData:
            return "Not on FMHY \u{2014} no data"
        case .invalid:
            return "That doesn't look like a link"
        }
    }

    var color: Color {
        switch self {
        case .fmhySite, .starred, .listed, .domainListed:
            return .green
        case .potentiallyUnsafe:
            return .orange
        case .unsafe:
            return .red
        case .searchEngine, .noData, .invalid:
            return .gray
        }
    }

    var symbolName: String {
        switch self {
        case .starred:
            return "star.circle.fill"
        case .fmhySite, .listed, .domainListed:
            return "checkmark.shield.fill"
        case .potentiallyUnsafe:
            return "exclamationmark.triangle.fill"
        case .unsafe:
            return "xmark.shield.fill"
        case .searchEngine:
            return "magnifyingglass.circle.fill"
        case .noData:
            return "questionmark.circle.fill"
        case .invalid:
            return "exclamationmark.circle.fill"
        }
    }
}

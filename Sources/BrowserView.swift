import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var bookmarks: Bookmarks
    @EnvironmentObject var hub: BrowserHub

    @FocusState private var isAddressFocused: Bool
    @State private var addressText: String = ""
    @State private var cachedHost: String?
    @State private var cachedVerdict: Verdict?
    @State private var showSafetySheet = false
    @State private var showTabSwitcher = false

    private var badgeSymbolName: String {
        guard let verdict = cachedVerdict else { return "questionmark.circle" }
        switch verdict.status {
        case .fmhySite, .starred, .listed, .domainListed:
            return "checkmark.seal.fill"
        case .potentiallyUnsafe:
            return "exclamationmark.triangle.fill"
        case .unsafe:
            return "xmark.octagon.fill"
        case .searchEngine, .noData, .invalid:
            return "questionmark.circle"
        }
    }

    private var badgeColor: Color {
        guard let verdict = cachedVerdict else { return .secondary }
        switch verdict.status {
        case .fmhySite, .starred, .listed, .domainListed:
            return .green
        case .potentiallyUnsafe:
            return .orange
        case .unsafe:
            return .red
        case .searchEngine, .noData, .invalid:
            return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if let selected = tabs.selected, selected.isLoading {
                ProgressView(value: selected.progress)
                    .progressViewStyle(.linear)
                    .tint(fmhyPurple)
                    .frame(height: 2)
            } else {
                Divider()
            }

            Group {
                if let tab = tabs.selected, tab.url != nil || tab.pendingURL != nil {
                    WebViewHost(tab: tab)
                        .id(tab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    BrowserStartView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()

            bottomToolbar
        }
        .onAppear {
            syncAddress()
            updateVerdict(for: tabs.selected?.url)
        }
        .onChange(of: tabs.selectedId) { _, _ in
            syncAddress()
            updateVerdict(for: tabs.selected?.url)
        }
        .onChange(of: tabs.selected?.url) { _, newUrl in
            syncAddress()
            updateVerdict(for: newUrl)
        }
        .onChange(of: isAddressFocused) { _, focused in
            if focused {
                addressText = tabs.selected?.url?.absoluteString ?? ""
            } else {
                syncAddress()
            }
        }
        .sheet(isPresented: $showSafetySheet) {
            SafetyInfoSheet(verdict: cachedVerdict, host: cachedHost)
                .presentationDetents([.height(260)])
        }
        .sheet(isPresented: $showTabSwitcher) {
            TabSwitcherSheet()
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                showSafetySheet = true
            } label: {
                Image(systemName: badgeSymbolName)
                    .font(.system(size: 20))
                    .foregroundStyle(badgeColor)
            }
            .accessibilityLabel("Safety status")

            HStack(spacing: 6) {
                if tabs.selected?.isPrivate == true {
                    Text("Private")
                        .font(.caption2.bold())
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(Capsule())
                }

                TextField("Search or enter address", text: $addressText)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isAddressFocused)
                    .onSubmit {
                        handleSubmit()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if tabs.selected?.isLoading == true {
                Button {
                    tabs.selected?.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Stop loading")
            } else {
                Button {
                    tabs.selected?.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .disabled(tabs.selected?.url == nil)
                .accessibilityLabel("Reload")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var bottomToolbar: some View {
        HStack {
            Button {
                tabs.selected?.goBack()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .medium))
            }
            .disabled(!(tabs.selected?.canGoBack ?? false))
            .accessibilityLabel("Back")

            Spacer()

            Button {
                tabs.selected?.goForward()
            } label: {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 18, weight: .medium))
            }
            .disabled(!(tabs.selected?.canGoForward ?? false))
            .accessibilityLabel("Forward")

            Spacer()

            if let url = tabs.selected?.url {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                }
                .accessibilityLabel("Share")
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Share")
            }

            Spacer()

            Menu {
                Button {
                    if let url = tabs.selected?.url {
                        UIPasteboard.general.string = url.absoluteString
                    }
                } label: {
                    Label("Copy link", systemImage: "doc.on.doc")
                }
                .disabled(tabs.selected?.url == nil)

                Button {
                    if let url = tabs.selected?.url {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
                .disabled(tabs.selected?.url == nil)

                Button {
                    tabs.selected?.desktopMode.toggle()
                } label: {
                    let isDesktop = tabs.selected?.desktopMode ?? false
                    Label(
                        isDesktop ? "Request mobile site" : "Request desktop site",
                        systemImage: isDesktop ? "iphone" : "desktopcomputer"
                    )
                }
                .disabled(tabs.selected == nil)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
            }
            .accessibilityLabel("Page options")

            Spacer()

            Button {
                showTabSwitcher = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    Text("\(tabs.tabs.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .accessibilityLabel("Tabs, \(tabs.tabs.count) open")

            Spacer()

            Button {
                _ = tabs.newTab(select: true)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
            }
            .accessibilityLabel("New tab")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func syncAddress() {
        guard !isAddressFocused else { return }
        if let host = tabs.selected?.url?.hostOnly {
            addressText = host
        } else {
            addressText = ""
        }
    }

    private func updateVerdict(for url: URL?) {
        guard let url = url, let host = url.host, !host.isEmpty else {
            cachedHost = nil
            cachedVerdict = nil
            return
        }
        if host == cachedHost && cachedVerdict != nil {
            return
        }
        cachedHost = host
        if let safeGuard = store.safeGuard {
            cachedVerdict = safeGuard.check(url.absoluteString)
        } else {
            cachedVerdict = nil
        }
    }

    private func handleSubmit() {
        isAddressFocused = false
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetURL: URL?
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            targetURL = URL(string: trimmed)
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            targetURL = URL(string: "https://\(trimmed)")
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            targetURL = URL(string: "https://duckduckgo.com/?q=\(query)")
        }

        guard let url = targetURL else { return }
        if let selected = tabs.selected {
            selected.load(url)
        } else {
            _ = tabs.newTab(url: url, isPrivate: false, select: true)
        }
        addressText = url.hostOnly
    }
}

private struct SafetyInfoSheet: View {
    let verdict: Verdict?
    let host: String?
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        guard let verdict = verdict else { return "Not on FMHY" }
        switch verdict.status {
        case .starred:
            return "Starred on FMHY"
        case .fmhySite, .listed, .domainListed:
            return "Listed on FMHY"
        case .potentiallyUnsafe:
            return "Potentially unsafe"
        case .unsafe:
            return "On the FMHY unsafe list"
        case .searchEngine, .noData, .invalid:
            return "Not on FMHY"
        }
    }

    private var color: Color {
        guard let verdict = verdict else { return .secondary }
        switch verdict.status {
        case .fmhySite, .starred, .listed, .domainListed:
            return .green
        case .potentiallyUnsafe:
            return .orange
        case .unsafe:
            return .red
        case .searchEngine, .noData, .invalid:
            return .secondary
        }
    }

    private var symbol: String {
        guard let verdict = verdict else { return "questionmark.circle" }
        switch verdict.status {
        case .fmhySite, .starred, .listed, .domainListed:
            return "checkmark.seal.fill"
        case .potentiallyUnsafe:
            return "exclamationmark.triangle.fill"
        case .unsafe:
            return "xmark.octagon.fill"
        case .searchEngine, .noData, .invalid:
            return "questionmark.circle"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .font(.headline)
            }
            .padding(.horizontal)
            .padding(.top, 14)

            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(color)

            Text(title)
                .font(.title3.bold())
                .foregroundStyle(color)

            if let host = host, !host.isEmpty {
                Text(host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let reason = verdict?.reason, !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
    }
}

import SwiftUI

// WebKit content blockers expose no per-request counts or blocked-URL lists, so per-site blocked count and blocked request list are omitted.
struct ShieldSheet: View {
    weak var tab: BrowserTab?
    let host: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var siteSettings: SiteSettingsStore
    @ObservedObject private var adBlocker = AdBlocker.shared

    @State private var showSiteSettings = false
    @State private var showAllowlist = false

    private var normalizedHost: String {
        SiteSettingsStore.normalizeHost(host)
    }

    private var displayHost: String {
        normalizedHost.isEmpty ? "This site" : normalizedHost
    }

    private var isBlockingOnThisSite: Bool {
        tab?.adBlockActive ?? adBlocker.shouldBlock(host: normalizedHost)
    }

    private var shieldSymbolName: String {
        isBlockingOnThisSite ? "shield.checkerboard" : "shield.slash"
    }

    private var shieldStatusText: String {
        if !adBlocker.isEnabled {
            return "Ad blocking is off everywhere"
        }
        if isBlockingOnThisSite {
            return "Protections are active on this site"
        } else {
            return "Blocking is turned off for this site"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                switchesSection
                actionsSection
            }
            .listStyle(.insetGrouped)
            .fmhyListStyle()
            .navigationTitle("Protections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showSiteSettings) {
                SiteSettingsView(host: normalizedHost, tab: tab)
                    .environmentObject(siteSettings)
            }
            .sheet(isPresented: $showAllowlist) {
                NavigationStack {
                    AllowlistSettingsView()
                        .environmentObject(settings)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showAllowlist = false
                                }
                            }
                        }
                }
            }
        }
    }

    private var headerSection: some View {
        SwiftUI.Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: shieldSymbolName)
                        .font(.system(size: 28))
                        .foregroundStyle(isBlockingOnThisSite ? fmhyPurple : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayHost)
                            .font(.headline)
                            .lineLimit(1)
                        Text(shieldStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .fmhyRowBackground()
        }
    }

    private var switchesSection: some View {
        SwiftUI.Section {
            Toggle("Ad blocking everywhere", isOn: $adBlocker.isEnabled)
                .fmhyRowBackground()

            if !normalizedHost.isEmpty {
                Toggle("Blocking on \(displayHost)", isOn: Binding(
                    get: { isBlockingOnThisSite },
                    set: { _ in
                        tab?.toggleAdBlockForCurrentSite()
                    }
                ))
                .disabled(!adBlocker.isEnabled)
                .fmhyRowBackground()
            }
        }
    }

    private var actionsSection: some View {
        SwiftUI.Section {
            if !normalizedHost.isEmpty {
                Button {
                    showSiteSettings = true
                } label: {
                    HStack {
                        Label("Site settings…", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                .fmhyRowBackground()
            }

            Button {
                showAllowlist = true
            } label: {
                HStack {
                    Label("Manage allowlisted sites", systemImage: "list.bullet")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .fmhyRowBackground()
        }
    }
}

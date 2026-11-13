import SwiftUI

struct SiteSettingsView: View {
    let host: String
    weak var tab: BrowserTab?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var siteSettings: SiteSettingsStore
    @ObservedObject private var adBlocker = AdBlocker.shared

    @State private var config: SiteConfig = SiteConfig(host: "")
    @State private var adblock: Bool = true
    @State private var hasLoadedInitial: Bool = false

    private var normalizedHost: String {
        SiteSettingsStore.normalizeHost(host)
    }

    private var displayHost: String {
        normalizedHost.isEmpty ? "This site" : normalizedHost
    }

    var body: some View {
        NavigationStack {
            List {
                togglesSection
                resetSection
            }
            .listStyle(.insetGrouped)
            .fmhyListStyle()
            .navigationTitle("Site settings for \(displayHost)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadInitial()
            }
        }
    }

    private var togglesSection: some View {
        SwiftUI.Section {
            Toggle("Ad blocking", isOn: Binding(
                get: { adblock },
                set: { newValue in
                    adblock = newValue
                    adBlocker.setAllowlisted(normalizedHost, !newValue)
                    tab?.reload()
                }
            ))
            .fmhyRowBackground()

            Toggle("Block pop-ups", isOn: Binding(
                get: { !config.popups },
                set: { newValue in
                    config.popups = !newValue
                    siteSettings.update(config)
                }
            ))
            .fmhyRowBackground()

            Toggle("JavaScript", isOn: Binding(
                get: { config.javaScript },
                set: { newValue in
                    config.javaScript = newValue
                    siteSettings.update(config)
                    tab?.reload()
                }
            ))
            .fmhyRowBackground()

            Toggle("Desktop site", isOn: Binding(
                get: { config.desktop },
                set: { newValue in
                    config.desktop = newValue
                    siteSettings.update(config)
                    tab?.reload()
                }
            ))
            .fmhyRowBackground()

            Toggle("Dark page", isOn: Binding(
                get: { config.darkPage },
                set: { newValue in
                    config.darkPage = newValue
                    siteSettings.update(config)
                    tab?.applyDarkPage()
                }
            ))
            .fmhyRowBackground()
        } header: {
            Text("Site settings for \(displayHost)")
        }
    }

    private var resetSection: some View {
        SwiftUI.Section {
            Button(role: .destructive) {
                resetSite()
            } label: {
                Text("Reset this site")
            }
            .fmhyRowBackground()
        }
    }

    private func loadInitial() {
        guard !hasLoadedInitial else { return }
        hasLoadedInitial = true
        config = siteSettings.config(for: normalizedHost)
        adblock = !adBlocker.isAllowlisted(host: normalizedHost)
    }

    private func resetSite() {
        siteSettings.reset(host: normalizedHost)
        adBlocker.setAllowlisted(normalizedHost, false)
        config = siteSettings.config(for: normalizedHost)
        adblock = true
        tab?.applyDarkPage()
        tab?.reload()
    }
}

struct ConfiguredSitesSettingsView: View {
    @EnvironmentObject var siteSettings: SiteSettingsStore
    @State private var showResetAllConfirm = false
    @State private var selectedSiteForEdit: IdentifiedSite?

    private var hosts: [String] {
        siteSettings.hosts
    }

    var body: some View {
        List {
            if hosts.isEmpty {
                emptyView
            } else {
                sitesList
            }
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
        .navigationTitle("Sites with custom settings")
        .toolbar {
            if !hosts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset all", role: .destructive) {
                        showResetAllConfirm = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Reset all site settings?",
            isPresented: $showResetAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset all", role: .destructive) {
                siteSettings.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove custom settings for all sites.")
        }
        .sheet(item: $selectedSiteForEdit) { item in
            SiteSettingsView(host: item.host, tab: nil)
                .environmentObject(siteSettings)
        }
    }

    private var emptyView: some View {
        Text("No site settings yet")
            .foregroundStyle(.secondary)
            .fmhyRowBackground()
    }

    private var sitesList: some View {
        SwiftUI.Section {
            ForEach(hosts, id: \.self) { host in
                Button {
                    selectedSiteForEdit = IdentifiedSite(host: host)
                } label: {
                    HStack {
                        Text(host)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .fmhyRowBackground()
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let host = hosts[index]
                    siteSettings.reset(host: host)
                }
            }
        }
    }
}

struct IdentifiedSite: Identifiable {
    let host: String
    var id: String { host }
}

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bookmarks: Bookmarks
    @EnvironmentObject var hub: BrowserHub
    @EnvironmentObject var changes: ChangesStore

    @State private var showSettings = false

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private func formatSiteCount(_ count: Int) -> String {
        let formatted = Self.countFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return count == 1 ? "\(formatted) site" : "\(formatted) sites"
    }

    private var listHeaderText: String {
        let formattedTotal = Self.countFormatter.string(from: NSNumber(value: store.totalSites)) ?? "\(store.totalSites)"
        let sitesText = store.totalSites == 1 ? "\(formattedTotal) site" : "\(formattedTotal) sites"
        let activeCategories = store.sections.filter { (store.sectionCounts[$0.id] ?? 0) > 0 }.count
        let categoriesText = activeCategories == 1 ? "1 category" : "\(activeCategories) categories"
        return "\(sitesText) in \(categoriesText)"
    }

    private var footerText: String {
        if let date = store.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
        } else {
            return "Bundled wiki"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let layoutGroups = SectionLayout.layout(sections: store.sections)
                ForEach(Array(layoutGroups.enumerated()), id: \.offset) { index, group in
                    SwiftUI.Section {
                        ForEach(group.sections) { section in
                            NavigationLink(value: section) {
                                HStack(spacing: 12) {
                                    Text(sectionEmoji(section.id))
                                        .font(.system(size: 28))
                                        .frame(width: 34, alignment: .center)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(section.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        if !section.description.isEmpty {
                                            Text(section.description)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }

                                        let count = store.sectionCounts[section.id] ?? 0
                                        Text(formatSiteCount(count))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)

                                    if follows.isFollowing(section.id) {
                                        Spacer()
                                        Image(systemName: "bell.fill")
                                            .font(.caption)
                                            .foregroundStyle(settings.accent.color)
                                            .accessibilityLabel("Followed")
                                    }
                                }
                            }
                            .fmhyRowBackground()
                        }
                    } header: {
                        if index == 0 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(listHeaderText)
                                    .textCase(nil)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, 2)
                                Text(group.title)
                            }
                        } else {
                            Text(group.title)
                        }
                    } footer: {
                        if index == layoutGroups.count - 1 {
                            VStack(alignment: .center, spacing: 4) {
                                if let error = store.errorMessage {
                                    Text(error)
                                        .foregroundStyle(.red)
                                }
                                Text(footerText)
                                    .foregroundStyle(.secondary)
                                Text("[Send feedback](https://github.com/spananide/fmhy-ios/issues/new/choose)")
                            }
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fmhyListStyle()
            .navigationTitle("FMHY")
            .navigationDestination(for: WikiSection.self) { section in
                SectionView(section: section)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if store.isRefreshing {
                        ProgressView()
                    } else {
                        Button {
                            Task {
                                await store.refresh()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh wiki")
                        .disabled(store.isLoading)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(settings)
                    .environmentObject(store)
                    .environmentObject(bookmarks)
                    .environmentObject(hub)
                    .environmentObject(changes)
                    .environmentObject(follows)
            }
        }
    }
}

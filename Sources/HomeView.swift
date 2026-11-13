import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bookmarks: Bookmarks
    @EnvironmentObject var hub: BrowserHub
    @EnvironmentObject var changes: ChangesStore
    @EnvironmentObject var layoutStore: HomeLayoutStore

    @State private var showSettings = false
    @State private var showEditHome = false
    @State private var showReportSheet = false
    @State private var randomPickId: String? = nil
    @State private var selectedEntry: Entry? = nil

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

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

    private var isSearchFirst: Bool {
        layoutStore.layout.enabledBlocks.first == .search
    }

    private var newSinceCount: Int {
        changes.changes.filter { change in
            change.kind == "added" && change.ts > changes.lastSeenTs
        }.count
    }

    var body: some View {
        NavigationStack {
            contentList
                .navigationTitle("FMHY")
                .navigationDestination(for: WikiSection.self) { section in
                    SectionView(section: section)
                }
                .toolbar {
                    leadingToolbar
                    trailingToolbar
                }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showEditHome) {
            EditHomeView()
        }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailSheet(entry: entry)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet()
        }
    }

    private var contentList: some View {
        List {
            ForEach(layoutStore.layout.enabledBlocks, id: \.self) { block in
                blockView(for: block)
            }
            footerSection
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
    }

    @ViewBuilder
    private func blockView(for block: HomeBlock) -> some View {
        switch block {
        case .search:
            SearchBlockView(
                totalEntries: store.totalSites,
                showHeadline: !isSearchFirst,
                onSearch: { hub.requestedTab = 1 }
            )
        case .newSince:
            NewSinceBlockView(
                count: newSinceCount,
                onOpen: { hub.requestedTab = 5 }
            )
        case .randomPick:
            RandomPickBlockView(
                pickId: $randomPickId,
                onSelect: { selected in selectedEntry = selected }
            )
        case .pinned:
            PinnedBlockView()
        case .newInPinned:
            NewInPinnedBlockView(
                onSelect: { selected in selectedEntry = selected },
                onSeeAll: { hub.requestedTab = 5 }
            )
        case .favourites:
            FavouritesBlockView(
                onSelect: { selected in selectedEntry = selected },
                onSeeAll: { hub.requestedTab = 2 }
            )
        case .suggestions:
            SuggestionsBlockView(
                onSelect: { selected in selectedEntry = selected }
            )
        case .sections:
            SectionsListBlock(
                headerText: listHeaderText
            )
        }
    }

    private var footerSection: some View {
        SwiftUI.Section {
            EmptyView()
        } footer: {
            VStack(alignment: .center, spacing: 6) {
                if let error = store.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
                Text(footerText)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    NavigationLink {
                        LegendView()
                    } label: {
                        Text("Icon legend")
                    }

                    Text("·")
                        .foregroundStyle(.secondary)

                    Button("Report a problem") {
                        showReportSheet = true
                    }
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
    }

    @ToolbarContentBuilder
    private var leadingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }

    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showEditHome = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Edit home")
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

    private var settingsSheet: some View {
        SettingsView()
            .environmentObject(settings)
            .environmentObject(store)
            .environmentObject(bookmarks)
            .environmentObject(hub)
            .environmentObject(changes)
            .environmentObject(follows)
    }
}

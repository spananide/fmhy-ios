import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var bookmarks: Bookmarks
    @EnvironmentObject var hub: BrowserHub
    @EnvironmentObject var changes: ChangesStore
    @EnvironmentObject var layoutStore: HomeLayoutStore

    @State private var path = NavigationPath()
    @State private var didAutoOpen = false
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
        NavigationStack(path: $path) {
            contentList
                .navigationTitle("FMHY")
                .navigationDestination(for: WikiSection.self) { section in
                    if section.id == "beginners-guide" {
                        ReaderView(path: "beginners-guide.md", title: section.title)
                    } else {
                        SectionView(section: section)
                    }
                }
                .navigationDestination(for: GroupRoute.self) { route in
                    GroupView(route: route)
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
        .task {
            checkAutoOpen()
        }
        .onChange(of: store.sections.count) { _, _ in
            checkAutoOpen()
        }
    }

    private func checkAutoOpen() {
        guard !didAutoOpen else { return }
        guard let sectionId = UserDefaults.standard.string(forKey: "section") else {
            didAutoOpen = true
            return
        }
        guard let section = store.sections.first(where: { $0.id == sectionId }) else {
            return
        }
        didAutoOpen = true
        path.append(section)

        if UserDefaults.standard.object(forKey: "group") != nil {
            let index = UserDefaults.standard.integer(forKey: "group")
            let groups = SectionOutline.topGroups(
                headings: store.headings(in: section.id),
                entries: store.entries(in: section.id)
            )
            if !groups.isEmpty {
                let clampedIndex = max(0, min(index, groups.count - 1))
                let group = groups[clampedIndex]
                path.append(GroupRoute(sectionId: section.id, groupId: group.id))
            }
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
            NavigationLink {
                LegendView()
            } label: {
                Label("Icon legend", systemImage: "questionmark.circle")
            }
            .fmhyRowBackground()

            Button {
                showReportSheet = true
            } label: {
                Label("Report a problem", systemImage: "exclamationmark.bubble")
            }
            .fmhyRowBackground()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Text(footerText)
            }
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

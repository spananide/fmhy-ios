import SwiftUI

struct SearchBlockView: View {
    let totalEntries: Int
    let showHeadline: Bool
    let onSearch: () -> Void

    @EnvironmentObject var settings: AppSettings

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private var searchText: String {
        let numStr = Self.formatter.string(from: NSNumber(value: totalEntries)) ?? "\(totalEntries)"
        return "Search \(numStr) sites"
    }

    var body: some View {
        SwiftUI.Section {
            Button(action: onSearch) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .foregroundStyle(settings.accent.color)
                    Text(searchText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .fmhyRowBackground()
        } header: {
            if showHeadline {
                Text("Search")
            }
        }
    }
}

struct NewSinceBlockView: View {
    let count: Int
    let onOpen: () -> Void

    @EnvironmentObject var settings: AppSettings

    private var newSinceText: String {
        "\(count) new since your last visit"
    }

    var body: some View {
        if count > 0 {
            SwiftUI.Section {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.body.weight(.medium))
                            .foregroundStyle(settings.accent.color)
                        Text(newSinceText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                .fmhyRowBackground()
            }
        }
    }
}

struct RandomPickBlockView: View {
    @Binding var pickId: String?
    let onSelect: (Entry) -> Void

    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var bookmarks: Bookmarks
    @EnvironmentObject var hub: BrowserHub
    @EnvironmentObject var settings: AppSettings

    private var currentEntry: Entry? {
        if let id = pickId, let found = store.entries.first(where: { $0.id == id }) {
            return found
        }
        return nil
    }

    private func chooseRandomPick() {
        let pool = store.entries.filter { $0.tier >= 1 }
        let candidatePool = pool.isEmpty ? store.entries : pool
        guard !candidatePool.isEmpty else { return }
        let others = candidatePool.filter { $0.id != pickId }
        let chosen = (others.isEmpty ? candidatePool : others).randomElement()
        pickId = chosen?.id
    }

    private func isSaved(_ id: String) -> Bool {
        bookmarks.isSaved(id)
    }

    private func headingCategory(_ headingPath: String) -> String {
        let parts = headingPath.split(separator: "›").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.last ?? headingPath
    }

    var body: some View {
        if let entry = currentEntry {
            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        onSelect(entry)
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            if entry.tier == 2 {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.subheadline)
                                    .accessibilityLabel("Top pick")
                            } else if entry.tier == 1 {
                                Image(systemName: "star")
                                    .foregroundStyle(.yellow)
                                    .font(.subheadline)
                                    .accessibilityLabel("Starred")
                            }

                            Text(entry.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            if !entry.headingPath.isEmpty {
                                Text(headingCategory(entry.headingPath))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if !entry.description.isEmpty {
                        Text(entry.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        Button {
                            chooseRandomPick()
                        } label: {
                            Label("Another one", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(settings.accent.color)

                        Spacer()

                        Button {
                            if let target = SafariTarget(urlString: entry.url) {
                                hub.open(target.url)
                            }
                        } label: {
                            Label("Open", systemImage: "safari")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            bookmarks.toggle(entry.id)
                        } label: {
                            Image(systemName: isSaved(entry.id) ? "bookmark.fill" : "bookmark")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(isSaved(entry.id) ? .yellow : .primary)
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
                .fmhyRowBackground()
            } header: {
                Text("Random pick")
            }
            .onAppear {
                if pickId == nil {
                    chooseRandomPick()
                }
            }
        } else {
            EmptyView()
                .onAppear {
                    if pickId == nil {
                        chooseRandomPick()
                    }
                }
        }
    }
}

struct PinnedSectionPair: Identifiable {
    let id: String
    let first: WikiSection
    let second: WikiSection?
}

struct PinnedBlockView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var settings: AppSettings

    private var pinnedSections: [WikiSection] {
        store.sections.filter { follows.isFollowing($0.id) }
    }

    private var pairs: [PinnedSectionPair] {
        Self.makePairs(pinnedSections)
    }

    nonisolated static func makePairs(_ list: [WikiSection]) -> [PinnedSectionPair] {
        var result: [PinnedSectionPair] = []
        var i = 0
        while i < list.count {
            let first = list[i]
            let second = (i + 1 < list.count) ? list[i + 1] : nil
            let pairId = "\(first.id)_\(second?.id ?? "")"
            result.append(PinnedSectionPair(id: pairId, first: first, second: second))
            i += 2
        }
        return result
    }

    var body: some View {
        if !pinnedSections.isEmpty {
            SwiftUI.Section {
                ForEach(pairs) { pair in
                    HStack(spacing: 8) {
                        PinnedTile(section: pair.first)
                        if let second = pair.second {
                            PinnedTile(section: second)
                        } else {
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .fmhyRowBackground()
                }
            } header: {
                HStack {
                    Text("Pinned categories")
                    Spacer()
                    NavigationLink {
                        FollowingView()
                    } label: {
                        Text("Manage")
                            .font(.subheadline)
                            .foregroundStyle(settings.accent.color)
                    }
                }
            }
        }
    }
}

struct PinnedTile: View {
    let section: WikiSection
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationLink(value: section) {
            HStack(spacing: 8) {
                Image(systemName: sectionSymbol(section.id))
                    .font(.subheadline)
                    .foregroundStyle(settings.accent.color)
                    .frame(width: 20)

                Text(section.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                follows.toggle(section.id)
            } label: {
                Label("Unfollow", systemImage: "bell.slash")
            }
        }
    }
}

struct NewInPinnedBlockView: View {
    let onSelect: (Entry) -> Void
    let onSeeAll: () -> Void

    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var changes: ChangesStore
    @EnvironmentObject var settings: AppSettings

    private var items: [Entry] {
        let followedChanges = changes.changes.filter { change in
            change.kind == "added" &&
            change.ts > changes.lastSeenTs &&
            follows.isFollowing(change.sectionId)
        }
        guard !followedChanges.isEmpty else { return [] }

        var entryMap: [String: Entry] = [:]
        for entry in store.entries {
            let norm = ChangesStore.normalizeURL(entry.url)
            if !norm.isEmpty && entryMap[norm] == nil {
                entryMap[norm] = entry
            }
        }

        var result: [Entry] = []
        var seenURLs = Set<String>()

        for change in followedChanges {
            let norm = ChangesStore.normalizeURL(change.url)
            guard !norm.isEmpty, seenURLs.insert(norm).inserted else { continue }
            if let entry = entryMap[norm] {
                result.append(entry)
            } else {
                let synthetic = Entry(
                    id: change.id,
                    sectionId: change.sectionId,
                    headingId: nil,
                    ord: 0,
                    name: change.name,
                    url: change.url,
                    originalUrl: nil,
                    description: change.detail,
                    tags: [],
                    headingPath: "",
                    tier: 0,
                    kind: 0,
                    isInlineMore: false,
                    isBase64: false,
                    mirrors: [],
                    extraLinks: []
                )
                result.append(synthetic)
            }
            if result.count >= 5 {
                break
            }
        }
        return result
    }

    var body: some View {
        if !items.isEmpty {
            SwiftUI.Section {
                ForEach(items) { entry in
                    EntryRow(entry: entry) { selected in
                        onSelect(selected)
                    }
                    .fmhyRowBackground()
                }

                Button(action: onSeeAll) {
                    HStack {
                        Spacer()
                        Text("See all ›")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(settings.accent.color)
                    }
                    .padding(.vertical, 2)
                }
                .fmhyRowBackground()
            } header: {
                Text("New in pinned categories")
            }
        }
    }
}

struct FavouritesBlockView: View {
    let onSelect: (Entry) -> Void
    let onSeeAll: () -> Void

    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var bookmarks: Bookmarks
    @EnvironmentObject var settings: AppSettings

    private var items: [Entry] {
        let saved = bookmarks.entries(from: store.entries)
        guard !saved.isEmpty else { return [] }
        return Array(saved.reversed().prefix(5))
    }

    var body: some View {
        if !items.isEmpty {
            SwiftUI.Section {
                ForEach(items) { entry in
                    EntryRow(entry: entry) { selected in
                        onSelect(selected)
                    }
                    .fmhyRowBackground()
                }

                Button(action: onSeeAll) {
                    HStack {
                        Spacer()
                        Text("Saved ›")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(settings.accent.color)
                    }
                    .padding(.vertical, 2)
                }
                .fmhyRowBackground()
            } header: {
                Text("Favourites")
            }
        }
    }
}

struct SuggestionsBlockView: View {
    let onSelect: (Entry) -> Void

    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var visits: VisitTracker
    @EnvironmentObject var settings: AppSettings

    private var topSections: [String] {
        visits.topSections(limit: 4)
    }

    private var hasVisitedSections: Bool {
        !topSections.isEmpty
    }

    private var items: [Entry] {
        guard !store.entries.isEmpty else { return [] }

        var result: [Entry] = []
        var seenIds = Set<String>()

        let recommendedPool = store.entries.filter { $0.tier >= 1 }
        if let pick = (recommendedPool.isEmpty ? store.entries : recommendedPool).randomElement() {
            if seenIds.insert(pick.id).inserted {
                result.append(pick)
            }
        }

        for sectionId in topSections {
            let sectionEntries = store.entries(in: sectionId)
            let starred = sectionEntries.filter { $0.tier >= 1 }
            let candidatePool = starred.isEmpty ? sectionEntries : starred
            for entry in candidatePool.prefix(2) {
                if result.count >= 5 { break }
                if seenIds.insert(entry.id).inserted {
                    result.append(entry)
                }
            }
            if result.count >= 5 { break }
        }

        for entry in recommendedPool {
            if result.count >= 5 { break }
            if seenIds.insert(entry.id).inserted {
                result.append(entry)
            }
        }

        return result
    }

    var body: some View {
        if !items.isEmpty {
            SwiftUI.Section {
                ForEach(items) { entry in
                    EntryRow(entry: entry) { selected in
                        onSelect(selected)
                    }
                    .fmhyRowBackground()
                }

                if !hasVisitedSections {
                    Text("Open sections to see recommendations from your most visited categories here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                        .fmhyRowBackground()
                }
            } header: {
                Text("Suggestions")
            }
        }
    }
}

struct SectionsListBlock: View {
    let headerText: String

    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var settings: AppSettings

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private func formatSiteCount(_ count: Int) -> String {
        let formatted = Self.countFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return count == 1 ? "\(formatted) site" : "\(formatted) sites"
    }

    private func siteCount(for sectionId: String) -> String {
        let count = store.sectionCounts[sectionId] ?? 0
        return formatSiteCount(count)
    }

    private var layoutGroups: [(title: String, sections: [WikiSection])] {
        SectionLayout.layout(sections: store.sections)
    }

    var body: some View {
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

                                Text(siteCount(for: section.id))
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
                        Text(headerText)
                            .textCase(nil)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)
                        Text(group.title)
                    }
                } else {
                    Text(group.title)
                }
            }
        }
    }
}

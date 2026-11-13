import SwiftUI

struct PostsYearGroup: Identifiable {
    let id: String
    let year: String
    let posts: [WikiPost]
}

struct PostsView: View {
    @EnvironmentObject var postsStore: PostsStore

    private var yearGroups: [PostsYearGroup] {
        var groups: [String: [WikiPost]] = [:]
        var yearsOrder: [String] = []

        for post in postsStore.posts {
            let yearString: String
            if post.date > 0 {
                let date = Date(timeIntervalSince1970: TimeInterval(post.date))
                let cal = Calendar(identifier: .gregorian)
                let y = cal.component(.year, from: date)
                yearString = String(y)
            } else {
                yearString = "Other"
            }

            if groups[yearString] == nil {
                groups[yearString] = []
                yearsOrder.append(yearString)
            }
            groups[yearString]?.append(post)
        }

        return yearsOrder.map { yr in
            PostsYearGroup(id: yr, year: yr, posts: groups[yr] ?? [])
        }
    }

    private var offlineBannerSection: some View {
        SwiftUI.Section {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Offline · showing cached posts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .fmhyRowBackground()
        }
    }

    private var mainList: some View {
        List {
            if postsStore.isOffline {
                offlineBannerSection
            }

            ForEach(yearGroups) { group in
                SwiftUI.Section {
                    ForEach(group.posts) { post in
                        NavigationLink {
                            PostDetailView(post: post)
                        } label: {
                            PostListRow(
                                post: post,
                                isUnread: !postsStore.readPaths.contains(post.path)
                            )
                        }
                        .fmhyRowBackground()
                    }
                } header: {
                    Text(group.year)
                }
            }
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
        .refreshable {
            await postsStore.refresh(force: true)
        }
    }

    private var contentBody: some View {
        Group {
            if postsStore.isLoading && postsStore.posts.isEmpty {
                ProgressView("Loading posts…")
            } else if postsStore.errorMessage != nil && postsStore.posts.isEmpty {
                ContentUnavailableView {
                    Label("Unable to Load Posts", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(postsStore.errorMessage ?? "An error occurred while loading posts.")
                } actions: {
                    Button("Try Again") {
                        Task {
                            await postsStore.refresh(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if postsStore.posts.isEmpty {
                ContentUnavailableView(
                    "No Posts",
                    systemImage: "newspaper",
                    description: Text("No posts available yet.")
                )
            } else {
                mainList
            }
        }
    }

    private var layerOne: some View {
        contentBody
            .navigationTitle("News & posts")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if postsStore.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task {
                                await postsStore.refresh(force: true)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh posts")
                    }

                    if postsStore.unreadCount > 0 {
                        Button("Mark all read") {
                            postsStore.markAllRead()
                        }
                    }
                }
            }
    }

    var body: some View {
        layerOne
    }
}

struct PostListRow: View {
    let post: WikiPost
    let isUnread: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isUnread {
                Circle()
                    .fill(fmhyPurple)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(post.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !post.dateText.isEmpty {
                    Text(post.dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

struct PostParsedSection: Identifiable, Hashable {
    let id: String
    let heading: String?
    let level: Int
    let blocks: [PostDetailBlock]
}

enum PostDetailBlock: Identifiable, Hashable {
    case site(PostSiteRow)
    case paragraph(String)

    var id: String {
        switch self {
        case .site(let row):
            return "s-\(row.id)"
        case .paragraph(let text):
            return "p-\(text.hashValue)"
        }
    }
}

enum PostBodyParser {
    nonisolated static func parseSections(from markdown: String) -> [PostParsedSection] {
        let cleaned = PostsListing.stripFrontMatter(markdown)
        let lines = cleaned.components(separatedBy: .newlines)

        var sections: [PostParsedSection] = []
        var currentHeading: String? = nil
        var currentLevel: Int = 1
        var currentBlocks: [PostDetailBlock] = []
        var currentParagraphLines: [String] = []

        func flushParagraph() {
            let text = currentParagraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                currentBlocks.append(.paragraph(text))
            }
            currentParagraphLines.removeAll()
        }

        func flushSection(index: Int) {
            flushParagraph()
            if currentHeading != nil || !currentBlocks.isEmpty {
                let id = "sec-\(index)-\(currentHeading ?? "root")"
                sections.append(PostParsedSection(
                    id: id,
                    heading: currentHeading,
                    level: currentLevel,
                    blocks: currentBlocks
                ))
            }
            currentBlocks.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                let level = hashes.count
                let remainder = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty {
                    flushSection(index: sections.count)
                    currentHeading = remainder
                    currentLevel = level
                    continue
                }
            }

            if let siteRow = PostsListing.parsePostSiteRow(trimmed) {
                flushParagraph()
                currentBlocks.append(.site(siteRow))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            currentParagraphLines.append(line)
        }

        flushSection(index: sections.count)
        return sections
    }
}

struct PostDetailView: View {
    let post: WikiPost
    @EnvironmentObject var postsStore: PostsStore
    @EnvironmentObject var hub: BrowserHub

    @State private var bodyMarkdown: String = ""
    @State private var isLoadingBody: Bool = true
    @State private var loadFailed: Bool = false

    private var parsedSections: [PostParsedSection] {
        PostBodyParser.parseSections(from: bodyMarkdown)
    }

    private var gitHubURL: URL? {
        URL(string: "https://github.com/fmhy/edit/blob/main/docs/\(post.path)")
    }

    private func fontForHeading(level: Int) -> Font {
        switch level {
        case ..<2:
            return .title3.bold()
        case 2:
            return .headline
        default:
            return .subheadline.weight(.semibold)
        }
    }

    private var headerSection: some View {
        SwiftUI.Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(post.title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                if !post.dateText.isEmpty {
                    Text(post.dateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .fmhyRowBackground()
        }
    }

    private var sectionsList: some View {
        List {
            headerSection

            ForEach(parsedSections) { sec in
                SwiftUI.Section {
                    ForEach(sec.blocks) { block in
                        switch block {
                        case .site(let row):
                            PostSiteRowView(row: row)
                        case .paragraph(let text):
                            PostParagraphView(markdown: text)
                        }
                    }
                } header: {
                    if let heading = sec.heading {
                        Text(heading)
                            .font(fontForHeading(level: sec.level))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
    }

    private var detailContent: some View {
        Group {
            if isLoadingBody && bodyMarkdown.isEmpty {
                ProgressView("Loading post…")
            } else if loadFailed && bodyMarkdown.isEmpty {
                ContentUnavailableView {
                    Label("Unable to Load Post", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Could not download the post contents.")
                } actions: {
                    Button("Retry") {
                        Task {
                            await loadContent()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                sectionsList
            }
        }
    }

    private var layerOne: some View {
        detailContent
            .navigationTitle(post.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let url = gitHubURL {
                        SwiftUI.Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .accessibilityLabel("Open on GitHub")

                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
    }

    private var layerTwo: some View {
        layerOne
            .onAppear {
                postsStore.markRead(post.path)
            }
            .task {
                await loadContent()
            }
    }

    var body: some View {
        layerTwo
    }

    private func loadContent() async {
        if !post.bodyMd.isEmpty {
            bodyMarkdown = post.bodyMd
            isLoadingBody = false
            return
        }
        isLoadingBody = true
        loadFailed = false
        if let body = await postsStore.fetchBody(for: post) {
            bodyMarkdown = body
            isLoadingBody = false
        } else {
            isLoadingBody = false
            loadFailed = true
        }
    }
}

struct PostSiteRowView: View {
    let row: PostSiteRow
    @EnvironmentObject var hub: BrowserHub

    private var targetURL: URL? {
        SafariTarget(urlString: row.url)?.url
    }

    var body: some View {
        Button {
            hub.open(row.url)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !row.description.isEmpty {
                        MarkdownText(markdown: row.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    if !row.url.hostOnly.isEmpty {
                        Text(row.url.hostOnly)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                Image(systemName: "safari")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fmhyRowBackground()
        .contextMenu {
            Button {
                hub.open(row.url)
            } label: {
                Label("Open site", systemImage: "safari")
            }
            .disabled(targetURL == nil)

            Button {
                if let url = targetURL {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open in Safari", systemImage: "safari")
            }
            .disabled(targetURL == nil)

            Button {
                UIPasteboard.general.string = row.url
            } label: {
                Label("Copy link", systemImage: "doc.on.doc")
            }

            if let url = targetURL {
                ShareLink(item: url) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

struct PostParagraphView: View {
    let markdown: String

    var body: some View {
        MarkdownText(markdown: markdown)
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.vertical, 2)
            .fmhyRowBackground()
    }
}

struct MarkdownText: View {
    let markdown: String

    private var attributed: AttributedString? {
        try? AttributedString(markdown: markdown)
    }

    var body: some View {
        if let attributed = attributed {
            Text(attributed)
        } else {
            Text(markdown)
        }
    }
}

import SwiftUI
import Foundation

enum ReaderBlock: Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case callout(type: String, text: String)
    case listItem(String)
    case divider
}

struct ReaderBlockItem: Identifiable, Sendable {
    let id: Int
    let block: ReaderBlock
}

struct ReaderUnsafeAlert: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let reason: String
}

struct ReaderView: View {
    let path: String
    let title: String

    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var hub: BrowserHub
    @EnvironmentObject var settings: AppSettings

    @State private var documentText: String? = nil
    @State private var isLoading: Bool = true
    @State private var pendingUnsafeAlert: ReaderUnsafeAlert? = nil

    init(path: String = "beginners-guide.md", title: String = "Beginner's guide") {
        self.path = path
        self.title = title
    }

    private var isGuide: Bool {
        Self.isGuidePath(path)
    }

    private var webURL: URL? {
        Self.fmhyWebURL(for: path)
    }

    private var blocks: [ReaderBlockItem] {
        guard let text = documentText else { return [] }
        return Self.parseBlocks(from: text)
    }

    // MARK: - Pure Helpers

    nonisolated static func isGuidePath(_ path: String) -> Bool {
        let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return clean == "beginners-guide.md" || clean.hasSuffix("/beginners-guide.md") || clean == "beginners-guide"
    }

    nonisolated static func fmhyWebURL(for path: String) -> URL? {
        var clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix("/") {
            clean.removeFirst()
        }
        if clean.hasPrefix("docs/") {
            clean = String(clean.dropFirst(5))
        }
        while clean.hasPrefix("/") {
            clean.removeFirst()
        }
        if clean.hasSuffix(".md") {
            clean = String(clean.dropLast(3))
        }
        guard !clean.isEmpty else {
            return URL(string: "https://fmhy.net")
        }
        return URL(string: "https://fmhy.net/\(clean)")
    }

    nonisolated static func cachedDocumentURL(path: String) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let cacheDir = appSupport.appendingPathComponent("wiki")
        let fileURL = cacheDir.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    nonisolated static func bundledDocumentURL(path: String) -> URL? {
        let bundledDir = WikiStore.bundledDataURL()
        let fileURL = bundledDir.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    nonisolated static func loadDocument(path: String) -> String? {
        if let cachedURL = cachedDocumentURL(path: path),
           let content = try? String(contentsOf: cachedURL, encoding: .utf8),
           !content.isEmpty {
            return content
        }
        if let bundledURL = bundledDocumentURL(path: path),
           let content = try? String(contentsOf: bundledURL, encoding: .utf8),
           !content.isEmpty {
            return content
        }
        return nil
    }

    nonisolated static func parseBlocks(from markdown: String) -> [ReaderBlockItem] {
        let lines = markdown.components(separatedBy: .newlines)
        var items: [ReaderBlockItem] = []
        var currentParagraphLines: [String] = []

        func flushParagraph() {
            let text = currentParagraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                items.append(ReaderBlockItem(id: items.count, block: .paragraph(text)))
            }
            currentParagraphLines.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "***" || trimmed == "---" || trimmed == "___" {
                flushParagraph()
                items.append(ReaderBlockItem(id: items.count, block: .divider))
                continue
            }

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                let level = hashes.count
                if level <= 6 {
                    let remainder = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                    if !remainder.isEmpty {
                        flushParagraph()
                        items.append(ReaderBlockItem(id: items.count, block: .heading(level: level, text: remainder)))
                        continue
                    }
                }
            }

            if trimmed.hasPrefix("!!!") {
                flushParagraph()
                let afterExcl = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                let parts = afterExcl.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                let type = parts.first.map(String.init)?.lowercased() ?? "note"
                let content = parts.count > 1 ? String(parts[1]) : ""
                items.append(ReaderBlockItem(id: items.count, block: .callout(type: type, text: content)))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let content = trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces)
                items.append(ReaderBlockItem(id: items.count, block: .quote(content)))
                continue
            }

            if (trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ")) && !trimmed.hasPrefix("***") && !trimmed.hasPrefix("---") {
                flushParagraph()
                let content = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                items.append(ReaderBlockItem(id: items.count, block: .listItem(content)))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            currentParagraphLines.append(line)
        }

        flushParagraph()
        return items
    }

    // MARK: - Actions

    private func loadContent() {
        isLoading = true
        let content = Self.loadDocument(path: path)
        self.documentText = content
        self.isLoading = false
    }

    private func handleOpenURL(_ url: URL) {
        guard let target = SafariTarget(url: url) else { return }
        if let safeGuard = store.safeGuard {
            let verdict = safeGuard.check(url.absoluteString)
            if verdict.status == .unsafe {
                pendingUnsafeAlert = ReaderUnsafeAlert(
                    url: target.url,
                    reason: verdict.reason ?? "On the FMHY unsafe list"
                )
                return
            }
        }
        hub.open(target.url)
    }

    // MARK: - View Layers

    var body: some View {
        layerTwo
    }

    private var layerOne: some View {
        mainContent
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .environment(\.openURL, OpenURLAction { url in
                handleOpenURL(url)
                return .handled
            })
            .task {
                loadContent()
            }
    }

    private var layerTwo: some View {
        layerOne
            .alert(
                "Blocked unsafe site",
                isPresented: Binding(
                    get: { pendingUnsafeAlert != nil },
                    set: { if !$0 { pendingUnsafeAlert = nil } }
                ),
                presenting: pendingUnsafeAlert
            ) { item in
                Button("Open anyway", role: .destructive) {
                    hub.open(item.url)
                    pendingUnsafeAlert = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUnsafeAlert = nil
                }
            } message: { item in
                Text(item.reason)
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if documentText != nil && !documentText!.isEmpty {
            documentScrollView
        } else {
            errorView
        }
    }

    private var documentScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if isGuide {
                    guideHeader
                    Divider()
                        .padding(.vertical, 4)
                }
                ForEach(blocks) { item in
                    blockView(item.block)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var guideHeader: some View {
        VStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(settings.accent.color.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: "graduationcap")
                    .font(.system(size: 28))
                    .foregroundStyle(settings.accent.color)
            }
            Text("Beginner's guide")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text("Start here: the basics of staying safe and finding things on FMHY.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Could not load document", systemImage: "icloud.slash")
        } description: {
            Text("The document is not available offline.")
        } actions: {
            Button("Retry") {
                loadContent()
            }
            .buttonStyle(.bordered)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let url = webURL {
                    Button {
                        hub.open(url)
                    } label: {
                        Label("Open on fmhy.net", systemImage: "arrow.up.right.square")
                    }

                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More options")
        }
    }

    // MARK: - Block Views

    @ViewBuilder
    private func blockView(_ block: ReaderBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .paragraph(let text):
            paragraphView(text: text)
        case .quote(let text):
            quoteView(text: text)
        case .callout(let type, let text):
            calloutView(type: type, text: text)
        case .listItem(let text):
            listItemView(text: text)
        case .divider:
            dividerView
        }
    }

    private func headingView(level: Int, text: String) -> some View {
        Text(text)
            .font(fontForHeading(level))
            .foregroundStyle(.primary)
            .padding(.top, 8)
    }

    private func paragraphView(text: String) -> some View {
        MarkdownText(markdown: text)
            .font(.body)
            .foregroundStyle(.primary)
    }

    private func quoteView(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(settings.accent.color.opacity(0.6))
                .frame(width: 3)
            MarkdownText(markdown: text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func calloutView(type: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: calloutIcon(for: type))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(calloutColor(for: type))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(type.capitalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(calloutColor(for: type))
                MarkdownText(markdown: text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(calloutColor(for: type).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func listItemView(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body.weight(.bold))
                .foregroundStyle(.secondary)
            MarkdownText(markdown: text)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private var dividerView: some View {
        Divider()
            .padding(.vertical, 6)
    }

    private func fontForHeading(_ level: Int) -> Font {
        switch level {
        case ..<2:
            return .title.bold()
        case 2:
            return .title2.bold()
        case 3:
            return .title3.bold()
        case 4:
            return .headline
        default:
            return .subheadline.weight(.semibold)
        }
    }

    private func calloutColor(for type: String) -> Color {
        switch type {
        case "tip":
            return .green
        case "warning", "caution", "danger":
            return .orange
        default:
            return settings.accent.color
        }
    }

    private func calloutIcon(for type: String) -> String {
        switch type {
        case "tip":
            return "lightbulb.fill"
        case "warning", "caution", "danger":
            return "exclamationmark.triangle.fill"
        default:
            return "info.circle.fill"
        }
    }
}

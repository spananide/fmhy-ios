import Foundation
import Combine

struct WikiPost: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let path: String
    let title: String
    let date: Int64
    let dateText: String
    var bodyMd: String

    var dateEpoch: Int64 { date }

    init(
        id: String? = nil,
        path: String,
        title: String,
        date: Int64,
        dateText: String = "",
        bodyMd: String = ""
    ) {
        self.id = id ?? path
        self.path = path
        self.title = title
        self.date = date
        self.dateText = dateText
        self.bodyMd = bodyMd
    }
}

struct CachedPostsData: Codable, Sendable {
    let fetchedAt: Int64
    let posts: [WikiPost]
}

struct PostSiteRow: Hashable, Identifiable, Sendable {
    var id: String { "\(name)|\(url)" }
    let name: String
    let url: String
    let description: String
}

struct PostNotificationContent: Equatable, Sendable {
    let title: String
    let body: String
}

enum NewPostsDecision {
    nonisolated static func newUnreadPosts(
        listed: [WikiPost],
        previouslyKnown: Set<String>?,
        read: Set<String>?
    ) -> [WikiPost] {
        guard let previouslyKnown = previouslyKnown, let read = read else {
            return []
        }
        return listed
            .filter { !previouslyKnown.contains($0.path) && !read.contains($0.path) }
            .sorted { $0.date > $1.date }
    }

    nonisolated static func newPostsNotificationText(newPosts: [WikiPost]) -> PostNotificationContent? {
        guard let newest = newPosts.first else { return nil }
        let more = newPosts.count - 1
        let text = more > 0 ? "\(newest.title) and \(more) more" : newest.title
        return PostNotificationContent(title: "New FMHY post", body: text)
    }

    nonisolated static func shouldCheckPosts(lastCheckEpochSec: Int64?, nowSec: Int64) -> Bool {
        guard let last = lastCheckEpochSec else { return true }
        return nowSec - last >= 86400 || nowSec < last
    }
}

enum PostsListing {
    nonisolated static let monthMap: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12
    ]

    nonisolated static let monthNames: [String] = [
        "", "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    private nonisolated static let monthRegex: NSRegularExpression? = {
        let pattern = "^(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)[-_](\\d{4})$"
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    nonisolated static func baseFileName(from fileName: String) -> String {
        var base = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastSlash = base.lastIndex(of: "/") {
            base = String(base[base.index(after: lastSlash)...])
        }
        if base.lowercased().hasSuffix(".md") {
            base = String(base.dropLast(3))
        }
        return base
    }

    nonisolated static func parseMonthAndYear(from fileName: String) -> (month: Int, year: Int)? {
        let base = baseFileName(from: fileName)
        guard let regex = monthRegex else { return nil }
        let ns = base as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: base, options: [], range: range),
              match.numberOfRanges == 3 else {
            return nil
        }
        let monthStr = ns.substring(with: match.range(at: 1)).lowercased()
        let yearStr = ns.substring(with: match.range(at: 2))
        guard let monthNum = monthMap[monthStr], let yearNum = Int(yearStr) else {
            return nil
        }
        return (month: monthNum, year: yearNum)
    }

    nonisolated static func parseISO8601Date(_ str: String) -> Int64? {
        let parts = str.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else {
            return nil
        }
        var comps = DateComponents()
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        guard let date = Calendar(identifier: .gregorian).date(from: comps) else {
            return nil
        }
        return Int64(date.timeIntervalSince1970)
    }

    nonisolated static func parseDate(fileName: String, frontMatterDate: String?) -> Int64 {
        if let fmd = frontMatterDate?.trimmingCharacters(in: .whitespacesAndNewlines), !fmd.isEmpty {
            if let epoch = parseISO8601Date(fmd) {
                return epoch
            }
        }
        if let (month, year) = parseMonthAndYear(from: fileName) {
            var comps = DateComponents()
            comps.timeZone = TimeZone(secondsFromGMT: 0)
            comps.year = year
            comps.month = month
            comps.day = 1
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
            if let date = Calendar(identifier: .gregorian).date(from: comps) {
                return Int64(date.timeIntervalSince1970)
            }
        }
        return 0
    }

    nonisolated static func formatDefaultTitle(fileName: String) -> String {
        let base = baseFileName(from: fileName)
        if let (month, year) = parseMonthAndYear(from: base) {
            let monthName = (month >= 1 && month < monthNames.count) ? monthNames[month] : "Monthly"
            return "Monthly Updates [\(monthName) \(year)]"
        }
        let pieces = base.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .filter { !$0.isEmpty }
            .map { part -> String in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + String(part.dropFirst())
            }
        return pieces.joined(separator: " ")
    }

    nonisolated static func formatDateText(fileName: String, frontMatterDate: String?, dateEpoch: Int64) -> String {
        if let fmd = frontMatterDate?.trimmingCharacters(in: .whitespacesAndNewlines), !fmd.isEmpty {
            return fmd
        }
        if let (month, year) = parseMonthAndYear(from: fileName) {
            let monthName = (month >= 1 && month < monthNames.count) ? monthNames[month] : ""
            return "\(monthName) \(year)"
        }
        if dateEpoch > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(dateEpoch))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
        return ""
    }

    nonisolated static func extractFrontMatter(_ text: String) -> (frontMatter: [String: String], body: String) {
        var lines = text.components(separatedBy: .newlines)
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces), first == "---" else {
            return ([:], text)
        }
        lines.removeFirst()
        var fm: [String: String] = [:]
        var bodyStartIndex: Int? = nil

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                bodyStartIndex = idx + 1
                break
            }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    fm[key] = val
                }
            }
        }

        if let start = bodyStartIndex {
            let bodyLines = lines[start...]
            return (fm, bodyLines.joined(separator: "\n"))
        } else {
            return ([:], text)
        }
    }

    nonisolated static func stripFrontMatter(_ text: String) -> String {
        extractFrontMatter(text).body
    }

    nonisolated static func parseGitHubListing(json: Data) throws -> [String] {
        if let array = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] {
            return array.compactMap { item in
                guard let name = item["name"] as? String,
                      let type = item["type"] as? String,
                      type == "file",
                      name.lowercased().hasSuffix(".md") else {
                    return nil
                }
                return name
            }
        }
        if let dict = try? JSONSerialization.jsonObject(with: json) as? [String: Any] {
            if let tree = dict["tree"] as? [[String: Any]] {
                return tree.compactMap { item in
                    guard let path = item["path"] as? String,
                          let type = item["type"] as? String,
                          type == "blob",
                          path.lowercased().hasSuffix(".md") else {
                        return nil
                    }
                    if path.hasPrefix("docs/posts/") {
                        let name = String(path.dropFirst("docs/posts/".count))
                        return name.contains("/") ? nil : name
                    } else if !path.contains("/") {
                        return path
                    }
                    return nil
                }
            }
            if let files = dict["files"] as? [[String: Any]] {
                var result: [String] = []
                for fileObj in files {
                    guard let name = fileObj["name"] as? String else { continue }
                    if name.lowercased().hasPrefix("/docs/posts/") && name.lowercased().hasSuffix(".md") {
                        let fileName = String(name.dropFirst("/docs/posts/".count))
                        if !fileName.contains("/") {
                            result.append(fileName)
                        }
                    }
                }
                return result
            }
        }
        return []
    }

    nonisolated static func parsePostSiteRow(_ text: String) -> PostSiteRow? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("- ") {
            s = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if s.hasPrefix("* ") {
            s = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if s.hasPrefix("+ ") {
            s = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }

        let bold = s.hasPrefix("**")
        if bold {
            s = String(s.dropFirst(2))
        }
        guard s.hasPrefix("[") else { return nil }
        guard let closeRange = s.range(of: "](") else { return nil }

        let label = String(s[s.index(after: s.startIndex)..<closeRange.lowerBound])
        guard !label.contains("["), !label.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        var i = closeRange.upperBound
        var depth = 1
        let urlStart = i

        while i < s.endIndex {
            let ch = s[i]
            if ch == "(" {
                depth += 1
            } else if ch == ")" {
                depth -= 1
                if depth == 0 {
                    break
                }
            }
            i = s.index(after: i)
        }

        guard depth == 0 else { return nil }

        var rawURL = String(s[urlStart..<i]).trimmingCharacters(in: .whitespaces)
        if rawURL.hasPrefix("<") {
            rawURL = String(rawURL.dropFirst())
        }
        if rawURL.hasSuffix(">") {
            rawURL = String(rawURL.dropLast())
        }
        let url = rawURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return nil }

        var rest = String(s[s.index(after: i)...])
        if bold {
            guard rest.hasPrefix("**") else { return nil }
            rest = String(rest.dropFirst(2))
        }

        let name = label
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        var desc = rest.trimmingCharacters(in: .whitespaces)
        let separators = ["-", "–", "—", ",", ":"]
        for sep in separators {
            let prefix = sep + " "
            if desc.hasPrefix(prefix) {
                desc = String(desc.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        return PostSiteRow(name: name, url: url, description: desc)
    }

    nonisolated static func resolvePost(fileName: String, bodyMd: String? = nil) -> WikiPost {
        let relPath = fileName.hasPrefix("posts/") ? fileName : "posts/\(fileName)"
        let base = baseFileName(from: fileName)

        if let body = bodyMd, !body.isEmpty {
            let (fm, cleanBody) = extractFrontMatter(body)
            let fmTitle = fm["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fmDate = fm["date"]?.trimmingCharacters(in: .whitespacesAndNewlines)

            let parsedDate = parseDate(fileName: base, frontMatterDate: fmDate)
            let title = (fmTitle != nil && !fmTitle!.isEmpty) ? fmTitle! : formatDefaultTitle(fileName: base)
            let dateText = formatDateText(fileName: base, frontMatterDate: fmDate, dateEpoch: parsedDate)

            return WikiPost(
                id: relPath,
                path: relPath,
                title: title,
                date: parsedDate,
                dateText: dateText,
                bodyMd: cleanBody
            )
        } else {
            let parsedDate = parseDate(fileName: base, frontMatterDate: nil)
            let title = formatDefaultTitle(fileName: base)
            let dateText = formatDateText(fileName: base, frontMatterDate: nil, dateEpoch: parsedDate)

            return WikiPost(
                id: relPath,
                path: relPath,
                title: title,
                date: parsedDate,
                dateText: dateText,
                bodyMd: ""
            )
        }
    }
}

@MainActor final class PostsStore: ObservableObject {
    @Published private(set) var posts: [WikiPost] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isOffline: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var readPaths: Set<String> = []

    private let readPathsKey = "posts.read.v1"
    private let lastCheckKey = "posts.lastCheck.v1"
    private let userDefaults: UserDefaults

    static var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("posts-listing-v2.json")
    }

    static var postBodiesDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("post_bodies", isDirectory: true)
    }

    var unreadCount: Int {
        posts.filter { !readPaths.contains($0.path) }.count
    }

    var hasReadState: Bool {
        userDefaults.object(forKey: readPathsKey) != nil
    }

    var lastCheckEpochSec: Int64? {
        if userDefaults.object(forKey: lastCheckKey) != nil {
            return Int64(userDefaults.integer(forKey: lastCheckKey))
        }
        return nil
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let saved = userDefaults.stringArray(forKey: readPathsKey) {
            self.readPaths = Set(saved)
        } else {
            self.readPaths = []
        }
    }

    func recordLastCheck(_ epochSec: Int64) {
        userDefaults.set(Int(epochSec), forKey: lastCheckKey)
    }

    func markRead(_ path: String) {
        guard !readPaths.contains(path) else { return }
        readPaths.insert(path)
        userDefaults.set(Array(readPaths), forKey: readPathsKey)
    }

    func markAllRead() {
        let all = Set(posts.map { $0.path })
        readPaths.formUnion(all)
        userDefaults.set(Array(readPaths), forKey: readPathsKey)
    }

    func setPostsForTesting(_ newPosts: [WikiPost]) {
        self.posts = newPosts.sorted { $0.date > $1.date }
        initializeReadStateIfFirstRun(for: self.posts)
    }

    private func initializeReadStateIfFirstRun(for postList: [WikiPost]) {
        if userDefaults.object(forKey: readPathsKey) == nil {
            let all = Set(postList.map { $0.path })
            self.readPaths = all
            userDefaults.set(Array(all), forKey: readPathsKey)
        } else if let saved = userDefaults.stringArray(forKey: readPathsKey) {
            self.readPaths = Set(saved)
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let now = Int64(Date().timeIntervalSince1970)
        let cacheFile = Self.cacheFileURL

        if FileManager.default.fileExists(atPath: cacheFile.path),
           let data = try? Data(contentsOf: cacheFile),
           let cached = try? JSONDecoder().decode(CachedPostsData.self, from: data),
           !cached.posts.isEmpty {
            self.posts = cached.posts.sorted { $0.date > $1.date }
            self.isOffline = false
            initializeReadStateIfFirstRun(for: self.posts)

            let age = now - cached.fetchedAt
            if age < 86400 {
                return
            }
        }

        await refresh(force: false)
    }

    func refresh(force: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let now = Int64(Date().timeIntervalSince1970)
        let cacheFile = Self.cacheFileURL

        var cachedPosts: [WikiPost]? = nil
        if FileManager.default.fileExists(atPath: cacheFile.path),
           let data = try? Data(contentsOf: cacheFile),
           let cached = try? JSONDecoder().decode(CachedPostsData.self, from: data) {
            cachedPosts = cached.posts
        }

        do {
            let fileNames = try await fetchListingFromNetwork()
            let resolved = fileNames.map { fileName -> WikiPost in
                let relPath = fileName.hasPrefix("posts/") ? fileName : "posts/\(fileName)"
                let cachedBody = loadCachedBody(for: relPath)
                return PostsListing.resolvePost(fileName: fileName, bodyMd: cachedBody)
            }.sorted { $0.date > $1.date }

            self.posts = resolved
            self.isOffline = false
            self.errorMessage = nil
            initializeReadStateIfFirstRun(for: resolved)

            let toCache = CachedPostsData(fetchedAt: now, posts: resolved)
            if let encoded = try? JSONEncoder().encode(toCache) {
                let parent = cacheFile.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parent.path) {
                    try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try? encoded.write(to: cacheFile, options: .atomic)
            }
        } catch {
            if let cached = cachedPosts, !cached.isEmpty {
                self.posts = cached.sorted { $0.date > $1.date }
                self.isOffline = true
                self.errorMessage = nil
                initializeReadStateIfFirstRun(for: self.posts)
            } else {
                self.isOffline = true
                self.errorMessage = "Could not load posts. Please check your internet connection."
            }
        }
    }

    private func fetchListingFromNetwork() async throws -> [String] {
        let githubURL = URL(string: "https://api.github.com/repos/fmhy/edit/contents/docs/posts?ref=main")!
        var request = URLRequest(url: githubURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FMHY-iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                let files = try PostsListing.parseGitHubListing(json: data)
                if !files.isEmpty {
                    return files
                }
            }
        } catch {}

        let jsdelivrURL = URL(string: "https://data.jsdelivr.com/v1/packages/gh/fmhy/edit@main?structure=flat")!
        let (data, response) = try await URLSession.shared.data(from: jsdelivrURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let files = try PostsListing.parseGitHubListing(json: data)
        if files.isEmpty {
            throw URLError(.cannotParseResponse)
        }
        return files
    }

    private func loadCachedBody(for path: String) -> String? {
        let sanitized = path.replacingOccurrences(of: "/", with: "_")
        let fileURL = Self.postBodiesDirectoryURL.appendingPathComponent(sanitized)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    func fetchBody(for post: WikiPost) async -> String? {
        if let existing = posts.first(where: { $0.path == post.path }), !existing.bodyMd.isEmpty {
            return existing.bodyMd
        }

        if let cached = loadCachedBody(for: post.path), !cached.isEmpty {
            applyBody(cached, for: post.path)
            return cached
        }

        let primaryURL = URL(string: "https://raw.githubusercontent.com/fmhy/edit/main/docs/\(post.path)")!
        let fallbackURL = URL(string: "https://cdn.jsdelivr.net/gh/fmhy/edit@main/docs/\(post.path)")!

        var bodyData: Data? = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: primaryURL)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                bodyData = data
            }
        } catch {}

        if bodyData == nil {
            do {
                let (data, response) = try await URLSession.shared.data(from: fallbackURL)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    bodyData = data
                }
            } catch {}
        }

        guard let data = bodyData, let raw = String(data: data, encoding: .utf8) else {
            return nil
        }

        let parent = Self.postBodiesDirectoryURL
        if !FileManager.default.fileExists(atPath: parent.path) {
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let sanitized = post.path.replacingOccurrences(of: "/", with: "_")
        let fileURL = parent.appendingPathComponent(sanitized)
        try? data.write(to: fileURL, options: .atomic)

        applyBody(raw, for: post.path)
        return raw
    }

    private func applyBody(_ rawMarkdown: String, for path: String) {
        let (fm, body) = PostsListing.extractFrontMatter(rawMarkdown)
        let fmTitle = fm["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fmDate = fm["date"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let index = posts.firstIndex(where: { $0.path == path }) else { return }
        var updated = posts[index]
        updated.bodyMd = body

        var newTitle = updated.title
        var newDate = updated.date
        var newDateText = updated.dateText

        if let t = fmTitle, !t.isEmpty {
            newTitle = t
        }
        if let d = fmDate, !d.isEmpty, let epoch = PostsListing.parseISO8601Date(d) {
            newDate = epoch
            newDateText = d
        }

        posts[index] = WikiPost(
            id: updated.id,
            path: updated.path,
            title: newTitle,
            date: newDate,
            dateText: newDateText,
            bodyMd: body
        )
    }
}

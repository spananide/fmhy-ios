import Foundation
import Combine

struct WikiChange: Hashable, Identifiable, Sendable {
    let ts: Int
    let kind: String
    let sectionId: String
    let name: String
    let url: String
    let detail: String
    let commit: String

    var id: String { "\(commit)|\(kind)|\(url)|\(name)" }
}

enum ChangeFeedError: LocalizedError {
    case invalidGzipHeader
    case decompressionFailed
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidGzipHeader:
            return "Invalid gzip header"
        case .decompressionFailed:
            return "Failed to decompress change feed"
        case .invalidJSON:
            return "Failed to parse change feed JSON"
        }
    }
}

enum ChangeFeedDecoder {
    static func cleanInvisibleCharacters(_ string: String) -> String {
        let invisible: Set<Character> = ["\u{2060}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"]
        return String(string.filter { !invisible.contains($0) })
    }

    static func gunzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else {
            throw ChangeFeedError.invalidGzipHeader
        }
        guard bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else {
            throw ChangeFeedError.invalidGzipHeader
        }

        let flg = bytes[3]
        var offset = 10
        let tailLimit = bytes.count - 8

        // FEXTRA
        if flg & 0x04 != 0 {
            guard offset + 2 <= tailLimit else {
                throw ChangeFeedError.invalidGzipHeader
            }
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + xlen
            guard offset <= tailLimit else {
                throw ChangeFeedError.invalidGzipHeader
            }
        }

        // FNAME
        if flg & 0x08 != 0 {
            while offset < tailLimit && bytes[offset] != 0 {
                offset += 1
            }
            guard offset < tailLimit else {
                throw ChangeFeedError.invalidGzipHeader
            }
            offset += 1
        }

        // FCOMMENT
        if flg & 0x10 != 0 {
            while offset < tailLimit && bytes[offset] != 0 {
                offset += 1
            }
            guard offset < tailLimit else {
                throw ChangeFeedError.invalidGzipHeader
            }
            offset += 1
        }

        // FHCRC
        if flg & 0x02 != 0 {
            guard offset + 2 <= tailLimit else {
                throw ChangeFeedError.invalidGzipHeader
            }
            offset += 2
        }

        guard offset <= tailLimit else {
            throw ChangeFeedError.invalidGzipHeader
        }

        let deflated = Data(bytes[offset..<tailLimit])
        do {
            return try (deflated as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw ChangeFeedError.decompressionFailed
        }
    }

    static func decode(json: Data) throws -> [WikiChange] {
        guard let top = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let changesArray = top["changes"] as? [[Any]] else {
            throw ChangeFeedError.invalidJSON
        }

        var changes: [WikiChange] = []
        changes.reserveCapacity(changesArray.count)

        for row in changesArray {
            guard row.count >= 5 else { continue }

            let ts: Int
            if let n = row[0] as? Int {
                ts = n
            } else if let num = row[0] as? NSNumber {
                ts = num.intValue
            } else {
                continue
            }

            guard let kind = row[1] as? String,
                  let sectionId = row[2] as? String,
                  let rawName = row[3] as? String,
                  let url = row[4] as? String else {
                continue
            }

            let detail = (row.count > 5 ? (row[5] as? String) : nil) ?? ""
            let commit = (row.count > 6 ? (row[6] as? String) : nil) ?? ""

            let cleanName = cleanInvisibleCharacters(rawName)

            changes.append(WikiChange(
                ts: ts,
                kind: kind,
                sectionId: sectionId,
                name: cleanName,
                url: url,
                detail: detail,
                commit: commit
            ))
        }

        return changes.sorted { $0.ts > $1.ts }
    }

    static func decode(gzip: Data) throws -> [WikiChange] {
        let json = try gunzip(gzip)
        return try decode(json: json)
    }
}

@MainActor final class ChangesStore: ObservableObject {
    @Published private(set) var changes: [WikiChange] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastFetched: Date?
    @Published var lastSeenTs: Int
    @Published private(set) var recentAddedURLs: Set<String> = []

    private let lastSeenKey = "changes.lastSeen.v1"
    private let userDefaults: UserDefaults

    private static var cacheFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("changes.json")
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: lastSeenKey) != nil {
            self.lastSeenTs = userDefaults.integer(forKey: lastSeenKey)
        } else {
            self.lastSeenTs = 0
        }
    }

    static func normalizeURL(_ urlString: String) -> String {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }

    private func recomputeRecentAddedURLs() {
        let cutoff = Int(Date().timeIntervalSince1970) - (7 * 24 * 3600)
        var urls = Set<String>()
        for change in changes where change.kind == "added" && change.ts >= cutoff {
            let norm = Self.normalizeURL(change.url)
            if !norm.isEmpty {
                urls.insert(norm)
            }
        }
        self.recentAddedURLs = urls
    }

    func isRecentlyAdded(url: String) -> Bool {
        let norm = Self.normalizeURL(url)
        guard !norm.isEmpty else { return false }
        return recentAddedURLs.contains(norm)
    }

    func markSeen() {
        if let newest = changes.first?.ts {
            lastSeenTs = newest
            userDefaults.set(newest, forKey: lastSeenKey)
        }
    }

    func newCount(followed: Set<String>?) -> Int {
        let filterFollowed = (followed != nil && !followed!.isEmpty)
        return changes.filter { change in
            guard change.ts > lastSeenTs else { return false }
            guard change.kind == "added" || change.kind == "starred" else { return false }
            if filterFollowed {
                return followed!.contains(change.sectionId)
            }
            return true
        }.count
    }

    func setChangesForTesting(_ newChanges: [WikiChange]) {
        applyChanges(newChanges)
    }

    private func applyChanges(_ newChanges: [WikiChange]) {
        self.changes = newChanges
        recomputeRecentAddedURLs()
        if userDefaults.object(forKey: lastSeenKey) == nil {
            if let newest = newChanges.first?.ts {
                self.lastSeenTs = newest
                userDefaults.set(newest, forKey: lastSeenKey)
            }
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let fileURL = Self.cacheFileURL
        var cacheAge: TimeInterval?

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let mod = attrs[.modificationDate] as? Date {
                cacheAge = Date().timeIntervalSince(mod)
                self.lastFetched = mod
            }
            if let data = try? Data(contentsOf: fileURL) {
                let cached = try? await Task.detached {
                    try ChangeFeedDecoder.decode(json: data)
                }.value
                if let cached = cached, !cached.isEmpty {
                    self.applyChanges(cached)
                }
            }
        }

        let sixHours: TimeInterval = 6 * 3600
        let isStaleOrMissing = (cacheAge == nil || cacheAge! > sixHours)
        if isStaleOrMissing {
            await refresh()
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let feedURL = URL(string: "https://omeg4-dev.github.io/fmhy-android/history/changes.json.gz")!
        do {
            let (data, response) = try await URLSession.shared.data(from: feedURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }

            let (gunzipped, decoded) = try await Task.detached {
                let uncompressed = try ChangeFeedDecoder.gunzip(data)
                let parsed = try ChangeFeedDecoder.decode(json: uncompressed)
                return (uncompressed, parsed)
            }.value

            self.applyChanges(decoded)
            self.lastFetched = Date()
            self.errorMessage = nil

            let fileURL = Self.cacheFileURL
            let parent = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try? gunzipped.write(to: fileURL, options: .atomic)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

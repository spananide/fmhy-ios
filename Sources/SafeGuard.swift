import Foundation

enum SafetyStatus: Sendable {
    case fmhySite
    case starred
    case listed
    case domainListed
    case potentiallyUnsafe
    case unsafe
    case searchEngine
    case noData
    case invalid
}

struct Verdict: Sendable {
    var status: SafetyStatus
    var input: String
    var normalizedUrl: String?
    var host: String?
    var reason: String?
    var matches: [Entry]
    var lookalikes: [Entry]
}

final class SafeGuard: @unchecked Sendable {
    private struct EntryMatch {
        let entry: Entry
        let matchedUrl: String
    }

    private let entries: [Entry]
    private let hostToMatches: [String: [EntryMatch]]
    private let unsafeKeys: Set<String>
    private let unsafeReasons: [String: String]
    private let fmhyKeys: Set<String>

    static let subdomainHostingHosts: Set<String> = ["neocities.org"]

    static let sharedResourceHosts: Set<String> = [
        "github.com",
        "gist.github.com",
        "raw.githubusercontent.com",
        "greasyfork.org",
        "youtube.com",
        "chromewebstore.google.com",
        "colab.research.google.com",
        "modrinth.com",
        "f-droid.org",
        "xdaforums.com",
        "start.me",
        "sites.google.com",
        "matrix.to",
        "codepen.io",
        "vk.com",
        "gitlab.com",
        "codeberg.org",
        "sourceforge.net",
        "linktr.ee",
        "rentry.co",
        "rentry.org",
        "pastebin.com",
        "archive.org",
        "drive.google.com",
        "docs.google.com",
        "discord.com",
        "discord.gg",
        "t.me",
        "mega.nz",
        "mediafire.com",
        "gofile.io",
        "pixeldrain.com",
        "huggingface.co"
    ]

    static let searchEngines: [String] = [
        "google.com",
        "bing.com",
        "duckduckgo.com",
        "kagi.com",
        "librey.org",
        "4get.ca",
        "mojeek.com",
        "qwant.com",
        "swisscows.com",
        "yacy.net",
        "startpage.com",
        "search.brave.com",
        "ekoru.org",
        "gibiru.com",
        "searx.org",
        "searx.",
        "searxng.",
        "whoogle.",
        "metager.org",
        "ecosia.org",
        "yandex.com",
        "yandex.",
        "yahoo.com",
        "yahoo.",
        "baidu.com",
        "naver.com",
        "seznam.cz"
    ]

    init(entries: [Entry], unsafeDomains: String, unsafeReasonsJSON: String, fmhySitesList: String) {
        self.entries = entries

        var map: [String: [EntryMatch]] = [:]
        for entry in entries {
            var urls = [entry.url]
            urls.append(contentsOf: entry.mirrors.map { $0.url })
            urls.append(contentsOf: entry.extraLinks.map { $0.url })

            for u in urls {
                if let h = Self.extractHostFromUrl(u) {
                    map[h, default: []].append(EntryMatch(entry: entry, matchedUrl: u))
                }
            }
        }
        self.hostToMatches = map

        var uSet = Set<String>()
        for line in unsafeDomains.components(separatedBy: .newlines) {
            if let k = Self.normalizeListKey(line) {
                uSet.insert(k)
            }
        }
        self.unsafeKeys = uSet

        var reasons: [String: String] = [:]
        if let data = unsafeReasonsJSON.data(using: .utf8),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
            for (k, v) in dict {
                let normK = Self.normalizeListKey(k) ?? k.lowercased().removePrefix("www.")
                reasons[normK] = v
            }
        }
        self.unsafeReasons = reasons

        var fSet = Set<String>()
        for line in fmhySitesList.components(separatedBy: .newlines) {
            if let k = Self.normalizeListKey(line) {
                fSet.insert(k)
            }
        }
        self.fmhyKeys = fSet
    }

    func check(_ input: String) -> Verdict {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Verdict(status: .invalid, input: input, normalizedUrl: nil, host: nil, reason: nil, matches: [], lookalikes: [])
        }

        let urlWithScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let rawHost: String
        if let comps = URLComponents(string: urlWithScheme), let h = comps.host {
            rawHost = h
        } else if let url = URL(string: urlWithScheme), let h = url.host {
            rawHost = h
        } else {
            let u = urlWithScheme
            if let range = u.range(of: "://") {
                let rest = u[range.upperBound...]
                let h = rest.prefix(while: { $0 != "/" && $0 != ":" && $0 != "?" && $0 != "#" })
                rawHost = String(h)
            } else {
                rawHost = ""
            }
        }

        let cleanRawHost = rawHost.trimmingCharacters(in: .whitespaces)
        if cleanRawHost.isEmpty || cleanRawHost.contains(" ") || cleanRawHost.contains("%") {
            return Verdict(status: .invalid, input: input, normalizedUrl: nil, host: nil, reason: nil, matches: [], lookalikes: [])
        }

        if !cleanRawHost.contains(".") && cleanRawHost.caseInsensitiveCompare("localhost") != .orderedSame {
            return Verdict(status: .invalid, input: input, normalizedUrl: nil, host: nil, reason: nil, matches: [], lookalikes: [])
        }

        let host = cleanRawHost.lowercased().removePrefix("www.")
        guard let normalizedUrl = Self.normalizeUrl(urlWithScheme) else {
            return Verdict(status: .invalid, input: input, normalizedUrl: nil, host: nil, reason: nil, matches: [], lookalikes: [])
        }

        // 1. Search engine check
        if Self.isSearchEngine(host) {
            return Verdict(status: .searchEngine, input: input, normalizedUrl: normalizedUrl, host: host, reason: nil, matches: [], lookalikes: [])
        }

        let path: String
        if let comps = URLComponents(string: urlWithScheme) {
            path = comps.path.lowercased().trimmingTrailingSlash()
        } else if let range = urlWithScheme.range(of: "://") {
            let rest = urlWithScheme[range.upperBound...]
            if let slash = rest.firstIndex(of: "/") {
                path = String(rest[slash...]).lowercased().trimmingTrailingSlash()
            } else {
                path = ""
            }
        } else {
            path = ""
        }

        // 2. Prepare candidate keys
        var candidateKeys: [String] = []
        if !path.isEmpty {
            let segments = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            if !segments.isEmpty {
                for i in stride(from: segments.count, through: 1, by: -1) {
                    let subPath = segments.prefix(i).joined(separator: "/")
                    candidateKeys.append("\(host)/\(subPath)")
                }
            }
        }
        candidateKeys.append(host)

        if !Self.isSharedResourceHost(host) {
            let labels = host.split(separator: ".").map(String.init)
            if labels.count > 2 {
                for i in 1..<(labels.count - 1) {
                    let parentHost = labels.dropFirst(i).joined(separator: ".")
                    if Self.subdomainHostingHosts.contains(parentHost) { break }
                    candidateKeys.append(parentHost)
                }
            }
        }

        // Distinct candidate keys preserving order
        var seenKeys = Set<String>()
        let distinctKeys = candidateKeys.filter { seenKeys.insert($0).inserted }

        // Find candidate matches in entries
        var candidateHosts = [host]
        if !Self.isSharedResourceHost(host) {
            let labels = host.split(separator: ".").map(String.init)
            if labels.count > 2 {
                for i in 1..<(labels.count - 1) {
                    let parentHost = labels.dropFirst(i).joined(separator: ".")
                    if Self.subdomainHostingHosts.contains(parentHost) { break }
                    candidateHosts.append(parentHost)
                }
            }
        }
        var seenHosts = Set<String>()
        let distinctHosts = candidateHosts.filter { seenHosts.insert($0).inserted }

        var allHostMatches: [EntryMatch] = []
        var seenMatchKeys = Set<String>()
        for h in distinctHosts {
            if let rows = hostToMatches[h] {
                for m in rows {
                    let k = "\(m.entry.id):\(m.matchedUrl)"
                    if seenMatchKeys.insert(k).inserted {
                        allHostMatches.append(m)
                    }
                }
            }
        }

        let exactMatches = allHostMatches.filter {
            Self.urlMatchesListedResource(currentUrl: urlWithScheme, listedUrl: $0.matchedUrl)
        }.sorted {
            if $0.entry.tier != $1.entry.tier {
                return $0.entry.tier > $1.entry.tier
            }
            return $0.entry.ord < $1.entry.ord
        }

        var seenExactEntryIds = Set<String>()
        let exactMatchingEntries = exactMatches.map { $0.entry }.filter { seenExactEntryIds.insert($0.id).inserted }

        // A. Unsafe from unsafeKeys
        if let matchingKey = distinctKeys.first(where: { unsafeKeys.contains($0) }) {
            let rawReason = unsafeReasons[matchingKey] ?? unsafeReasons[host] ?? unsafeReasons[normalizedUrl]
            let reason = Self.readableReason(rawReason)
            return Verdict(status: .unsafe, input: input, normalizedUrl: normalizedUrl, host: host, reason: reason, matches: exactMatchingEntries, lookalikes: [])
        }

        // B. FMHY from fmhyKeys
        if distinctKeys.contains(where: { fmhyKeys.contains($0) }) {
            return Verdict(status: .fmhySite, input: input, normalizedUrl: normalizedUrl, host: host, reason: nil, matches: exactMatchingEntries, lookalikes: [])
        }

        // C. Starred / Listed exact match from entries
        if !exactMatches.isEmpty {
            let isStarred = exactMatches.contains { $0.entry.tier >= 1 }
            let status: SafetyStatus = isStarred ? .starred : .listed
            return Verdict(status: status, input: input, normalizedUrl: normalizedUrl, host: host, reason: nil, matches: exactMatchingEntries, lookalikes: [])
        }

        // D. DOMAIN_LISTED
        let isShared = Self.isSharedResourceHost(host)
        if !isShared && !allHostMatches.isEmpty {
            var seenDomainIds = Set<String>()
            let domainEntries = allHostMatches.map { $0.entry }
                .filter { seenDomainIds.insert($0.id).inserted }
                .sorted {
                    if $0.tier != $1.tier {
                        return $0.tier > $1.tier
                    }
                    return $0.ord < $1.ord
                }
            let lookalikes = findLookalikes(host)
            return Verdict(status: .domainListed, input: input, normalizedUrl: normalizedUrl, host: host, reason: nil, matches: domainEntries, lookalikes: lookalikes)
        }

        // E. Fallback unsafeReason
        if let rawReason = unsafeReasons[host] ?? unsafeReasons[normalizedUrl] {
            let reason = Self.readableReason(rawReason)
            return Verdict(status: .unsafe, input: input, normalizedUrl: normalizedUrl, host: host, reason: reason, matches: [], lookalikes: [])
        }

        // F. No data
        let lookalikes = findLookalikes(host)
        return Verdict(status: .noData, input: input, normalizedUrl: normalizedUrl, host: host, reason: nil, matches: [], lookalikes: lookalikes)
    }

    private func findLookalikes(_ host: String) -> [Entry] {
        if Self.isSharedResourceHost(host) || Self.subdomainHostingHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return []
        }
        let targetLabel = Self.extractMainLabel(host)
        if targetLabel.count < 4 { return [] }

        struct RankedLookalike {
            let entry: Entry
            let score: Int
        }

        var ranked: [RankedLookalike] = []
        var seenIds = Set<String>()
        let cleanHost = host.lowercased().removePrefix("www.")

        for entry in entries {
            guard let cHost = Self.extractHostFromUrl(entry.url) else { continue }
            if cHost == cleanHost { continue }
            if Self.isSharedResourceHost(cHost) || Self.subdomainHostingHosts.contains(where: { cHost == $0 || cHost.hasSuffix(".\($0)") }) {
                continue
            }

            let candidateLabel = Self.extractMainLabel(cHost)
            if candidateLabel.count < 4 { continue }

            let score: Int
            if candidateLabel == targetLabel {
                score = 0
            } else if candidateLabel.contains(targetLabel) || targetLabel.contains(candidateLabel) {
                score = 1
            } else if targetLabel.count >= 6 && candidateLabel.count >= 6 {
                let dist = Self.levenshtein(targetLabel, candidateLabel)
                score = dist <= 2 ? 2 : -1
            } else {
                score = -1
            }

            if score >= 0 && seenIds.insert(entry.id).inserted {
                ranked.append(RankedLookalike(entry: entry, score: score))
            }
        }

        ranked.sort {
            if $0.score != $1.score {
                return $0.score < $1.score
            }
            if $0.entry.tier != $1.entry.tier {
                return $0.entry.tier > $1.entry.tier
            }
            return $0.entry.ord < $1.entry.ord
        }

        return Array(ranked.prefix(3).map { $0.entry })
    }

    static func isSearchEngine(_ hostname: String) -> Bool {
        let domain = hostname.lowercased().removePrefix("www.")
        return searchEngines.contains { se in
            if se.hasSuffix(".") {
                return domain.hasPrefix(se) || domain.contains(".\(se)") || domain == String(se.dropLast())
            } else {
                return domain == se || domain.hasSuffix(".\(se)")
            }
        }
    }

    static func isSharedResourceHost(_ hostname: String) -> Bool {
        let domain = hostname.lowercased().removePrefix("www.")
        return sharedResourceHosts.contains { host in
            domain == host || domain.hasSuffix(".\(host)")
        }
    }

    static func normalizeUrl(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let source = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let comps = URLComponents(string: source), let rawHost = comps.host, !rawHost.isEmpty else {
            return nil
        }
        let scheme = (comps.scheme ?? "https").lowercased()
        let host = rawHost.lowercased().removePrefix("www.")
        let rawPath = comps.path.trimmingTrailingSlash()
        return "\(scheme)://\(host)\(rawPath)"
    }

    static func normalizeResourceUrl(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let source = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let comps = URLComponents(string: source), let rawHost = comps.host, !rawHost.isEmpty else {
            return nil
        }
        let scheme = (comps.scheme ?? "https").lowercased()
        let host = rawHost.lowercased().removePrefix("www.")
        var rawPath = comps.path.trimmingTrailingSlash()
        let path = rawPath.isEmpty ? "/" : rawPath
        let query = comps.query != nil ? "?\(comps.query!)" : ""
        let fragment = comps.fragment != nil ? "#\(comps.fragment!)" : ""
        var full = "\(scheme)://\(host)\(path)\(query)\(fragment)"
        if query.isEmpty && fragment.isEmpty && full.hasSuffix("/") && path != "/" {
            full.removeLast()
        }
        return full
    }

    static func urlMatchesListedResource(currentUrl: String, listedUrl: String) -> Bool {
        guard let curNorm = normalizeResourceUrl(currentUrl),
              let listNorm = normalizeResourceUrl(listedUrl),
              let currentHost = extractHostFromUrl(curNorm),
              let listedHost = extractHostFromUrl(listNorm) else {
            return false
        }

        let sharedHost = isSharedResourceHost(currentHost) || isSharedResourceHost(listedHost)
        let hostMatches: Bool
        if sharedHost || subdomainHostingHosts.contains(listedHost) {
            hostMatches = currentHost == listedHost
        } else {
            hostMatches = currentHost == listedHost || currentHost.hasSuffix(".\(listedHost)")
        }
        if !hostMatches { return false }

        let curComps = URLComponents(string: curNorm)
        let listComps = URLComponents(string: listNorm)

        let currentPath = (curComps?.path ?? "").lowercased().trimmingTrailingSlash()
        let listedPath = (listComps?.path ?? "").lowercased().trimmingTrailingSlash()

        // GreasyFork script match
        if currentHost == "greasyfork.org" && listedHost == "greasyfork.org" {
            let pattern = "^/(?:[^/]+/)?scripts/(\\d+)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let curMatch = regex.firstMatch(in: currentPath, options: [], range: NSRange(location: 0, length: (currentPath as NSString).length)),
               let listMatch = regex.firstMatch(in: listedPath, options: [], range: NSRange(location: 0, length: (listedPath as NSString).length)),
               curMatch.numberOfRanges >= 2, listMatch.numberOfRanges >= 2 {
                let curId = (currentPath as NSString).substring(with: curMatch.range(at: 1))
                let listId = (listedPath as NSString).substring(with: listMatch.range(at: 1))
                if curId == listId {
                    return true
                }
            }
        }

        // Gist platform pages
        if currentHost == "gist.github.com" && listedHost == "gist.github.com" &&
            (currentPath == "/starred" || currentPath == "/discover") && listedPath.isEmpty {
            return true
        }

        let pathMatches: Bool
        if listedPath.isEmpty || listedPath == "/" {
            pathMatches = !sharedHost || currentPath.isEmpty() || currentPath == "/"
        } else {
            pathMatches = currentPath == listedPath || currentPath.hasPrefix("\(listedPath)/")
        }
        if !pathMatches { return false }

        // Query matching for youtube / archive
        if listedHost == "youtube.com" || listedHost == "archive.org" {
            let curQuery = parseQueryParams(curComps?.query)
            let listQuery = parseQueryParams(listComps?.query)
            for (k, v) in listQuery {
                if curQuery[k] != v { return false }
            }
        }

        // Fragment matching for rentry / matrix
        if listedHost == "rentry.co" || listedHost == "rentry.org" || listedHost == "matrix.to" {
            if let listFrag = listComps?.fragment, !listFrag.isEmpty {
                guard let curFrag = curComps?.fragment, curFrag.caseInsensitiveCompare(listFrag) == .orderedSame else {
                    return false
                }
            }
        }

        return true
    }

    private static func parseQueryParams(_ query: String?) -> [String: String] {
        guard let query = query, !query.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for param in query.components(separatedBy: "&") {
            let parts = param.components(separatedBy: "=")
            if parts.count >= 2 {
                result[parts[0]] = parts[1]
            } else if parts.count == 1 {
                result[parts[0]] = ""
            }
        }
        return result
    }

    static func extractHostFromUrl(_ url: String) -> String? {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comps = URLComponents(string: clean.contains("://") ? clean : "https://\(clean)"),
           let h = comps.host, !h.isEmpty {
            return h.lowercased().removePrefix("www.")
        }
        let u = clean.contains("://") ? clean : "https://\(clean)"
        guard let range = u.range(of: "://") else { return nil }
        let rest = u[range.upperBound...]
        let h = rest.prefix(while: { $0 != "/" && $0 != ":" && $0 != "?" && $0 != "#" })
        if h.isEmpty { return nil }
        return String(h).lowercased().removePrefix("www.")
    }

    static func extractMainLabel(_ host: String) -> String {
        let clean = host.lowercased().removePrefix("www.")
        let domainParts = clean.split(separator: ".").map(String.init)
        let mainPart: String
        if domainParts.count >= 2 {
            mainPart = domainParts[domainParts.count - 2]
        } else {
            mainPart = clean
        }
        let tokens = mainPart.components(separatedBy: CharacterSet(charactersIn: "-_")).filter { !$0.isEmpty }
        return tokens.max(by: { $0.count < $1.count }) ?? mainPart
    }

    static func normalizeListKey(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("#") { return nil }
        var clean = trimmed
        if let range = clean.range(of: "://") {
            clean = String(clean[range.upperBound...])
        }
        if let hashIdx = clean.firstIndex(of: "#") {
            clean = String(clean[..<hashIdx])
        }
        if let qIdx = clean.firstIndex(of: "?") {
            clean = String(clean[..<qIdx])
        }
        while clean.hasSuffix("/") {
            clean.removeLast()
        }
        if clean.isEmpty { return nil }

        let slashIdx = clean.firstIndex(of: "/")
        let hostPart = slashIdx != nil ? String(clean[..<slashIdx!]) : clean
        let pathPart = slashIdx != nil ? String(clean[slashIdx!...]) : ""

        let normalizedHost = hostPart.lowercased().removePrefix("www.")
        if normalizedHost.isEmpty { return nil }
        var normalizedPath = pathPart.lowercased()
        while normalizedPath.hasSuffix("/") {
            normalizedPath.removeLast()
        }
        return normalizedPath.isEmpty ? normalizedHost : "\(normalizedHost)\(normalizedPath)"
    }

    static func readableReason(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        var text = raw

        if let linkRegex = try? NSRegularExpression(pattern: "\\[([^\\]]*)\\]\\([^)]*\\)", options: []) {
            let ns = text as NSString
            text = linkRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
        }

        if let parenRegex = try? NSRegularExpression(pattern: "\\(\\s*https?://\\S*\\s*\\)", options: []) {
            let ns = text as NSString
            text = parenRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }

        if let sepUrlRegex = try? NSRegularExpression(pattern: "(?:[ \\t]*(?:-{1,2}|–|—|:)[ \\t]+)?https?://\\S+", options: []) {
            let ns = text as NSString
            text = sepUrlRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }

        if let sepWwwRegex = try? NSRegularExpression(pattern: "(?:[ \\t]*(?:-{1,2}|–|—|:)[ \\t]+)?(?<!\\S)www\\.\\S+", options: []) {
            let ns = text as NSString
            text = sepWwwRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }

        if let trailRegex = try? NSRegularExpression(pattern: "[ \\t]*(?:[-–—:/]|\\s)+$", options: []) {
            let ns = text as NSString
            text = trailRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }

        if let leadRegex = try? NSRegularExpression(pattern: "^(?:[-–—:/]|\\s)+", options: []) {
            let ns = text as NSString
            text = leadRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }

        let parts = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        text = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func levenshtein(_ s1: String, _ s2: String) -> Int {
        if s1 == s2 { return 0 }
        let a = Array(s1.unicodeScalars)
        let b = Array(s2.unicodeScalars)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var prev = Array(0...b.count)
        var curr = Array(repeating: 0, count: b.count + 1)

        for i in 0..<a.count {
            curr[0] = i + 1
            for j in 0..<b.count {
                let cost = a[i] == b[j] ? 0 : 1
                curr[j + 1] = min(
                    curr[j] + 1,
                    prev[j + 1] + 1,
                    prev[j] + cost
                )
            }
            prev = curr
        }
        return prev[b.count]
    }
}

private extension String {
    func removePrefix(_ prefix: String) -> String {
        if self.hasPrefix(prefix) {
            return String(self.dropFirst(prefix.count))
        }
        return self
    }

    func trimmingTrailingSlash() -> String {
        var s = self
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }
}

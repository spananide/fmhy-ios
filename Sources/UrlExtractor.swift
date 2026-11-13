import Foundation

// MARK: - SafetyStatus Codable

extension SafetyStatus: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        switch str {
        case "fmhySite", "FMHY_SITE": self = .fmhySite
        case "starred", "STARRED": self = .starred
        case "listed", "LISTED": self = .listed
        case "domainListed", "DOMAIN_LISTED": self = .domainListed
        case "potentiallyUnsafe", "POTENTIALLY_UNSAFE": self = .potentiallyUnsafe
        case "unsafe", "UNSAFE": self = .unsafe
        case "searchEngine", "SEARCH_ENGINE": self = .searchEngine
        case "noData", "NO_DATA": self = .noData
        default: self = .invalid
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(describing: self))
    }
}

// MARK: - RecentCheck

struct RecentCheck: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(url)_\(ts.timeIntervalSince1970)" }
    var url: String
    var status: SafetyStatus
    var ts: Date

    init(url: String, status: SafetyStatus, ts: Date = Date()) {
        self.url = url
        self.status = status
        self.ts = ts
    }

    enum CodingKeys: String, CodingKey {
        case url, status, ts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.status = try container.decode(SafetyStatus.self, forKey: .status)
        if let d = try? container.decode(Double.self, forKey: .ts) {
            if d > 100_000_000_000 {
                self.ts = Date(timeIntervalSince1970: d / 1000.0)
            } else if d > 1_000_000_000 {
                self.ts = Date(timeIntervalSince1970: d)
            } else {
                self.ts = Date(timeIntervalSinceReferenceDate: d)
            }
        } else if let date = try? container.decode(Date.self, forKey: .ts) {
            self.ts = date
        } else {
            self.ts = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(status, forKey: .status)
        try container.encode(Int64(ts.timeIntervalSince1970 * 1000), forKey: .ts)
    }
}

// MARK: - UrlExtractor & CheckLogic

enum UrlExtractor {
    private static let webUrlFallbackPattern = #"https?://[^\s<>"{}|\\^`]+|(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(?::\d{1,5})?(?:/[^\s<>"{}|\\^`]*)?"#

    nonisolated static func looksLikeUrl(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains(" ") || trimmed.contains("\t") || trimmed.contains("\n") {
            return false
        }
        let hasScheme = trimmed.contains("://")
        let hasDot = trimmed.contains(".")
        let lower = trimmed.lowercased()
        let isLocalhost = lower == "localhost" ||
            lower.hasPrefix("localhost:") ||
            lower.hasPrefix("localhost/")

        if !hasScheme && !hasDot && !isLocalhost {
            return false
        }

        let urlWithScheme = hasScheme ? trimmed : "https://\(trimmed)"
        let host: String?
        if let comps = URLComponents(string: urlWithScheme), let h = comps.host {
            host = h.trimmingCharacters(in: .whitespaces)
        } else if let u = URL(string: urlWithScheme), let h = u.host {
            host = h.trimmingCharacters(in: .whitespaces)
        } else {
            host = nil
        }

        guard let h = host, !h.isEmpty, !h.contains(" "), !h.contains("%") else {
            return false
        }
        return h.contains(".") || h.caseInsensitiveCompare("localhost") == .orderedSame
    }

    nonisolated static func extractFirstUrl(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        if let regex = try? NSRegularExpression(pattern: webUrlFallbackPattern, options: []) {
            let ns = trimmed as NSString
            let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length))
            if let range = match?.range {
                let matchedString = ns.substring(with: range)
                return trimTrailingPunctuation(matchedString)
            }
        }
        return trimmed
    }

    nonisolated static func extractHost(from text: String) -> String? {
        let extracted = extractFirstUrl(text)
        guard looksLikeUrl(extracted) else { return nil }
        guard let norm = SafeGuard.normalizeUrl(extracted) else { return nil }
        guard let host = SafeGuard.extractHostFromUrl(norm), !host.isEmpty else { return nil }
        return host
    }

    nonisolated static func urlHasPath(_ urlString: String) -> Bool {
        let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlWithScheme = clean.contains("://") ? clean : "https://\(clean)"
        if let comps = URLComponents(string: urlWithScheme) {
            let p = comps.path
            return !p.isEmpty && p != "/"
        }
        if let url = URL(string: urlWithScheme) {
            let p = url.path
            return !p.isEmpty && p != "/"
        }
        return false
    }

    nonisolated static func hostForCheckJustHost(verdict: Verdict) -> String? {
        guard let host = verdict.host, !host.isEmpty else { return nil }
        guard verdict.status == .noData || verdict.status == .domainListed else { return nil }
        let targetUrl = verdict.normalizedUrl ?? verdict.input
        guard urlHasPath(targetUrl) else { return nil }
        return host
    }

    nonisolated static func pruneRecentChecks(_ items: [RecentCheck]) -> [RecentCheck] {
        func key(_ r: RecentCheck) -> String {
            r.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        var kept: [RecentCheck] = []
        for (index, item) in items.enumerated() {
            let k = key(item)
            let shadowed = items.enumerated().contains { (otherIndex, other) in
                guard otherIndex != index else { return false }
                guard other.ts >= item.ts else { return false }
                let o = key(other)
                if o.count > k.count && o.hasPrefix(k) {
                    return true
                }
                if o == k {
                    return other.ts > item.ts || otherIndex < index
                }
                return false
            }
            if !shadowed {
                kept.append(item)
            }
        }
        return kept
    }

    nonisolated static func matchBreadcrumb(sectionTitle: String?, headingPath: String) -> [String] {
        var parts = headingPath.split(separator: ">")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let section = (sectionTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if section.isEmpty { return parts }
        if let first = parts.first, first.caseInsensitiveCompare(section) == .orderedSame {
            parts.removeFirst()
        }
        return [section] + parts
    }

    private nonisolated static func trimTrailingPunctuation(_ s: String) -> String {
        var res = s
        let punctuation: Set<Character> = [".", ",", ";", "!", "?", ")"]
        while let last = res.last, punctuation.contains(last) {
            res.removeLast()
        }
        return res
    }
}

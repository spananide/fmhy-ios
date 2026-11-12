import Foundation

struct SearchResult: Identifiable, Sendable {
    var entry: Entry
    var score: Double
    var id: String { entry.id }
}

final class SearchIndex: @unchecked Sendable {
    private final class IndexedEntry {
        let entry: Entry
        let normName: String
        let nameWords: [String]
        let nameScalars: [UnicodeScalar]
        let nameWordScalars: [[UnicodeScalar]]
        let normHost: String
        let normDesc: String
        let normTags: [String]
        let normHeadingPath: String
        let normCombined: String

        init(entry: Entry) {
            self.entry = entry
            let nName = SearchIndex.normalize(entry.name)
            self.normName = nName
            self.nameScalars = Array(nName.unicodeScalars)

            let words = nName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            self.nameWords = words
            self.nameWordScalars = words.map { Array($0.unicodeScalars) }

            let host: String
            if let comps = URLComponents(string: entry.url), let h = comps.host {
                let lower = h.lowercased()
                host = lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
            } else {
                let u = entry.url
                if let range = u.range(of: "://") {
                    let rest = u[range.upperBound...]
                    let h = rest.prefix(while: { $0 != "/" && $0 != ":" && $0 != "?" && $0 != "#" })
                    let s = String(h).lowercased()
                    host = s.hasPrefix("www.") ? String(s.dropFirst(4)) : s
                } else {
                    host = ""
                }
            }
            self.normHost = SearchIndex.normalize(host)
            self.normDesc = SearchIndex.normalize(entry.description)
            self.normTags = entry.tags.map { SearchIndex.normalize($0) }
            self.normHeadingPath = SearchIndex.normalize(entry.headingPath)

            var combined = nName + " " + self.normHost + " " + self.normDesc + " " + self.normHeadingPath
            for t in self.normTags {
                combined += " " + t
            }
            self.normCombined = combined
        }
    }

    private struct ParsedQuery {
        var words: [String] = []
        var phrases: [String] = []
        var excludes: [String] = []
        var inSections: [String] = []
        var isStarred: Bool = false
        var isTop: Bool = false
        var isB64: Bool = false
        var site: String? = nil

        var hasFreeText: Bool {
            !words.isEmpty || !phrases.isEmpty
        }

        var isEmpty: Bool {
            words.isEmpty && phrases.isEmpty && excludes.isEmpty && inSections.isEmpty && !isStarred && !isTop && !isB64 && site == nil
        }
    }

    private let indexedEntries: [IndexedEntry]
    private let sections: [WikiSection]

    init(entries: [Entry], sections: [WikiSection]) {
        self.sections = sections
        self.indexedEntries = entries.map { IndexedEntry(entry: $0) }
    }

    func search(_ query: String, limit: Int = 100) -> [SearchResult] {
        let q = parseQuery(query)
        if q.isEmpty {
            return []
        }

        // Resolve section filter if any
        let allowedSectionIds: Set<String>?
        if !q.inSections.isEmpty {
            var matchedIds = Set<String>()
            for pattern in q.inSections {
                let p = pattern.lowercased()
                for s in sections {
                    if s.id.lowercased().hasPrefix(p) || s.title.lowercased().hasPrefix(p) || s.id.lowercased().contains(p) {
                        matchedIds.insert(s.id)
                    }
                }
            }
            if matchedIds.isEmpty {
                return []
            }
            allowedSectionIds = matchedIds
        } else {
            allowedSectionIds = nil
        }

        let siteFilter = q.site?.lowercased().removePrefix("www.")
        let normalizedExcludes = q.excludes.map { Self.normalize($0) }
        let normalizedPhrases = q.phrases.map { Self.normalize($0) }
        let normalizedWords = q.words.map { w -> (word: String, scalars: [UnicodeScalar], maxDist: Int) in
            let nw = Self.normalize(w)
            let sc = Array(nw.unicodeScalars)
            let maxDist = nw.count >= 8 ? 2 : (nw.count >= 4 ? 1 : 0)
            return (nw, sc, maxDist)
        }

        var results: [SearchResult] = []

        for item in indexedEntries {
            let entry = item.entry

            // Section filter
            if let allowed = allowedSectionIds, !allowed.contains(entry.sectionId) {
                continue
            }

            // Flag filters
            if q.isStarred && entry.tier < 1 {
                continue
            }
            if q.isTop && entry.tier != 2 {
                continue
            }
            if q.isB64 && !entry.isBase64 {
                continue
            }

            // Site filter
            if let site = siteFilter {
                if !item.normHost.contains(site) && !entry.url.lowercased().contains(site) {
                    continue
                }
            }

            // Excludes
            var excluded = false
            for ex in normalizedExcludes {
                if item.normCombined.contains(ex) {
                    excluded = true
                    break
                }
            }
            if excluded { continue }

            // Phrases
            var phrasesMatched = true
            for phr in normalizedPhrases {
                if !item.normCombined.contains(phr) {
                    phrasesMatched = false
                    break
                }
            }
            if !phrasesMatched { continue }

            if !q.hasFreeText {
                // Only filters: score by tier desc, then ord asc
                let score = Double(entry.tier * 100000 - entry.ord)
                results.append(SearchResult(entry: entry, score: score))
                continue
            }

            // Free text matching
            var entryScore: Double = 0
            if entry.tier == 2 {
                entryScore += 20.0
            } else if entry.tier == 1 {
                entryScore += 10.0
            }

            for _ in normalizedPhrases {
                entryScore += 30.0
            }

            var allWordsMatched = true
            for (w, wScalars, maxDist) in normalizedWords {
                var matched = false
                var wordScore: Double = 0

                if item.normName == w {
                    matched = true
                    wordScore = max(wordScore, 100.0)
                } else if item.normName.hasPrefix(w) {
                    matched = true
                    wordScore = max(wordScore, 60.0)
                } else if item.nameWords.contains(w) {
                    matched = true
                    wordScore = max(wordScore, 45.0)
                } else if item.nameWords.contains(where: { $0.hasPrefix(w) }) {
                    matched = true
                    wordScore = max(wordScore, 35.0)
                } else if item.normName.contains(w) {
                    matched = true
                    wordScore = max(wordScore, 25.0)
                } else if item.normHost.contains(w) {
                    matched = true
                    wordScore = max(wordScore, 20.0)
                } else if item.normTags.contains(where: { $0.contains(w) }) {
                    matched = true
                    wordScore = max(wordScore, 15.0)
                } else if item.normDesc.contains(w) {
                    matched = true
                    wordScore = max(wordScore, 10.0)
                } else if item.normHeadingPath.contains(w) {
                    matched = true
                    wordScore = max(wordScore, 5.0)
                }

                if !matched && maxDist > 0 {
                    var bestDist = Int.max
                    for ws in item.nameWordScalars {
                        let d = Self.damerauLevenshtein(wScalars, ws, limit: maxDist)
                        if d <= maxDist && d < bestDist {
                            bestDist = d
                        }
                    }
                    if bestDist > maxDist {
                        let d = Self.damerauLevenshtein(wScalars, item.nameScalars, limit: maxDist)
                        if d <= maxDist && d < bestDist {
                            bestDist = d
                        }
                    }
                    if bestDist <= maxDist {
                        matched = true
                        wordScore = max(wordScore, bestDist == 1 ? 8.0 : 4.0)
                    }
                }

                if !matched {
                    allWordsMatched = false
                    break
                }
                entryScore += wordScore
            }

            if !allWordsMatched {
                continue
            }

            results.append(SearchResult(entry: entry, score: entryScore))
        }

        results.sort {
            if abs($0.score - $1.score) > 0.0001 {
                return $0.score > $1.score
            }
            if $0.entry.tier != $1.entry.tier {
                return $0.entry.tier > $1.entry.tier
            }
            return $0.entry.ord < $1.entry.ord
        }

        if results.count > limit {
            return Array(results.prefix(limit))
        }
        return results
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }

    private func parseQuery(_ raw: String) -> ParsedQuery {
        var query = ParsedQuery()
        let chars = Array(raw)
        let len = chars.count
        var i = 0

        while i < len {
            while i < len && (chars[i] == " " || chars[i] == "\t") {
                i += 1
            }
            if i >= len { break }

            let remaining = String(chars[i...])

            if remaining.hasPrefix("in:\"") {
                i += 4
                let start = i
                while i < len && chars[i] != "\"" { i += 1 }
                let sec = String(chars[start..<i]).trimmingCharacters(in: .whitespaces)
                if i < len && chars[i] == "\"" { i += 1 }
                if !sec.isEmpty { query.inSections.append(sec) }
                continue
            }

            if remaining.hasPrefix("site:\"") {
                i += 6
                let start = i
                while i < len && chars[i] != "\"" { i += 1 }
                let s = String(chars[start..<i]).trimmingCharacters(in: .whitespaces).lowercased().removePrefix("www.")
                if i < len && chars[i] == "\"" { i += 1 }
                if !s.isEmpty { query.site = s }
                continue
            }

            var isExclude = false
            if chars[i] == "-" && i + 1 < len && chars[i + 1] != " " && chars[i + 1] != "\t" {
                isExclude = true
                i += 1
            }

            if i < len && chars[i] == "\"" {
                i += 1
                let start = i
                while i < len && chars[i] != "\"" { i += 1 }
                let phrase = String(chars[start..<i]).trimmingCharacters(in: .whitespaces)
                if i < len && chars[i] == "\"" { i += 1 }
                if !phrase.isEmpty {
                    if isExclude {
                        query.excludes.append(phrase)
                    } else {
                        query.phrases.append(phrase)
                    }
                }
            } else {
                let start = i
                while i < len && chars[i] != " " && chars[i] != "\t" { i += 1 }
                let token = String(chars[start..<i])
                let lowerToken = token.lowercased()

                if isExclude {
                    if !token.isEmpty { query.excludes.append(token) }
                } else if lowerToken.hasPrefix("in:") {
                    let sec = String(token.dropFirst(3)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if !sec.isEmpty { query.inSections.append(sec) }
                } else if lowerToken == "is:starred" {
                    query.isStarred = true
                } else if lowerToken == "is:top" {
                    query.isTop = true
                } else if lowerToken == "is:b64" {
                    query.isB64 = true
                } else if lowerToken.hasPrefix("site:") {
                    let s = String(token.dropFirst(5)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased().removePrefix("www.")
                    if !s.isEmpty { query.site = s }
                } else {
                    if !token.isEmpty { query.words.append(token) }
                }
            }
        }

        return query
    }

    private static func damerauLevenshtein(_ a: [UnicodeScalar], _ b: [UnicodeScalar], limit: Int) -> Int {
        let n = a.count
        let m = b.count
        if abs(n - m) > limit { return limit + 1 }
        if n == 0 { return m }
        if m == 0 { return n }

        var prev2 = Array(0...m)
        var prev = Array(0...m)
        var cur = Array(repeating: 0, count: m + 1)

        for i in 1...n {
            cur[0] = i
            for j in 1...m {
                let cost = (a[i - 1] == b[j - 1]) ? 0 : 1
                var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                    v = min(v, prev2[j - 2] + 1)
                }
                cur[j] = v
            }
            prev2 = prev
            prev = cur
        }
        return prev[m]
    }
}

private extension String {
    func removePrefix(_ prefix: String) -> String {
        if self.hasPrefix(prefix) {
            return String(self.dropFirst(prefix.count))
        }
        return self
    }
}

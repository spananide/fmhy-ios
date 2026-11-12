import Foundation

enum FmhyParser {
    private static let excludedFiles: Set<String> = ["base64.md"]
    private static let socialLabels: Set<String> = [
        "discord", "github", "gitlab", "source code", "telegram",
        "subreddit", "x", "mastodon", "bluesky", ".onion", "status"
    ]

    static func parseSections(headersJSON: Data) -> [WikiSection] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: headersJSON) as? [String: Any],
              let rawString = String(data: headersJSON, encoding: .utf8) else {
            return []
        }

        var orderedKeys: [String] = []
        var seenKeys = Set<String>()
        if let regex = try? NSRegularExpression(pattern: "\"([a-zA-Z0-9_-]+\\.md)\"\\s*:", options: []) {
            let nsString = rawString as NSString
            let matches = regex.matches(in: rawString, options: [], range: NSRange(location: 0, length: nsString.length))
            for m in matches {
                guard m.numberOfRanges >= 2 else { continue }
                let keyRange = m.range(at: 1)
                guard keyRange.location != NSNotFound else { continue }
                let key = nsString.substring(with: keyRange)
                if seenKeys.insert(key).inserted {
                    orderedKeys.append(key)
                }
            }
        }

        var sections: [WikiSection] = []
        var ord = 0
        for key in orderedKeys {
            if excludedFiles.contains(key.lowercased()) {
                continue
            }
            guard let dict = jsonObject[key] as? [String: Any] else {
                continue
            }
            let title = (dict["title"] as? String) ?? ""
            let description = (dict["description"] as? String) ?? ""
            let id = key.hasSuffix(".md") ? String(key.dropLast(3)) : key
            sections.append(WikiSection(id: id, title: title, description: description, ord: ord))
            ord += 1
        }
        return sections
    }

    static func parseSection(_ section: WikiSection, markdown: String, b64: Base64Map) -> ParsedSection {
        let lines = markdown.components(separatedBy: .newlines).map { stripInvisibleChars($0) }
        var headings: [Heading] = []
        var entries: [Entry] = []
        var notes: [Note] = []
        var unparsedLines = 0

        var inFence = false
        var ordCounter = 0
        var headingOrd = 0

        let anchorTracker = AnchorTracker()
        var headingStack: [Heading] = []
        var noteCounts: [String: Int] = [:]
        let idAssigner = IdAssigner()

        func currentHeading() -> Heading? {
            headingStack.last
        }

        func currentHeadingPath() -> String {
            var parts = [section.title]
            for h in headingStack {
                parts.append(h.title)
            }
            return parts.joined(separator: " › ")
        }

        func pushHeading(_ h: Heading) {
            while let last = headingStack.last, last.level >= h.level {
                headingStack.removeLast()
            }
            headingStack.append(h)
        }

        var i = 0
        if let firstLine = lines.first, isFrontMatter(firstLine) {
            i = 1
            while i < lines.count {
                if isFrontMatter(lines[i]) {
                    i += 1
                    break
                }
                i += 1
            }
        }

        while i < lines.count {
            let line = lines[i]
            let lineNumber = i + 1
            i += 1

            if line.hasPrefix(":::") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
            if trimmedLeading.hasPrefix("<") { continue }

            if trimmedLeading == "***" || trimmedLeading == "---" { continue }

            if line.range(of: "back to wiki index", options: .caseInsensitive) != nil { continue }

            if isBackToTop(trimmedLeading) { continue }

            if let headingMatch = matchHeading(line) {
                let level = headingMatch.level
                let rawTitle = headingMatch.title.trimmingCharacters(in: .whitespaces)
                let displayTitle = rawTitle.replacingOccurrences(of: "►", with: "").replacingOccurrences(of: "▷", with: "").trimmingCharacters(in: .whitespaces)
                let anchor = Slug.slugify(rawTitle)
                let uniqueAnchor = anchorTracker.add(anchor)
                let parent = headingStack.last(where: { $0.level < level })

                let h = Heading(
                    id: "\(section.id)/\(uniqueAnchor)",
                    sectionId: section.id,
                    parentId: parent?.id,
                    level: level,
                    title: displayTitle,
                    anchor: uniqueAnchor,
                    ord: headingOrd
                )
                headingOrd += 1
                pushHeading(h)
                headings.append(h)
                continue
            }

            if let bqText = matchBlockquote(line) {
                let text = bqText.trimmingCharacters(in: .whitespaces)
                let ch = currentHeading()
                let parentKey = ch?.id ?? section.id
                let k = (noteCounts[parentKey] ?? 0) + 1
                noteCounts[parentKey] = k
                let noteId = "\(parentKey)#n\(k)"

                notes.append(
                    Note(
                        id: noteId,
                        sectionId: section.id,
                        headingId: ch?.id,
                        ord: ordCounter,
                        text: text
                    )
                )
                ordCounter += 1
                continue
            }

            if let bulletContent = matchBullet(line) {
                if let noteText = matchNoteMarker(bulletContent) {
                    let ch = currentHeading()
                    let parentKey = ch?.id ?? section.id
                    let k = (noteCounts[parentKey] ?? 0) + 1
                    noteCounts[parentKey] = k
                    let noteId = "\(parentKey)#n\(k)"

                    notes.append(
                        Note(
                            id: noteId,
                            sectionId: section.id,
                            headingId: ch?.id,
                            ord: ordCounter,
                            text: noteText
                        )
                    )
                    ordCounter += 1
                    continue
                }

                guard let parsed = parseBulletLine(
                    bulletContent,
                    sectionId: section.id,
                    headingId: currentHeading()?.id,
                    headingPath: currentHeadingPath(),
                    isInlineMore: false,
                    line: lineNumber
                ), !parsed.isEmpty else {
                    unparsedLines += 1
                    continue
                }

                for p in parsed {
                    let norm = Ids.normalizeUrl(p.url)
                    let eid = idAssigner.assign(normUrl: norm, sectionId: section.id)
                    let (resolvedUrl, originalUrl, allMirrors) = b64.resolve(url: p.url, mirrors: p.mirrors)
                    entries.append(
                        Entry(
                            id: eid,
                            sectionId: section.id,
                            headingId: p.headingId,
                            ord: ordCounter,
                            name: p.name,
                            url: resolvedUrl,
                            originalUrl: originalUrl,
                            description: p.description,
                            tags: p.tags,
                            headingPath: p.headingPath,
                            tier: p.tier,
                            kind: p.kind,
                            isInlineMore: p.isInlineMore,
                            isBase64: originalUrl != nil,
                            mirrors: allMirrors,
                            extraLinks: p.extraLinks
                        )
                    )
                    ordCounter += 1
                }
                continue
            }

            let stripped = line.trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty {
                let links = extractInlineLinks(stripped)
                if !links.isEmpty {
                    if let parsed = parseBulletLine(
                        stripped,
                        sectionId: section.id,
                        headingId: currentHeading()?.id,
                        headingPath: currentHeadingPath(),
                        isInlineMore: true,
                        line: lineNumber
                    ), !parsed.isEmpty {
                        for p in parsed {
                            let norm = Ids.normalizeUrl(p.url)
                            let eid = idAssigner.assign(normUrl: norm, sectionId: section.id)
                            let (resolvedUrl, originalUrl, allMirrors) = b64.resolve(url: p.url, mirrors: p.mirrors)
                            entries.append(
                                Entry(
                                    id: eid,
                                    sectionId: section.id,
                                    headingId: p.headingId,
                                    ord: ordCounter,
                                    name: p.name,
                                    url: resolvedUrl,
                                    originalUrl: originalUrl,
                                    description: p.description,
                                    tags: p.tags,
                                    headingPath: p.headingPath,
                                    tier: p.tier,
                                    kind: p.kind,
                                    isInlineMore: p.isInlineMore,
                                    isBase64: originalUrl != nil,
                                    mirrors: allMirrors,
                                    extraLinks: p.extraLinks
                                )
                            )
                            ordCounter += 1
                        }
                    } else {
                        unparsedLines += 1
                    }
                }
            }
        }

        return ParsedSection(section: section, headings: headings, entries: entries, notes: notes, unparsedLines: unparsedLines)
    }

    private static func isFrontMatter(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }

    private static func isBackToTop(_ s: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^\\[.*\\]\\(#\\S*\\)\\s*$", options: []) else { return false }
        let ns = s as NSString
        return regex.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func matchHeading(_ line: String) -> (level: Int, title: String)? {
        let chars = Array(line)
        var count = 0
        while count < chars.count && chars[count] == "#" {
            count += 1
        }
        if count >= 1 && count <= 4 && count < chars.count && (chars[count] == " " || chars[count] == "\t") {
            var start = count
            while start < chars.count && (chars[start] == " " || chars[start] == "\t") {
                start += 1
            }
            return (count, String(chars[start...]))
        }
        return nil
    }

    private static func matchBlockquote(_ line: String) -> String? {
        if line.hasPrefix(">") {
            let after = line.dropFirst()
            if after.hasPrefix(" ") || after.hasPrefix("\t") {
                return String(after.dropFirst())
            }
            return String(after)
        }
        return nil
    }

    private static func matchBullet(_ line: String) -> String? {
        let chars = Array(line)
        var i = 0
        while i < chars.count && (chars[i] == " " || chars[i] == "\t") {
            i += 1
        }
        guard i < chars.count else { return nil }
        if chars[i] == "*" || chars[i] == "-" {
            i += 1
            guard i < chars.count && (chars[i] == " " || chars[i] == "\t") else { return nil }
            while i < chars.count && (chars[i] == " " || chars[i] == "\t") {
                i += 1
            }
            return String(chars[i...])
        }
        return nil
    }

    private static func matchNoteMarker(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("**Note**") else { return nil }
        let rest = trimmed.dropFirst("**Note**".count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("-") else { return nil }
        let afterDash = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        return afterDash
    }

    private struct PartialEntry {
        var name: String
        var url: String
        var tier: Int
        var kind: Int
        var line: Int
        var isInlineMore: Bool
        var headingId: String?
        var headingPath: String
        var description: String = ""
        var tags: [String] = []
        var mirrors: [Link] = []
        var extraLinks: [Link] = []
    }

    private static func parseBulletLine(
        _ content: String,
        sectionId: String,
        headingId: String?,
        headingPath: String,
        isInlineMore: Bool,
        line: Int
    ) -> [PartialEntry]? {
        let cleaned = stripInvisibleChars(content)
        let (tier, kind, withoutTierAndKind) = detectTierAndKind(cleaned)
        let (head, desc) = splitHeadDesc(withoutTierAndKind)

        let headLinks = extractInlineLinks(head)
        if headLinks.isEmpty {
            let descLinks = extractInlineLinks(desc)
            if descLinks.isEmpty {
                return nil
            }
            let rawName = head.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            let name = stripLeadingEmoji(rawName).trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                return nil
            }
            let firstUrl = descLinks[0].url
            let extraLinks = descLinks.map { Link(label: $0.label, url: $0.url) }
            let (_, nonLinkDesc) = splitHeadDesc(desc)
            let description = !nonLinkDesc.isEmpty ? markdownToPlain(nonLinkDesc).trimmingCharacters(in: .whitespaces) : ""
            let tags = description.isEmpty ? [] : [description]

            return [
                PartialEntry(
                    name: name,
                    url: firstUrl,
                    tier: tier,
                    kind: isInlineMore ? 0 : kind,
                    line: line,
                    isInlineMore: isInlineMore,
                    headingId: headingId,
                    headingPath: headingPath,
                    description: description,
                    tags: tags,
                    mirrors: [],
                    extraLinks: extraLinks
                )
            ]
        }

        let lineKind = isInlineMore ? 0 : kind
        var entryCandidates = parseHeadLinks(
            headText: head,
            tier: tier,
            lineKind: lineKind,
            line: line,
            isInlineMore: isInlineMore,
            headingId: headingId,
            headingPath: headingPath
        )
        if entryCandidates.isEmpty {
            return nil
        }

        let (description, tags, extraLinks) = parseDesc(desc)
        for idx in 0..<entryCandidates.count {
            entryCandidates[idx].description = description
            entryCandidates[idx].tags = tags
            if idx == 0 {
                entryCandidates[idx].extraLinks.append(contentsOf: extraLinks)
            }
        }

        return entryCandidates
    }

    static func detectTierAndKind(_ line: String) -> (tier: Int, kind: Int, rest: String) {
        var tier = 0
        var kind = 0
        var s = line.trimmingCharacters(in: .whitespaces)

        for _ in 0..<2 {
            s = s.trimmingCharacters(in: .whitespaces)
            if tier == 0 {
                if s.hasPrefix("🌟") {
                    tier = 2
                    s = String(s.dropFirst("🌟".count))
                    continue
                } else if s.hasPrefix("⭐") {
                    tier = 1
                    s = String(s.dropFirst("⭐".count))
                    continue
                }
            }
            if kind == 0 {
                if s.hasPrefix("🌐") {
                    kind = 1
                    s = String(s.dropFirst("🌐".count))
                    if s.hasPrefix("\u{FE0F}") {
                        s = String(s.dropFirst())
                    }
                    continue
                } else if s.hasPrefix("↪️") {
                    kind = 2
                    s = String(s.dropFirst("↪️".count))
                    continue
                } else if s.hasPrefix("↪") {
                    kind = 2
                    s = String(s.dropFirst("↪".count))
                    if s.hasPrefix("\u{FE0F}") {
                        s = String(s.dropFirst())
                    }
                    continue
                }
            }
        }
        return (tier, kind, s.trimmingCharacters(in: .whitespaces))
    }

    static func detectTier(_ line: String) -> (tier: Int, rest: String) {
        let (tier, _, rest) = detectTierAndKind(line)
        return (tier, rest)
    }

    static func splitHeadDesc(_ line: String) -> (head: String, desc: String) {
        let chars = Array(line)
        let n = chars.count
        var depth = 0
        var i = 0
        var inLinkUrl = false

        while i < n {
            let ch = chars[i]
            if ch == "[" {
                depth += 1
            } else if ch == "]" {
                depth -= 1
                if depth < 0 { depth = 0 }
                if i + 1 < n && chars[i + 1] == "(" {
                    inLinkUrl = true
                    i += 2
                    while i < n && chars[i] != ")" {
                        i += 1
                    }
                    inLinkUrl = false
                    if i < n {
                        i += 1
                    }
                    continue
                }
            }

            if depth == 0 && !inLinkUrl {
                if i + 3 <= n && chars[i] == " " && chars[i + 1] == "-" && chars[i + 2] == " " {
                    let head = String(chars[0..<i])
                    let desc = String(chars[(i + 3)..<n])
                    return (head, desc)
                }
            }
            i += 1
        }
        return (line, "")
    }

    private static func parseHeadLinks(
        headText: String,
        tier: Int,
        lineKind: Int,
        line: Int,
        isInlineMore: Bool,
        headingId: String?,
        headingPath: String
    ) -> [PartialEntry] {
        var entries: [PartialEntry] = []
        var current: PartialEntry?
        var inBold = false
        var prevTextTail = ""

        func finishEntry() {
            if let c = current {
                entries.append(c)
                current = nil
            }
        }

        func newEntry(name: String, url: String, linkTier: Int, linkKind: Int) {
            finishEntry()
            current = PartialEntry(
                name: stripLeadingEmoji(name).trimmingCharacters(in: .whitespaces),
                url: url,
                tier: linkTier,
                kind: linkKind,
                line: line,
                isInlineMore: isInlineMore,
                headingId: headingId,
                headingPath: headingPath
            )
        }

        let chars = Array(headText)
        let n = chars.count
        var i = 0
        while i < n {
            if i + 1 < n && chars[i] == "*" && chars[i + 1] == "*" {
                inBold.toggle()
                i += 2
                continue
            }

            if let link = scanLinkAt(headText, i) {
                let sepText = prevTextTail
                prevTextTail = ""

                if isNumberLabel(link.label) && current != nil {
                    current?.mirrors.append(Link(label: link.label, url: link.url))
                } else {
                    let isExtra = (sepText.contains(" / ") || sepText.trimmingCharacters(in: .whitespaces) == "/") && current != nil
                    if isExtra {
                        current?.extraLinks.append(Link(label: link.label, url: link.url))
                    } else {
                        let isFirstEntry = entries.isEmpty && current == nil
                        let linkTier = tier
                        let linkKind: Int
                        if link.label.trimmingCharacters(in: .whitespaces).hasPrefix("🌐") || sepText.contains("🌐") {
                            linkKind = 1
                        } else if link.label.trimmingCharacters(in: .whitespaces).hasPrefix("↪") || sepText.contains("↪") {
                            linkKind = 2
                        } else if isFirstEntry {
                            linkKind = lineKind
                        } else {
                            linkKind = 0
                        }
                        newEntry(name: link.label, url: link.url, linkTier: linkTier, linkKind: linkKind)
                    }
                }
                i = link.endIndex
                continue
            }

            prevTextTail.append(chars[i])
            i += 1
        }

        finishEntry()
        return entries
    }

    private static func parseDesc(_ descText: String) -> (description: String, tags: [String], extraLinks: [Link]) {
        let trimmed = descText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return ("", [], [])
        }

        let parts = splitOutsideLinks(trimmed, sep: " / ")
        var tagParts: [String] = []
        var extraLinks: [Link] = []

        for part in parts {
            let partTrimmed = part.trimmingCharacters(in: .whitespaces)
            if partTrimmed.isEmpty { continue }

            if !partTrimmed.contains("[") {
                tagParts.append(partTrimmed)
                continue
            }

            let links = extractInlineLinks(partTrimmed)
            if links.count == 1 && isSoleLink(partTrimmed, link: links[0]) {
                extraLinks.append(Link(label: links[0].label, url: links[0].url))
            } else {
                let social = links.filter { socialLabels.contains($0.label.trimmingCharacters(in: .whitespaces).lowercased()) }
                if !social.isEmpty {
                    extraLinks.append(contentsOf: social.map { Link(label: $0.label, url: $0.url) })
                    var chars = Array(partTrimmed)
                    for sl in social.sorted(by: { $0.startIndex > $1.startIndex }) {
                        if sl.startIndex >= 0 && sl.endIndex <= chars.count && sl.startIndex < sl.endIndex {
                            chars.removeSubrange(sl.startIndex..<sl.endIndex)
                        }
                    }
                    let currentText = String(chars)
                    let cleaned = cleanDanglingSeparators(currentText)
                    if !cleaned.isEmpty {
                        tagParts.append(markdownToPlain(cleaned))
                    }
                } else {
                    tagParts.append(markdownToPlain(partTrimmed))
                }
            }
        }

        let description = tagParts.joined(separator: " / ")
        return (description, tagParts, extraLinks)
    }

    static func splitOutsideLinks(_ text: String, sep: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        let chars = Array(text)
        let sepChars = Array(sep)
        let n = chars.count
        let sepLen = sepChars.count
        var i = 0

        while i < n {
            let ch = chars[i]
            if ch == "[" {
                depth += 1
                current.append(ch)
                i += 1
            } else if ch == "]" {
                depth -= 1
                if depth < 0 { depth = 0 }
                current.append(ch)
                if i + 1 < n && chars[i + 1] == "(" {
                    i += 1
                    current.append(chars[i])
                    i += 1
                    while i < n && chars[i] != ")" {
                        current.append(chars[i])
                        i += 1
                    }
                    if i < n {
                        current.append(chars[i])
                        i += 1
                    }
                } else {
                    i += 1
                }
            } else if depth == 0 && i + sepLen <= n && Array(chars[i..<(i + sepLen)]) == sepChars {
                parts.append(current)
                current = ""
                i += sepLen
            } else {
                current.append(ch)
                i += 1
            }
        }
        parts.append(current)
        return parts
    }

    private static func isSoleLink(_ text: String, link: ScannedLink) -> Bool {
        let stripped = text.trimmingCharacters(in: .whitespaces)
        let expected = "[\(link.label)](\(link.url))"
        return stripped == expected
    }

    static func markdownToPlain(_ text: String) -> String {
        var result = ""
        let chars = Array(text)
        let n = chars.count
        var i = 0
        while i < n {
            if let link = scanLinkAt(text, i) {
                result.append(link.label)
                i = link.endIndex
            } else {
                let ch = chars[i]
                if ch != "*" && ch != "`" {
                    result.append(ch)
                }
                i += 1
            }
        }
        return result
    }

    struct ScannedLink {
        let label: String
        let url: String
        let startIndex: Int
        let endIndex: Int
    }

    static func extractInlineLinks(_ text: String) -> [ScannedLink] {
        var links: [ScannedLink] = []
        let n = text.count
        var i = 0
        while i < n {
            if let link = scanLinkAt(text, i) {
                links.append(link)
                i = link.endIndex
            } else {
                i += 1
            }
        }
        return links
    }

    static func isNumberLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.allSatisfy({ $0.isNumber }), let num = Int64(label) else {
            return false
        }
        return num >= 2
    }

    static func scanLinkAt(_ text: String, _ startIndex: Int) -> ScannedLink? {
        let chars = Array(text)
        let n = chars.count
        if startIndex >= n || chars[startIndex] != "[" { return nil }

        if startIndex > 0 && chars[startIndex - 1] == "!" {
            var backslashCount = 0
            var b = startIndex - 2
            while b >= 0 && chars[b] == "\\" {
                backslashCount += 1
                b -= 1
            }
            if backslashCount % 2 == 0 {
                return nil
            }
        }

        var backslashCount = 0
        var b = startIndex - 1
        while b >= 0 && chars[b] == "\\" {
            backslashCount += 1
            b -= 1
        }
        if backslashCount % 2 != 0 {
            return nil
        }

        var depth = 1
        var j = startIndex + 1
        var rawLabel = ""
        while j < n && depth > 0 {
            let c = chars[j]
            if c == "\\" && j + 1 < n {
                rawLabel.append(c)
                rawLabel.append(chars[j + 1])
                j += 2
                continue
            }
            if c == "[" {
                depth += 1
                rawLabel.append(c)
                j += 1
            } else if c == "]" {
                depth -= 1
                if depth == 0 {
                    j += 1
                    break
                } else {
                    rawLabel.append(c)
                    j += 1
                }
            } else {
                rawLabel.append(c)
                j += 1
            }
        }

        if depth != 0 { return nil }
        if j >= n || chars[j] != "(" { return nil }
        j += 1

        while j < n && (chars[j] == " " || chars[j] == "\t") { j += 1 }
        if j >= n { return nil }

        if chars[j] == "<" {
            j += 1
            var urlStr = ""
            while j < n && chars[j] != ">" {
                if chars[j] == "\\" && j + 1 < n {
                    urlStr.append(chars[j + 1])
                    j += 2
                } else {
                    urlStr.append(chars[j])
                    j += 1
                }
            }
            if j >= n || chars[j] != ">" { return nil }
            j += 1
            while j < n && (chars[j] == " " || chars[j] == "\t") { j += 1 }
            if j < n && (chars[j] == "\"" || chars[j] == "'" || chars[j] == "(") {
                let quote: Character = chars[j] == "(" ? ")" : chars[j]
                j += 1
                while j < n && chars[j] != quote {
                    if chars[j] == "\\" && j + 1 < n { j += 2 } else { j += 1 }
                }
                if j < n { j += 1 }
                while j < n && (chars[j] == " " || chars[j] == "\t") { j += 1 }
            }
            if j >= n || chars[j] != ")" { return nil }
            j += 1
            let label = cleanLabel(rawLabel)
            return ScannedLink(label: label, url: cleanUrl(urlStr), startIndex: startIndex, endIndex: j)
        } else {
            var parenDepth = 1
            var urlStr = ""
            var inTitle = false
            var titleQuote: Character?

            while j < n {
                let c = chars[j]
                if c == "\\" && j + 1 < n {
                    if !inTitle { urlStr.append(chars[j + 1]) }
                    j += 2
                    continue
                }
                if inTitle {
                    if c == titleQuote {
                        inTitle = false
                        titleQuote = nil
                    }
                    j += 1
                    continue
                }
                if c == "(" {
                    parenDepth += 1
                    urlStr.append(c)
                    j += 1
                } else if c == ")" {
                    parenDepth -= 1
                    if parenDepth == 0 {
                        j += 1
                        break
                    } else {
                        urlStr.append(c)
                        j += 1
                    }
                } else if c == " " || c == "\t" {
                    if parenDepth == 1 {
                        j += 1
                        while j < n && (chars[j] == " " || chars[j] == "\t") { j += 1 }
                        if j < n && (chars[j] == "\"" || chars[j] == "'" || chars[j] == "(") {
                            inTitle = true
                            titleQuote = chars[j] == "(" ? ")" : chars[j]
                            j += 1
                        } else if j < n && chars[j] == ")" {
                            parenDepth = 0
                            j += 1
                            break
                        }
                    } else {
                        urlStr.append(c)
                        j += 1
                    }
                } else {
                    urlStr.append(c)
                    j += 1
                }
            }

            if parenDepth != 0 { return nil }
            let label = cleanLabel(rawLabel)
            return ScannedLink(label: label, url: cleanUrl(urlStr), startIndex: startIndex, endIndex: j)
        }
    }

    private static func cleanUrl(_ raw: String) -> String {
        return raw.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func cleanLabel(_ raw: String) -> String {
        let chars = Array(raw)
        var result = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "\\" && i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "[" || next == "]" || next == "\\" {
                    result.append(next)
                    i += 2
                    continue
                }
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    static func cleanDanglingSeparators(_ s: String) -> String {
        var str = s.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed && !str.isEmpty {
            changed = false
            str = str.trimmingCharacters(in: .whitespaces)
            if str.hasSuffix(",") || str.hasSuffix("/") {
                str = String(str.dropLast()).trimmingCharacters(in: .whitespaces)
                changed = true
            }
            if str.hasPrefix(",") || str.hasPrefix("/") {
                str = String(str.dropFirst()).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        let parts = str.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    static func stripInvisibleChars(_ text: String) -> String {
        if !text.contains(where: { $0 == "\u{2060}" || $0 == "\u{200B}" || $0 == "\u{200C}" || $0 == "\u{FEFF}" }) {
            return text
        }
        return text.filter { $0 != "\u{2060}" && $0 != "\u{200B}" && $0 != "\u{200C}" && $0 != "\u{FEFF}" }
    }

    static func stripLeadingEmoji(_ text: String) -> String {
        Slug.stripTitlePrefix(text)
    }
}

final class AnchorTracker {
    private var seen: [String: Int] = [:]

    func add(_ rawAnchor: String) -> String {
        guard let count = seen[rawAnchor] else {
            seen[rawAnchor] = 0
            return rawAnchor
        }
        let next = count + 1
        seen[rawAnchor] = next
        return "\(rawAnchor)-\(next)"
    }
}

final class IdAssigner {
    private var counts: [String: Int] = [:]

    func assign(normUrl: String, sectionId: String) -> String {
        let key = "\(sectionId)|\(normUrl)"
        let count = counts[key, default: 0]
        counts[key] = count + 1
        return count == 0 ? key : "\(key)#\(count + 1)"
    }
}

enum Slug {
    static func isEmojiCodePoint(_ cp: UInt32) -> Bool {
        return (cp >= 0x1F300 && cp <= 0x1FAFF) ||
               (cp >= 0x2600 && cp <= 0x27BF) ||
               (cp >= 0xFE00 && cp <= 0xFE0F) ||
               (cp >= 0x2190 && cp <= 0x21FF) ||
               (cp >= 0x2300 && cp <= 0x23FF) ||
               (cp >= 0x2700 && cp <= 0x27BF) ||
               (cp >= 0x2B00 && cp <= 0x2BFF) ||
               (cp >= 0x3000 && cp <= 0x303F) ||
               cp == 0xFE0F
    }

    static func stripTitlePrefix(_ title: String) -> String {
        let stripped = title.replacingOccurrences(of: "►", with: "").replacingOccurrences(of: "▷", with: "")
        var result = ""
        var inPrefix = true
        for s in stripped.unicodeScalars {
            let cp = s.value
            if inPrefix && (isEmojiCodePoint(cp) || cp == 0x20 || cp == 0x09) {
                continue
            }
            inPrefix = false
            result.unicodeScalars.append(s)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func slugify(_ title: String) -> String {
        let s = stripTitlePrefix(title)
        let nfkd = s.decomposedStringWithCompatibilityMapping
        var cleaned = ""
        for u in nfkd.unicodeScalars {
            let v = u.value
            if (v >= 0x0300 && v <= 0x036F) || (v <= 0x001F) || (v >= 0x007F && v <= 0x009F) {
                continue
            }
            cleaned.unicodeScalars.append(u)
        }
        let sepChars = Set(" \t\r\n~`!@#$%^&*()-_+=[]{}|\\;:\"'<>,.?/")
        var result = ""
        var inSep = false
        for c in cleaned {
            if sepChars.contains(c) {
                if !inSep {
                    result.append("-")
                    inSep = true
                }
            } else {
                result.append(c)
                inSep = false
            }
        }
        while result.hasPrefix("-") {
            result.removeFirst()
        }
        while result.hasSuffix("-") {
            result.removeLast()
        }
        if let first = result.first, first.isNumber {
            result = "_" + result
        }
        return result.lowercased()
    }
}

enum Ids {
    private static let removeParams: Set<String> = ["ref", "fbclid"]

    static func normalizeUrl(_ u: String) -> String {
        let hashIdx = u.firstIndex(of: "#")
        let fragment = hashIdx != nil ? String(u[u.index(after: hashIdx!)...]) : ""
        let withoutHash = hashIdx != nil ? String(u[..<hashIdx!]) : u

        let queryIdx = withoutHash.firstIndex(of: "?")
        let query = queryIdx != nil ? String(withoutHash[withoutHash.index(after: queryIdx!)...]) : ""
        let withoutQuery = queryIdx != nil ? String(withoutHash[..<queryIdx!]) : withoutHash

        let scheme: String
        let netlocAndPath: String
        if let schemeRange = withoutQuery.range(of: "://") {
            scheme = String(withoutQuery[..<schemeRange.lowerBound]).lowercased()
            netlocAndPath = String(withoutQuery[schemeRange.upperBound...])
        } else if let colonIdx = withoutQuery.firstIndex(of: ":") {
            scheme = String(withoutQuery[..<colonIdx]).lowercased()
            let rest = String(withoutQuery[withoutQuery.index(after: colonIdx)...])
            netlocAndPath = rest.hasPrefix("//") ? String(rest.dropFirst(2)) : rest
        } else {
            scheme = ""
            netlocAndPath = withoutQuery
        }

        var netloc: String
        var path: String
        if let slashIdx = netlocAndPath.firstIndex(of: "/") {
            netloc = String(netlocAndPath[..<slashIdx]).lowercased()
            path = String(netlocAndPath[slashIdx...])
        } else {
            netloc = netlocAndPath.lowercased()
            path = ""
        }

        if netloc.hasPrefix("www.") {
            netloc = String(netloc.dropFirst(4))
        }

        if let colonPortIdx = netloc.lastIndex(of: ":") {
            let host = String(netloc[..<colonPortIdx])
            let port = String(netloc[netloc.index(after: colonPortIdx)...])
            if (scheme == "http" && port == "80") || (scheme == "https" && port == "443") {
                netloc = host
            }
        }

        while path.hasSuffix("/") {
            path.removeLast()
        }

        let normalizedQuery = query.isEmpty ? "" : filterAndEncodeQuery(query)

        var sb = ""
        if !scheme.isEmpty {
            sb += scheme + "://"
        } else if withoutQuery.hasPrefix("//") {
            sb += "//"
        }
        sb += netloc
        sb += path
        if !normalizedQuery.isEmpty {
            sb += "?" + normalizedQuery
        }
        if !fragment.isEmpty {
            sb += "#" + fragment
        }
        return sb
    }

    private static func filterAndEncodeQuery(_ query: String) -> String {
        let parts = query.components(separatedBy: "&")
        var pairs: [(String, String)] = []
        for part in parts {
            if part.isEmpty { continue }
            if let eqIdx = part.firstIndex(of: "=") {
                let rawKey = String(part[..<eqIdx])
                let rawVal = String(part[part.index(after: eqIdx)...])
                let key = rawKey.removingPercentEncoding ?? rawKey
                let value = rawVal.removingPercentEncoding ?? rawVal
                pairs.append((key, value))
            } else {
                let key = part.removingPercentEncoding ?? part
                pairs.append((key, ""))
            }
        }

        let filtered = pairs.filter { k, _ in
            !removeParams.contains(k) && !k.hasPrefix("utm_")
        }

        if filtered.isEmpty { return "" }
        return filtered.map { k, v in
            let ek = urlEncode(k)
            let ev = urlEncode(v)
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }

    private static func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

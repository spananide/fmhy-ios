import Foundation

struct Base64Map: Sendable {
    private let map: [String: [String]]

    var resolvedAnchors: Int {
        map.count
    }

    init(html: String) {
        var parsed: [String: [String]] = [:]
        let h4Pattern = "<h4[^>]*id=[\"']([^\"']+)[\"'][^>]*>(.*?)(?=<h4|\\Z)"
        let codePattern = "<code>(.*?)</code>"

        guard let h4Regex = try? NSRegularExpression(pattern: h4Pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let codeRegex = try? NSRegularExpression(pattern: codePattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            self.map = [:]
            return
        }

        let nsHtml = html as NSString
        let fullRange = NSRange(location: 0, length: nsHtml.length)
        let h4Matches = h4Regex.matches(in: html, options: [], range: fullRange)

        for h4Match in h4Matches {
            guard h4Match.numberOfRanges >= 3 else { continue }
            let anchorRange = h4Match.range(at: 1)
            let bodyRange = h4Match.range(at: 2)
            guard anchorRange.location != NSNotFound, bodyRange.location != NSNotFound else { continue }

            let anchor = nsHtml.substring(with: anchorRange)
            let body = nsHtml.substring(with: bodyRange)
            let nsBody = body as NSString
            let bodyRangeFull = NSRange(location: 0, length: nsBody.length)

            let codeMatches = codeRegex.matches(in: body, options: [], range: bodyRangeFull)
            var urls: [String] = []
            for codeMatch in codeMatches {
                guard codeMatch.numberOfRanges >= 2 else { continue }
                let codeRange = codeMatch.range(at: 1)
                guard codeRange.location != NSNotFound else { continue }
                let codeText = nsBody.substring(with: codeRange).trimmingCharacters(in: .whitespacesAndNewlines)
                let unescaped = Base64Map.unescapeHTML(codeText)
                if let resolved = Base64Map.resolveBase64String(unescaped) {
                    urls.append(resolved)
                }
            }
            if !urls.isEmpty {
                parsed[anchor] = urls
            }
        }
        self.map = parsed
    }

    func resolve(url: String, mirrors: [Link]) -> (url: String, originalUrl: String?, mirrors: [Link]) {
        let pattern = "^https?://(www\\.)?rentry\\.(co|org)/FMHYB64#(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return (url, nil, mirrors)
        }
        let nsUrl = url as NSString
        let match = regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: nsUrl.length))
        guard let m = match, m.numberOfRanges >= 4 else {
            return (url, nil, mirrors)
        }
        let anchorRange = m.range(at: 3)
        guard anchorRange.location != NSNotFound else {
            return (url, nil, mirrors)
        }
        let anchor = nsUrl.substring(with: anchorRange)
        guard let urls = map[anchor], let primary = urls.first else {
            return (url, nil, mirrors)
        }
        let originalUrl = url
        let extraMirrors = urls.dropFirst().enumerated().map { idx, u in
            Link(label: "\(idx + 2)", url: u)
        }
        let allMirrors = extraMirrors + mirrors
        return (primary, originalUrl, allMirrors)
    }

    private static func unescapeHTML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        return result
    }

    private static func decodeBase64(_ input: String) -> String? {
        var str = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let missing = str.count % 4
        if missing != 0 {
            str += String(repeating: "=", count: 4 - missing)
        }
        if let data = Data(base64Encoded: str) ?? Data(base64Encoded: str, options: .ignoreUnknownCharacters) {
            if let decoded = String(data: data, encoding: .utf8) {
                return decoded
            }
        }
        let urlSafe = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        if let data = Data(base64Encoded: urlSafe) ?? Data(base64Encoded: urlSafe, options: .ignoreUnknownCharacters) {
            if let decoded = String(data: data, encoding: .utf8) {
                return decoded
            }
        }
        return nil
    }

    private static func resolveBase64String(_ s: String, maxRounds: Int = 3) -> String? {
        var current = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<maxRounds {
            if current.hasPrefix("http://") || current.hasPrefix("https://") {
                return current
            }
            guard let decoded = decodeBase64(current) else { return nil }
            current = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if current.hasPrefix("http://") || current.hasPrefix("https://") {
            return current
        }
        return nil
    }
}

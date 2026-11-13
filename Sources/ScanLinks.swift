import Foundation

// MARK: - Scan Links

public enum ScanLinks: Sendable {
    public nonisolated static func fileReport(service: ScanService, sha256: String) -> String {
        switch service {
        case .virusTotal:
            return "https://www.virustotal.com/gui/file/\(sha256)"
        case .hybridAnalysis:
            return "https://hybrid-analysis.com/sample/\(sha256)"
        }
    }

    public nonisolated static func linkReport(service: ScanService, url: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?")
        let enc = url.addingPercentEncoding(withAllowedCharacters: allowed) ?? url
        switch service {
        case .virusTotal:
            return "https://www.virustotal.com/gui/search/\(enc)"
        case .hybridAnalysis:
            return "https://hybrid-analysis.com/search?query=\(enc)"
        }
    }

    public nonisolated static func uploadPage(service: ScanService) -> String {
        switch service {
        case .virusTotal:
            return "https://www.virustotal.com/gui/home/upload"
        case .hybridAnalysis:
            return "https://hybrid-analysis.com/"
        }
    }

    public nonisolated static func vtUrlId(_ url: String) -> String {
        let data = Data(url.utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

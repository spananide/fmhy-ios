import Foundation

enum ReportArea: String, CaseIterable, Identifiable {
    case pageDoesNotLoad = "Page does not load"
    case lists = "Lists"
    case search = "Search"
    case downloads = "Downloads"
    case update = "Update"
    case other = "Other"

    var id: String { rawValue }
    var label: String { rawValue }
}

struct TechnicalInfo: Equatable {
    var appVersion: String
    var buildNumber: String
    var osVersion: String
    var deviceModel: String
    var wikiLastUpdated: String?
}

struct ReportDraft: Equatable {
    var area: ReportArea
    var whatWentWrong: String
    var includeTechnical: Bool
    var includePageUrl: Bool
    var pageUrl: String?
    var technical: TechnicalInfo?
}

struct IssueLink: Equatable {
    let url: String
    let truncated: Bool
}

enum IssueUrlBuilder {
    static let baseURL = "https://github.com/spananide/fmhy-ios/issues/new"
    static let truncationSuffix = "\n\n(report shortened - the full text was copied)"

    nonisolated static func buildTitle(area: ReportArea, whatWentWrong: String) -> String {
        let singleLine = whatWentWrong
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = singleLine.isEmpty ? "(not described)" : String(singleLine.prefix(60))
        return "[\(area.label)] \(desc)"
    }

    nonisolated static func buildTitle(draft: ReportDraft) -> String {
        buildTitle(area: draft.area, whatWentWrong: draft.whatWentWrong)
    }

    nonisolated static func buildBody(draft: ReportDraft) -> String {
        var sb = "## What happened\n"
        sb.append("Area: \(draft.area.label)\n")
        let what = draft.whatWentWrong.trimmingCharacters(in: .whitespacesAndNewlines)
        if what.isEmpty {
            sb.append("(not described)")
        } else {
            sb.append(what)
        }

        if draft.includeTechnical {
            sb.append("\n\n## Technical details\n")
            let tech = draft.technical
            sb.append("App version: \(tech?.appVersion ?? "Unknown") (\(tech?.buildNumber ?? "1"))\n")
            sb.append("iOS version: \(tech?.osVersion ?? "Unknown")\n")
            sb.append("Device model: \(tech?.deviceModel ?? "Unknown")\n")
            let wikiDate = tech?.wikiLastUpdated ?? "Bundled wiki"
            sb.append("Wiki last updated: \(wikiDate)")
        }

        if draft.includePageUrl, let pageUrl = draft.pageUrl, !pageUrl.isEmpty {
            sb.append("\n\n## Page\n")
            sb.append("Web address: \(pageUrl)")
        }

        return sb
    }

    nonisolated static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.*~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    nonisolated static func build(
        title: String,
        body: String,
        baseURL: String = IssueUrlBuilder.baseURL,
        maxLength: Int = 7000
    ) -> IssueLink {
        let encTitle = urlEncode(title)
        let fullUrl = "\(baseURL)?title=\(encTitle)&body=\(urlEncode(body))"
        if fullUrl.count <= maxLength {
            return IssueLink(url: fullUrl, truncated: false)
        }

        var lines = body.components(separatedBy: "\n")
        var finalUrl: String?

        while !lines.isEmpty {
            lines.removeLast()
            let shortenedBody: String
            if lines.isEmpty {
                shortenedBody = truncationSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                shortenedBody = lines.joined(separator: "\n") + truncationSuffix
            }
            let candidateUrl = "\(baseURL)?title=\(encTitle)&body=\(urlEncode(shortenedBody))"
            if candidateUrl.count <= maxLength {
                finalUrl = candidateUrl
                break
            }
        }

        if finalUrl == nil {
            var shortened = truncationSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
            while !shortened.isEmpty && "\(baseURL)?title=\(encTitle)&body=\(urlEncode(shortened))".count > maxLength {
                shortened.removeLast()
            }
            finalUrl = "\(baseURL)?title=\(encTitle)&body=\(urlEncode(shortened))"
        }

        return IssueLink(url: finalUrl ?? "\(baseURL)?title=\(encTitle)", truncated: true)
    }

    nonisolated static func build(draft: ReportDraft, maxLength: Int = 7000) -> IssueLink {
        let title = buildTitle(draft: draft)
        let body = buildBody(draft: draft)
        return build(title: title, body: body, maxLength: maxLength)
    }
}

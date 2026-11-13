import Foundation

// MARK: - Check UI Text

public enum CheckUiText {
    public nonisolated static func checkedLine(_ result: ScanResult, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let checkedYear = calendar.component(.year, from: result.checkedAt)
        let nowYear = calendar.component(.year, from: now)

        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = (checkedYear == nowYear) ? "d MMM" : "d MMM yyyy"
        let dateStr = formatter.string(from: result.checkedAt)
        return "Checked \(dateStr)"
    }

    public nonisolated static func checkedLine(result: ScanResult, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        checkedLine(result, now: now, timeZone: timeZone)
    }

    public nonisolated static func serviceLine(_ r: ServiceResult) -> String {
        if let error = r.error {
            return ScanText.error(service: r.service, e: error)
        }
        if let flagged = r.flagged, let engines = r.engines, engines > 0 {
            return ScanText.engines(flagged: flagged, engines: engines)
        }
        return r.detail ?? ScanText.unknownFile
    }

    public nonisolated static func serviceLine(r: ServiceResult) -> String {
        serviceLine(r)
    }

    public nonisolated static func verdictTitle(_ v: ScanVerdict) -> String {
        switch v {
        case .noFlags:
            return "No flags"
        case .suspicious:
            return "Suspicious"
        case .dangerous:
            return "Dangerous: don't open this file"
        case .unknown:
            return "Unknown"
        }
    }

    public nonisolated static func verdictTitle(v: ScanVerdict) -> String {
        verdictTitle(v)
    }

    public nonisolated static func linkVerdictTitle(_ v: ScanVerdict) -> String {
        switch v {
        case .noFlags:
            return "No flags"
        case .suspicious:
            return "Suspicious"
        case .dangerous:
            return "Dangerous: don't download this file"
        case .unknown:
            return "Unknown"
        }
    }

    public nonisolated static func linkVerdictTitle(v: ScanVerdict) -> String {
        linkVerdictTitle(v)
    }

    public nonisolated static func sendNote(_ services: [ScanService]) -> String {
        let names = services.map { $0.label }.joined(separator: " and ")
        return "The web address will be sent to \(names). Some links contain personal or one-time codes."
    }

    public nonisolated static func sendNote(services: [ScanService]) -> String {
        sendNote(services)
    }

    public nonisolated static func hasError(_ result: ScanResult, error: ScanError) -> Bool {
        result.services.contains { $0.error == error }
    }

    public nonisolated static func hasError(result: ScanResult, error: ScanError) -> Bool {
        hasError(result, error: error)
    }

    public nonisolated static func hasError(_ result: ScanResult) -> Bool {
        result.services.contains { $0.error != nil }
    }

    public nonisolated static func hasError(result: ScanResult) -> Bool {
        hasError(result)
    }

    public nonisolated static func anyUnknown(_ result: ScanResult) -> Bool {
        result.services.contains { $0.verdict == .unknown && $0.error == nil }
    }

    public nonisolated static func anyUnknown(result: ScanResult) -> Bool {
        anyUnknown(result)
    }
}

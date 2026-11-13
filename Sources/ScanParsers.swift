import Foundation

// MARK: - Scan Parsers

public enum ScanParsers: Sendable {
    public nonisolated static func errorFor(_ httpCode: Int) -> ScanError? {
        switch httpCode {
        case 401, 403:
            return .badKey
        case 429, 204:
            return .limit
        case 413:
            return .tooBig
        case 404:
            return nil
        case 200...299:
            return nil
        default:
            return .other
        }
    }

    public nonisolated static func vtReport(_ data: Data, reportUrl: String) -> ServiceResult? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let dataDict = root["data"] as? [String: Any],
              let attributes = dataDict["attributes"] as? [String: Any],
              let stats = attributes["last_analysis_stats"] as? [String: Any] else {
            return nil
        }

        let malicious = (stats["malicious"] as? NSNumber)?.intValue ?? 0
        let suspicious = (stats["suspicious"] as? NSNumber)?.intValue ?? 0
        let undetected = (stats["undetected"] as? NSNumber)?.intValue ?? 0
        let harmless = (stats["harmless"] as? NSNumber)?.intValue ?? 0

        let engines = malicious + suspicious + undetected + harmless
        let flagged = malicious + suspicious
        let verdict = ScanVerdicts.fromCounts(malicious: malicious, suspicious: suspicious, engines: engines)

        var scannedAt: Date?
        if let lastSec = (attributes["last_analysis_date"] as? NSNumber)?.doubleValue {
            scannedAt = Date(timeIntervalSince1970: lastSec)
        }

        return ServiceResult(
            service: .virusTotal,
            verdict: verdict,
            flagged: flagged,
            engines: engines,
            detail: nil,
            scannedAt: scannedAt,
            reportUrl: reportUrl,
            error: nil
        )
    }

    public nonisolated static func vtReport(_ body: String, reportUrl: String) -> ServiceResult? {
        guard let data = body.data(using: .utf8) else { return nil }
        return vtReport(data, reportUrl: reportUrl)
    }

    public nonisolated static func vtAnalysisId(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let dataDict = root["data"] as? [String: Any] else {
            return nil
        }
        return dataDict["id"] as? String
    }

    public nonisolated static func vtAnalysisId(_ body: String) -> String? {
        guard let data = body.data(using: .utf8) else { return nil }
        return vtAnalysisId(data)
    }

    public nonisolated static func vtUploadUrl(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return root["data"] as? String
    }

    public nonisolated static func vtUploadUrl(_ body: String) -> String? {
        guard let data = body.data(using: .utf8) else { return nil }
        return vtUploadUrl(data)
    }

    public nonisolated static func vtAnalysis(_ data: Data, reportUrl: String) -> ServiceResult? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let dataDict = root["data"] as? [String: Any],
              let attributes = dataDict["attributes"] as? [String: Any] else {
            return nil
        }

        guard let status = attributes["status"] as? String, status == "completed" else {
            return nil
        }

        guard let stats = attributes["stats"] as? [String: Any] else {
            return nil
        }

        let malicious = (stats["malicious"] as? NSNumber)?.intValue ?? 0
        let suspicious = (stats["suspicious"] as? NSNumber)?.intValue ?? 0
        let undetected = (stats["undetected"] as? NSNumber)?.intValue ?? 0
        let harmless = (stats["harmless"] as? NSNumber)?.intValue ?? 0

        let engines = malicious + suspicious + undetected + harmless
        let flagged = malicious + suspicious
        let verdict = ScanVerdicts.fromCounts(malicious: malicious, suspicious: suspicious, engines: engines)

        var scannedAt: Date?
        if let dateSec = (attributes["date"] as? NSNumber)?.doubleValue {
            scannedAt = Date(timeIntervalSince1970: dateSec)
        }

        return ServiceResult(
            service: .virusTotal,
            verdict: verdict,
            flagged: flagged,
            engines: engines,
            detail: nil,
            scannedAt: scannedAt,
            reportUrl: reportUrl,
            error: nil
        )
    }

    public nonisolated static func vtAnalysis(_ body: String, reportUrl: String) -> ServiceResult? {
        guard let data = body.data(using: .utf8) else { return nil }
        return vtAnalysis(data, reportUrl: reportUrl)
    }

    public nonisolated static func haOverview(_ data: Data, reportUrl: String) -> ServiceResult? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let rawVerdict = root["verdict"] as? String
        let verdict = ScanVerdicts.fromHybridVerdict(rawVerdict)

        let threatScore = (root["threat_score"] as? NSNumber)?.intValue
        let detail = threatScore.map { "Threat score \($0) of 100" }

        let rawDate = (root["last_multi_scan"] as? String) ?? (root["analysis_start_time"] as? String)
        let scannedAt = rawDate.flatMap(parseISO8601Date)

        return ServiceResult(
            service: .hybridAnalysis,
            verdict: verdict,
            flagged: nil,
            engines: nil,
            detail: detail,
            scannedAt: scannedAt,
            reportUrl: reportUrl,
            error: nil
        )
    }

    public nonisolated static func haOverview(_ body: String, reportUrl: String) -> ServiceResult? {
        guard let data = body.data(using: .utf8) else { return nil }
        return haOverview(data, reportUrl: reportUrl)
    }

    public nonisolated static func haQuickScanId(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return root["id"] as? String
    }

    public nonisolated static func haQuickScanId(_ body: String) -> String? {
        guard let data = body.data(using: .utf8) else { return nil }
        return haQuickScanId(data)
    }

    public nonisolated static func haQuickScan(_ data: Data, reportUrl: String) -> ServiceResult? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let finished = (root["finished"] as? NSNumber)?.boolValue ?? (root["finished"] as? Bool) ?? false
        guard finished else {
            return nil
        }

        guard let scanners = root["scanners"] as? [[String: Any]] else {
            return nil
        }

        var malicious = 0
        var suspicious = 0
        var engines = 0

        for scanner in scanners {
            guard let status = (scanner["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                continue
            }
            switch status {
            case "malicious":
                malicious += 1
                engines += 1
            case "suspicious":
                suspicious += 1
                engines += 1
            case "clean", "no-classification":
                engines += 1
            default:
                break
            }
        }

        let flagged = malicious + suspicious
        let verdict = ScanVerdicts.fromCounts(malicious: malicious, suspicious: suspicious, engines: engines)

        return ServiceResult(
            service: .hybridAnalysis,
            verdict: verdict,
            flagged: flagged,
            engines: engines,
            detail: nil,
            scannedAt: nil,
            reportUrl: reportUrl,
            error: nil
        )
    }

    public nonisolated static func haQuickScan(_ body: String, reportUrl: String) -> ServiceResult? {
        guard let data = body.data(using: .utf8) else { return nil }
        return haQuickScan(data, reportUrl: reportUrl)
    }

    // MARK: - Private Helpers

    private nonisolated static func parseISO8601Date(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let d = formatter.date(from: str) {
            return d
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: str) {
            return d
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return df.date(from: str)
    }
}

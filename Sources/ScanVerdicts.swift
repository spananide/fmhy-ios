import Foundation

// MARK: - Scan Verdicts

public enum ScanVerdicts: Sendable {
    public nonisolated static func fromCounts(malicious: Int, suspicious: Int, engines: Int) -> ScanVerdict {
        if engines <= 0 {
            return .unknown
        }
        if malicious >= 3 {
            return .dangerous
        }
        if malicious >= 1 || suspicious >= 1 {
            return .suspicious
        }
        return .noFlags
    }

    public nonisolated static func fromHybridVerdict(_ verdict: String?) -> ScanVerdict {
        guard let verdict = verdict else {
            return .unknown
        }
        switch verdict.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "malicious":
            return .dangerous
        case "suspicious":
            return .suspicious
        case "no specific threat", "no-specific-threat", "whitelisted", "clean":
            return .noFlags
        default:
            return .unknown
        }
    }

    public nonisolated static func combine(_ results: [ServiceResult]) -> ScanVerdict {
        let valid = results.filter { $0.error == nil && $0.verdict != .unknown }
        guard !valid.isEmpty else {
            return .unknown
        }
        return valid.max(by: { $0.verdict.rank < $1.verdict.rank })?.verdict ?? .unknown
    }
}

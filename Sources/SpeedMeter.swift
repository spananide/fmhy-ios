import Foundation

struct SpeedMeter: Sendable {
    private let alpha: Double
    private var lastSampleBytes: Int64?
    private var lastSampleMs: Int64?
    private var smoothedRate: Double?

    init(alpha: Double = 0.3) {
        self.alpha = alpha
        self.lastSampleBytes = nil
        self.lastSampleMs = nil
        self.smoothedRate = nil
    }

    mutating func sample(totalBytes: Int64, nowMs: Int64) {
        guard let prevMs = lastSampleMs, let prevBytes = lastSampleBytes else {
            lastSampleMs = nowMs
            lastSampleBytes = totalBytes
            return
        }

        let dt = nowMs - prevMs
        if dt < 250 {
            return
        }

        let deltaBytes = max(0, totalBytes - prevBytes)
        let instantRate = (Double(deltaBytes) * 1000.0) / Double(dt)

        if let currentSmoothed = smoothedRate {
            smoothedRate = alpha * instantRate + (1.0 - alpha) * currentSmoothed
        } else {
            smoothedRate = instantRate
        }

        lastSampleMs = nowMs
        lastSampleBytes = totalBytes
    }

    var bytesPerSecond: Int64? {
        guard let rate = smoothedRate, !rate.isNaN, !rate.isInfinite else {
            return nil
        }
        return Int64(rate.rounded())
    }

    func etaSeconds(remainingBytes: Int64) -> Int64? {
        guard let speed = bytesPerSecond, speed > 0, remainingBytes >= 0 else {
            return nil
        }
        if remainingBytes == 0 {
            return 0
        }
        return Int64(ceil(Double(remainingBytes) / Double(speed)))
    }

    mutating func reset() {
        lastSampleBytes = nil
        lastSampleMs = nil
        smoothedRate = nil
    }

    nonisolated static func formatSpeed(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else {
            return "0 B/s"
        }
        let d = Double(bytesPerSecond)
        if d < 1_000 {
            return "\(bytesPerSecond) B/s"
        } else if d < 1_000_000 {
            let kb = d / 1_000.0
            return String(format: "%.1f KB/s", locale: Locale(identifier: "en_US_POSIX"), kb)
        } else if d < 1_000_000_000 {
            let mb = d / 1_000_000.0
            return String(format: "%.1f MB/s", locale: Locale(identifier: "en_US_POSIX"), mb)
        } else {
            let gb = d / 1_000_000_000.0
            return String(format: "%.1f GB/s", locale: Locale(identifier: "en_US_POSIX"), gb)
        }
    }

    nonisolated static func formatEta(_ seconds: Int64) -> String? {
        guard seconds >= 0 else { return nil }
        if seconds == 0 { return "0s left" }
        if seconds < 60 {
            return "\(seconds)s left"
        }
        let mins = seconds / 60
        let remSecs = seconds % 60
        if mins < 60 {
            if remSecs > 0 && mins < 5 {
                return "\(mins)m \(remSecs)s left"
            }
            return "\(mins)m left"
        }
        let hours = mins / 60
        let remMins = mins % 60
        if remMins > 0 {
            return "\(hours)h \(remMins)m left"
        }
        return "\(hours)h left"
    }
}

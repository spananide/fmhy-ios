import Foundation
import Combine

// MARK: - Mark

struct VtMark: Codable, Equatable, Sendable {
    var flagged: Int?
    var engines: Int?
    var checkedAt: Date

    init(flagged: Int? = nil, engines: Int? = nil, checkedAt: Date) {
        self.flagged = flagged
        self.engines = engines
        self.checkedAt = checkedAt
    }

    enum CodingKeys: String, CodingKey {
        case flagged, engines, checkedAt
        case f, e, at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.flagged = try container.decodeIfPresent(Int.self, forKey: .flagged)
            ?? container.decodeIfPresent(Int.self, forKey: .f)
        self.engines = try container.decodeIfPresent(Int.self, forKey: .engines)
            ?? container.decodeIfPresent(Int.self, forKey: .e)

        if let doubleVal = try? container.decode(Double.self, forKey: .checkedAt) {
            if doubleVal > 100_000_000_000 {
                self.checkedAt = Date(timeIntervalSince1970: doubleVal / 1000.0)
            } else if doubleVal > 1_000_000_000 {
                self.checkedAt = Date(timeIntervalSince1970: doubleVal)
            } else {
                self.checkedAt = Date(timeIntervalSinceReferenceDate: doubleVal)
            }
        } else if let doubleVal = try? container.decode(Double.self, forKey: .at) {
            if doubleVal > 100_000_000_000 {
                self.checkedAt = Date(timeIntervalSince1970: doubleVal / 1000.0)
            } else if doubleVal > 1_000_000_000 {
                self.checkedAt = Date(timeIntervalSince1970: doubleVal)
            } else {
                self.checkedAt = Date(timeIntervalSinceReferenceDate: doubleVal)
            }
        } else if let str = try? container.decode(String.self, forKey: .checkedAt) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) ?? ISO8601DateFormatter().date(from: str) {
                self.checkedAt = d
            } else {
                throw DecodingError.dataCorruptedError(forKey: .checkedAt, in: container, debugDescription: "Invalid date: \(str)")
            }
        } else if let date = try? container.decode(Date.self, forKey: .checkedAt) {
            self.checkedAt = date
        } else {
            self.checkedAt = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(flagged, forKey: .flagged)
        try container.encodeIfPresent(engines, forKey: .engines)
        try container.encode(Int64(checkedAt.timeIntervalSince1970 * 1000), forKey: .checkedAt)
    }
}

typealias Mark = VtMark

// MARK: - VtSiteChecks

@MainActor
final class VtSiteChecks: ObservableObject {
    typealias Mark = VtMark

    static let ttl: TimeInterval = 30 * 24 * 60 * 60
    static let cap: Int = 500

    @Published private(set) var marks: [String: VtMark] = [:]

    private let fileURL: URL
    private let now: @MainActor () -> Date

    init(
        fileURL: URL = defaultFileURL(),
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.now = now
        load()
    }

    var hasMarks: Bool {
        let currentDate = now()
        return marks.values.contains { currentDate.timeIntervalSince($0.checkedAt) < Self.ttl }
    }

    func markFor(host: String) -> VtMark? {
        let norm = Self.normalizeHost(host)
        guard let mark = marks[norm] else { return nil }
        if now().timeIntervalSince(mark.checkedAt) >= Self.ttl {
            return nil
        }
        return mark
    }

    func remember(host: String, flagged: Int?, engines: Int?) {
        let norm = Self.normalizeHost(host)
        guard !norm.isEmpty else { return }
        let currentDate = now()
        var updated = marks
        updated[norm] = VtMark(flagged: flagged, engines: engines, checkedAt: currentDate)
        let nonExpired = updated.filter { currentDate.timeIntervalSince($0.value.checkedAt) < Self.ttl }
        if nonExpired.count > Self.cap {
            let sorted = nonExpired.sorted { $0.value.checkedAt > $1.value.checkedAt }
            let capped = sorted.prefix(Self.cap)
            marks = Dictionary(uniqueKeysWithValues: capped.map { ($0.key, $0.value) })
        } else {
            marks = nonExpired
        }
        save()
    }

    func forgetAll() {
        marks = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    nonisolated static func shouldRemember(_ verdict: ScanVerdict) -> Bool {
        verdict == .noFlags
    }

    nonisolated static func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("vtsites.json")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([String: VtMark].self, from: data)
            let currentDate = now()
            marks = decoded.filter { currentDate.timeIntervalSince($0.value.checkedAt) < Self.ttl }
        } catch {
            marks = [:]
        }
    }

    private func save() {
        do {
            let parentDir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(marks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silently ignore storage failures
        }
    }
}

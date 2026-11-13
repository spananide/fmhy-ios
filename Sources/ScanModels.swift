import Foundation

// MARK: - Scan Service

public enum ScanService: String, Codable, Hashable, Sendable, CaseIterable {
    case virusTotal = "VIRUSTOTAL"
    case hybridAnalysis = "HYBRID_ANALYSIS"

    public var label: String {
        switch self {
        case .virusTotal:
            return "VirusTotal"
        case .hybridAnalysis:
            return "Hybrid Analysis"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.uppercased().replacingOccurrences(of: "-", with: "_") {
        case "VIRUSTOTAL", "VIRUS_TOTAL":
            self = .virusTotal
        case "HYBRIDANALYSIS", "HYBRID_ANALYSIS":
            self = .hybridAnalysis
        default:
            if let match = ScanService(rawValue: raw) {
                self = match
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown ScanService: \(raw)"
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Scan Verdict

public enum ScanVerdict: String, Codable, Hashable, Sendable, CaseIterable {
    case noFlags = "NO_FLAGS"
    case suspicious = "SUSPICIOUS"
    case dangerous = "DANGEROUS"
    case unknown = "UNKNOWN"

    public var label: String {
        switch self {
        case .noFlags:
            return "No flags"
        case .suspicious:
            return "Suspicious"
        case .dangerous:
            return "Dangerous"
        case .unknown:
            return "Unknown"
        }
    }

    public var rank: Int {
        switch self {
        case .unknown:
            return 0
        case .noFlags:
            return 1
        case .suspicious:
            return 2
        case .dangerous:
            return 3
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.uppercased().replacingOccurrences(of: "-", with: "_") {
        case "NO_FLAGS", "NOFLAGS":
            self = .noFlags
        case "SUSPICIOUS":
            self = .suspicious
        case "DANGEROUS":
            self = .dangerous
        case "UNKNOWN":
            self = .unknown
        default:
            if let match = ScanVerdict(rawValue: raw) {
                self = match
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown ScanVerdict: \(raw)"
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Scan Error

public enum ScanError: String, Codable, Hashable, Sendable, CaseIterable {
    case badKey = "BAD_KEY"
    case limit = "LIMIT"
    case offline = "OFFLINE"
    case tooBig = "TOO_BIG"
    case other = "OTHER"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.uppercased().replacingOccurrences(of: "-", with: "_") {
        case "BAD_KEY", "BADKEY":
            self = .badKey
        case "LIMIT":
            self = .limit
        case "OFFLINE":
            self = .offline
        case "TOO_BIG", "TOOBIG":
            self = .tooBig
        case "OTHER":
            self = .other
        default:
            if let match = ScanError(rawValue: raw) {
                self = match
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown ScanError: \(raw)"
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Scan Kind

public enum ScanKind: String, Codable, Hashable, Sendable, CaseIterable {
    case file = "FILE"
    case link = "LINK"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.uppercased() {
        case "FILE":
            self = .file
        case "LINK":
            self = .link
        default:
            if let match = ScanKind(rawValue: raw) {
                self = match
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown ScanKind: \(raw)"
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Scan Exception

public struct ScanException: Error, Hashable, Sendable, LocalizedError {
    public let error: ScanError

    public init(_ error: ScanError) {
        self.error = error
    }

    public init(error: ScanError) {
        self.error = error
    }

    public var errorDescription: String? {
        error.rawValue
    }
}

// MARK: - Date Helpers for DTO Encoding/Decoding

private enum ScanDateHelper {
    static func decodeDate(from container: KeyedDecodingContainer<ScanResultCodingKeys>, forKey key: ScanResultCodingKeys) throws -> Date {
        if let doubleVal = try? container.decode(Double.self, forKey: key) {
            if doubleVal > 100_000_000_000 {
                return Date(timeIntervalSince1970: doubleVal / 1000.0)
            } else if doubleVal > 1_000_000_000 {
                return Date(timeIntervalSince1970: doubleVal)
            } else {
                return Date(timeIntervalSinceReferenceDate: doubleVal)
            }
        }
        if let str = try? container.decode(String.self, forKey: key) {
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: str) {
                return d
            }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) {
                return d
            }
        }
        return try container.decode(Date.self, forKey: key)
    }

    static func decodeOptionalDate(from container: KeyedDecodingContainer<ServiceResultCodingKeys>, forKey key: ServiceResultCodingKeys) throws -> Date? {
        guard container.contains(key) else { return nil }
        if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: key) {
            if doubleVal > 100_000_000_000 {
                return Date(timeIntervalSince1970: doubleVal / 1000.0)
            } else if doubleVal > 1_000_000_000 {
                return Date(timeIntervalSince1970: doubleVal)
            } else {
                return Date(timeIntervalSinceReferenceDate: doubleVal)
            }
        }
        if let str = try? container.decodeIfPresent(String.self, forKey: key) {
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: str) {
                return d
            }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) {
                return d
            }
        }
        return try container.decodeIfPresent(Date.self, forKey: key)
    }

    static func decodePendingDate(from container: KeyedDecodingContainer<PendingAnalysisCodingKeys>, forKey key: PendingAnalysisCodingKeys) throws -> Date {
        if let doubleVal = try? container.decode(Double.self, forKey: key) {
            if doubleVal > 100_000_000_000 {
                return Date(timeIntervalSince1970: doubleVal / 1000.0)
            } else if doubleVal > 1_000_000_000 {
                return Date(timeIntervalSince1970: doubleVal)
            } else {
                return Date(timeIntervalSinceReferenceDate: doubleVal)
            }
        }
        if let str = try? container.decode(String.self, forKey: key) {
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: str) {
                return d
            }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) {
                return d
            }
        }
        return try container.decode(Date.self, forKey: key)
    }
}

private enum ServiceResultCodingKeys: String, CodingKey {
    case service, verdict, flagged, engines, detail, scannedAt, reportUrl, error
}

private enum PendingAnalysisCodingKeys: String, CodingKey {
    case service, analysisId, startedAt
}

private enum ScanResultCodingKeys: String, CodingKey {
    case kind, sha256, services, checkedAt, pending
}

// MARK: - Service Result

public struct ServiceResult: Codable, Hashable, Sendable {
    public var service: ScanService
    public var verdict: ScanVerdict
    public var flagged: Int?
    public var engines: Int?
    public var detail: String?
    public var scannedAt: Date?
    public var reportUrl: String?
    public var error: ScanError?

    public init(
        service: ScanService,
        verdict: ScanVerdict,
        flagged: Int? = nil,
        engines: Int? = nil,
        detail: String? = nil,
        scannedAt: Date? = nil,
        reportUrl: String? = nil,
        error: ScanError? = nil
    ) {
        self.service = service
        self.verdict = verdict
        self.flagged = flagged
        self.engines = engines
        self.detail = detail
        self.scannedAt = scannedAt
        self.reportUrl = reportUrl
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ServiceResultCodingKeys.self)
        self.service = try container.decode(ScanService.self, forKey: .service)
        self.verdict = try container.decode(ScanVerdict.self, forKey: .verdict)
        self.flagged = try container.decodeIfPresent(Int.self, forKey: .flagged)
        self.engines = try container.decodeIfPresent(Int.self, forKey: .engines)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
        self.scannedAt = try ScanDateHelper.decodeOptionalDate(from: container, forKey: .scannedAt)
        self.reportUrl = try container.decodeIfPresent(String.self, forKey: .reportUrl)
        self.error = try container.decodeIfPresent(ScanError.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ServiceResultCodingKeys.self)
        try container.encode(service, forKey: .service)
        try container.encode(verdict, forKey: .verdict)
        try container.encodeIfPresent(flagged, forKey: .flagged)
        try container.encodeIfPresent(engines, forKey: .engines)
        try container.encodeIfPresent(detail, forKey: .detail)
        if let scannedAt = scannedAt {
            try container.encode(Int64(scannedAt.timeIntervalSince1970 * 1000), forKey: .scannedAt)
        }
        try container.encodeIfPresent(reportUrl, forKey: .reportUrl)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

// MARK: - Pending Analysis

public struct PendingAnalysis: Codable, Hashable, Sendable {
    public var service: ScanService
    public var analysisId: String
    public var startedAt: Date

    public init(service: ScanService, analysisId: String, startedAt: Date) {
        self.service = service
        self.analysisId = analysisId
        self.startedAt = startedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PendingAnalysisCodingKeys.self)
        self.service = try container.decode(ScanService.self, forKey: .service)
        self.analysisId = try container.decode(String.self, forKey: .analysisId)
        self.startedAt = try ScanDateHelper.decodePendingDate(from: container, forKey: .startedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PendingAnalysisCodingKeys.self)
        try container.encode(service, forKey: .service)
        try container.encode(analysisId, forKey: .analysisId)
        try container.encode(Int64(startedAt.timeIntervalSince1970 * 1000), forKey: .startedAt)
    }
}

// MARK: - Scan Result

public struct ScanResult: Codable, Hashable, Sendable {
    public var kind: ScanKind
    public var sha256: String?
    public var services: [ServiceResult]
    public var checkedAt: Date
    public var pending: [PendingAnalysis]

    public var verdict: ScanVerdict {
        ScanVerdicts.combine(services)
    }

    public var isRunning: Bool {
        !pending.isEmpty
    }

    public init(
        kind: ScanKind,
        sha256: String? = nil,
        services: [ServiceResult] = [],
        checkedAt: Date = Date(),
        pending: [PendingAnalysis] = []
    ) {
        self.kind = kind
        self.sha256 = sha256
        self.services = services
        self.checkedAt = checkedAt
        self.pending = pending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ScanResultCodingKeys.self)
        self.kind = try container.decode(ScanKind.self, forKey: .kind)
        self.sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        self.services = try container.decodeIfPresent([ServiceResult].self, forKey: .services) ?? []
        self.checkedAt = try ScanDateHelper.decodeDate(from: container, forKey: .checkedAt)
        self.pending = try container.decodeIfPresent([PendingAnalysis].self, forKey: .pending) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ScanResultCodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(sha256, forKey: .sha256)
        try container.encode(services, forKey: .services)
        try container.encode(Int64(checkedAt.timeIntervalSince1970 * 1000), forKey: .checkedAt)
        try container.encode(pending, forKey: .pending)
    }

    public func toJson() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func fromJson(_ json: String?) -> ScanResult? {
        guard let json = json, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = json.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(ScanResult.self, from: data)
    }
}

// MARK: - Scan Text

public enum ScanText: Sendable {
    public static let reminder = "“No flags” is not a guarantee, and “unknown” does not mean safe."
    public static let REMINDER = reminder

    public static let unknownFile = "Not known to this service yet."
    public static let UNKNOWN_FILE = unknownFile

    public nonisolated static func engines(flagged: Int, engines: Int) -> String {
        "\(flagged) of \(engines) engines flagged this"
    }

    public nonisolated static func error(service: ScanService, e: ScanError) -> String {
        switch e {
        case .badKey:
            return "The \(service.label) key isn't valid. Check it in settings or open the \(service.label) website instead."
        case .limit:
            return "Your free \(service.label) key has reached its usage limit. Try again later or open the \(service.label) website instead."
        case .offline:
            return "Couldn't reach \(service.label). Check your connection."
        case .tooBig:
            return "This file is too big to upload to \(service.label). Open the \(service.label) website instead."
        case .other:
            return "\(service.label) couldn't check this right now."
        }
    }
}

// MARK: - Scan Client Protocol

public protocol ScanClient: Sendable {
    var service: ScanService { get }
    var maxUploadBytes: Int64 { get }
    func lookupFile(sha256: String) async throws -> ServiceResult
    func lookupLink(url: String) async throws -> ServiceResult
    func upload(fileURL: URL) async throws -> PendingAnalysis
    func submitLink(url: String) async throws -> PendingAnalysis
    func poll(pending: PendingAnalysis, sha256: String?) async throws -> ServiceResult?
}

extension ScanClient {
    public func upload(fileName: String, fileURL: URL) async throws -> PendingAnalysis {
        _ = fileName
        return try await upload(fileURL: fileURL)
    }
}

// MARK: - Multipart Upload Helper

enum ScanMultipart {
    static func createTempFile(
        fileURL: URL,
        fileName: String,
        boundary: String,
        extraFields: [(name: String, value: String)] = []
    ) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmhy-upload-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
        let writeHandle = try FileHandle(forWritingTo: tempURL)

        for field in extraFields {
            var fieldHeader = "--\(boundary)\r\n"
            fieldHeader += "Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n"
            fieldHeader += "\(field.value)\r\n"
            if let d = fieldHeader.data(using: .utf8) {
                try writeHandle.write(contentsOf: d)
            }
        }

        var fileHeader = "--\(boundary)\r\n"
        fileHeader += "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n"
        fileHeader += "Content-Type: application/octet-stream\r\n\r\n"
        if let d = fileHeader.data(using: .utf8) {
            try writeHandle.write(contentsOf: d)
        }

        let readHandle = try FileHandle(forReadingFrom: fileURL)
        let bufferSize = 64 * 1024
        while let chunk = try readHandle.read(upToCount: bufferSize), !chunk.isEmpty {
            try writeHandle.write(contentsOf: chunk)
        }
        try? readHandle.close()

        let footer = "\r\n--\(boundary)--\r\n"
        if let d = footer.data(using: .utf8) {
            try writeHandle.write(contentsOf: d)
        }
        try? writeHandle.close()

        return tempURL
    }
}

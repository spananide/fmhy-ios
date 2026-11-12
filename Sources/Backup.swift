import Foundation

struct BackupFile: Codable, Equatable {
    var version: Int
    var exportedAt: Date
    var bookmarks: [String]
    var follows: [String]
    var settings: [String: String]
}

enum BackupError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidData
    case fileAccessFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Backup version \(version) is not supported by this version of FMHY."
        case .invalidData:
            return "The selected file is not a valid FMHY backup."
        case .fileAccessFailed:
            return "Could not access the backup file."
        }
    }
}

enum BackupIO {
    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: BackupFile
        do {
            file = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.invalidData
        }

        guard file.version <= 1 else {
            throw BackupError.unsupportedVersion(file.version)
        }
        return file
    }

    static func makeTempFile(_ file: BackupFile) throws -> URL {
        let data = try encode(file)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: file.exportedAt)
        let fileName = "fmhy-backup-\(dateString).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }
}

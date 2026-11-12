import Foundation
import Security

struct VTResult: Codable, Hashable, Sendable {
    var malicious: Int
    var suspicious: Int
    var harmless: Int
    var undetected: Int
    var checkedAt: Date
    var found: Bool
    var permalink: String

    var verdictText: String {
        if !found {
            return "Not known to VirusTotal"
        }
        let flagged = malicious + suspicious
        if flagged == 0 {
            return "No detections"
        } else if flagged == 1 {
            return "1 engine flags this file"
        } else {
            return "\(flagged) engines flag this file"
        }
    }
}

enum VirusTotalError: LocalizedError, Equatable {
    case invalidAPIKey
    case rateLimitExceeded
    case serverError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimitExceeded:
            return "Rate limit reached, try again in a minute"
        case .serverError(let code):
            return "VirusTotal error (HTTP \(code))"
        case .invalidResponse:
            return "Invalid response from VirusTotal"
        }
    }
}

enum VirusTotal {
    private struct ReportResponse: Decodable {
        struct DataContainer: Decodable {
            struct Attributes: Decodable {
                struct Stats: Decodable {
                    let malicious: Int?
                    let suspicious: Int?
                    let harmless: Int?
                    let undetected: Int?
                }
                let last_analysis_stats: Stats?
            }
            let attributes: Attributes?
        }
        let data: DataContainer?
    }

    static func parseFileReport(_ data: Data, sha256: String) -> VTResult? {
        guard let response = try? JSONDecoder().decode(ReportResponse.self, from: data),
              let stats = response.data?.attributes?.last_analysis_stats,
              let malicious = stats.malicious,
              let suspicious = stats.suspicious,
              let harmless = stats.harmless,
              let undetected = stats.undetected else {
            return nil
        }

        return VTResult(
            malicious: malicious,
            suspicious: suspicious,
            harmless: harmless,
            undetected: undetected,
            checkedAt: Date(),
            found: true,
            permalink: "https://www.virustotal.com/gui/file/\(sha256)"
        )
    }

    static func lookup(sha256: String, apiKey: String) async throws -> VTResult {
        guard let url = URL(string: "https://www.virustotal.com/api/v3/files/\(sha256)") else {
            throw VirusTotalError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VirusTotalError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            if let report = parseFileReport(data, sha256: sha256) {
                return report
            } else {
                throw VirusTotalError.invalidResponse
            }
        case 401:
            throw VirusTotalError.invalidAPIKey
        case 404:
            return VTResult(
                malicious: 0,
                suspicious: 0,
                harmless: 0,
                undetected: 0,
                checkedAt: Date(),
                found: false,
                permalink: "https://www.virustotal.com/gui/file/\(sha256)"
            )
        case 429:
            throw VirusTotalError.rateLimitExceeded
        default:
            throw VirusTotalError.serverError(http.statusCode)
        }
    }
}

enum KeychainStore {
    private static let service = "de.spanani.fmhy"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let value = value, let data = value.data(using: .utf8) else {
            return
        }

        var addQuery = deleteQuery
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

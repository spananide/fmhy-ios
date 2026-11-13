import Foundation

// MARK: - VirusTotal Client

final class VirusTotalClient: ScanClient, @unchecked Sendable {
    let service: ScanService = .virusTotal
    let maxUploadBytes: Int64 = 650 * 1024 * 1024

    private let apiKey: String
    private let session: URLSession
    private let rateLimiter = RateLimiter()

    private actor RateLimiter {
        private var nextAllowedTime: Date = .distantPast
        private let interval: TimeInterval = 15.0

        func wait() async throws {
            let now = Date()
            let target = max(now, nextAllowedTime)
            nextAllowedTime = target.addingTimeInterval(interval)
            let delay = target.timeIntervalSince(now)
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private func newRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func lookupFile(sha256: String) async throws -> ServiceResult {
        let reportUrl = ScanLinks.fileReport(service: .virusTotal, sha256: sha256)
        do {
            try await rateLimiter.wait()
            guard let url = URL(string: "https://www.virustotal.com/api/v3/files/\(sha256)") else {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            let request = newRequest(url: url)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            if http.statusCode == 404 {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    detail: ScanText.unknownFile,
                    reportUrl: reportUrl,
                    error: nil
                )
            }

            if let error = ScanParsers.errorFor(http.statusCode) {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: error
                )
            }

            return ScanParsers.vtReport(data, reportUrl: reportUrl) ?? ServiceResult(
                service: .virusTotal,
                verdict: .unknown,
                reportUrl: reportUrl,
                error: .other
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ServiceResult(
                service: .virusTotal,
                verdict: .unknown,
                reportUrl: reportUrl,
                error: .offline
            )
        }
    }

    func lookupLink(url: String) async throws -> ServiceResult {
        let reportUrl = ScanLinks.linkReport(service: .virusTotal, url: url)
        do {
            try await rateLimiter.wait()
            let id = ScanLinks.vtUrlId(url)
            guard let endpoint = URL(string: "https://www.virustotal.com/api/v3/urls/\(id)") else {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            let request = newRequest(url: endpoint)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            if http.statusCode == 404 {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    detail: "Nobody has scanned this link yet.",
                    reportUrl: reportUrl,
                    error: nil
                )
            }

            if let error = ScanParsers.errorFor(http.statusCode) {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: error
                )
            }

            return ScanParsers.vtReport(data, reportUrl: reportUrl) ?? ServiceResult(
                service: .virusTotal,
                verdict: .unknown,
                reportUrl: reportUrl,
                error: .other
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ServiceResult(
                service: .virusTotal,
                verdict: .unknown,
                reportUrl: reportUrl,
                error: .offline
            )
        }
    }

    func submitLink(url: String) async throws -> PendingAnalysis {
        do {
            try await rateLimiter.wait()
            guard let endpoint = URL(string: "https://www.virustotal.com/api/v3/urls") else {
                throw ScanException(.other)
            }

            var request = newRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "url", value: url)]
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ScanException(.other)
            }

            if let error = ScanParsers.errorFor(http.statusCode) {
                throw ScanException(error)
            }

            guard let analysisId = ScanParsers.vtAnalysisId(data) else {
                throw ScanException(.other)
            }

            return PendingAnalysis(service: .virusTotal, analysisId: analysisId, startedAt: Date())
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ScanException {
            throw error
        } catch is URLError {
            throw ScanException(.offline)
        } catch {
            throw ScanException(.other)
        }
    }

    func upload(fileURL: URL) async throws -> PendingAnalysis {
        let size: Int64
        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let s = values.fileSize {
            size = Int64(s)
        } else if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path), let s = attrs[.size] as? NSNumber {
            size = s.int64Value
        } else {
            size = 0
        }

        if size > maxUploadBytes {
            throw ScanException(.tooBig)
        }

        do {
            let uploadTargetString: String
            if size <= 32 * 1024 * 1024 {
                uploadTargetString = "https://www.virustotal.com/api/v3/files"
            } else {
                try await rateLimiter.wait()
                guard let getUrlEndpoint = URL(string: "https://www.virustotal.com/api/v3/files/upload_url") else {
                    throw ScanException(.other)
                }

                let getReq = newRequest(url: getUrlEndpoint)
                let (urlData, urlResp) = try await session.data(for: getReq)
                guard let http = urlResp as? HTTPURLResponse else {
                    throw ScanException(.other)
                }
                if let err = ScanParsers.errorFor(http.statusCode) {
                    throw ScanException(err)
                }
                guard let parsedUrl = ScanParsers.vtUploadUrl(urlData) else {
                    throw ScanException(.other)
                }
                uploadTargetString = parsedUrl
            }

            guard let uploadURL = URL(string: uploadTargetString) else {
                throw ScanException(.other)
            }

            let boundary = "Boundary-\(UUID().uuidString)"
            let tempURL = try ScanMultipart.createTempFile(
                fileURL: fileURL,
                fileName: fileURL.lastPathComponent,
                boundary: boundary
            )
            defer { try? FileManager.default.removeItem(at: tempURL) }

            try await rateLimiter.wait()
            var postReq = newRequest(url: uploadURL)
            postReq.httpMethod = "POST"
            postReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            let (postData, postResp) = try await session.upload(for: postReq, fromFile: tempURL)
            guard let http = postResp as? HTTPURLResponse else {
                throw ScanException(.other)
            }
            if let err = ScanParsers.errorFor(http.statusCode) {
                throw ScanException(err)
            }
            guard let analysisId = ScanParsers.vtAnalysisId(postData) else {
                throw ScanException(.other)
            }

            return PendingAnalysis(service: .virusTotal, analysisId: analysisId, startedAt: Date())
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ScanException {
            throw error
        } catch is URLError {
            throw ScanException(.offline)
        } catch {
            throw ScanException(.other)
        }
    }

    func poll(pending: PendingAnalysis, sha256: String?) async throws -> ServiceResult? {
        let reportUrl = sha256.map { ScanLinks.fileReport(service: .virusTotal, sha256: $0) }
            ?? "https://www.virustotal.com/gui/home/upload"
        do {
            try await rateLimiter.wait()
            guard let url = URL(string: "https://www.virustotal.com/api/v3/analyses/\(pending.analysisId)") else {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            let request = newRequest(url: url)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            if let error = ScanParsers.errorFor(http.statusCode) {
                return ServiceResult(
                    service: .virusTotal,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: error
                )
            }

            return ScanParsers.vtAnalysis(data, reportUrl: reportUrl)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ServiceResult(
                service: .virusTotal,
                verdict: .unknown,
                reportUrl: reportUrl,
                error: .offline
            )
        }
    }
}

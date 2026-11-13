import Foundation

// MARK: - Hybrid Analysis Client

final class HybridAnalysisClient: ScanClient, @unchecked Sendable {
    let service: ScanService = .hybridAnalysis
    let maxUploadBytes: Int64 = 100 * 1024 * 1024

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private func newRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "api-key")
        request.setValue("Falcon Sandbox", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func lookupFile(sha256: String) async throws -> ServiceResult {
        let reportUrl = ScanLinks.fileReport(service: .hybridAnalysis, sha256: sha256)
        do {
            guard let url = URL(string: "https://hybrid-analysis.com/api/v2/overview/\(sha256)") else {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            let request = newRequest(url: url)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            if http.statusCode == 404 {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    detail: ScanText.unknownFile,
                    reportUrl: reportUrl,
                    error: nil
                )
            }

            if let error = ScanParsers.errorFor(http.statusCode) {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: error
                )
            }

            return ScanParsers.haOverview(data, reportUrl: reportUrl) ?? ServiceResult(
                service: .hybridAnalysis,
                verdict: .unknown,
                reportUrl: reportUrl,
                error: .other
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ServiceResult(
                service: .hybridAnalysis,
                verdict: .unknown,
                reportUrl: reportUrl,
                error: .offline
            )
        }
    }

    func lookupLink(url: String) async throws -> ServiceResult {
        let reportUrl = ScanLinks.linkReport(service: .hybridAnalysis, url: url)
        do {
            guard let endpoint = URL(string: "https://hybrid-analysis.com/api/v2/quick-scan/url") else {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            var postRequest = newRequest(url: endpoint)
            postRequest.httpMethod = "POST"
            postRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "scan_type", value: "all")
            ]
            postRequest.httpBody = components.percentEncodedQuery?.data(using: .utf8)

            let (data, response) = try await session.data(for: postRequest)
            guard let http = response as? HTTPURLResponse else {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            if let error = ScanParsers.errorFor(http.statusCode) {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: error
                )
            }

            guard let scanId = ScanParsers.haQuickScanId(data) else {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            let startTime = Date()
            while Date().timeIntervalSince(startTime) < 60.0 {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                guard let pollUrl = URL(string: "https://hybrid-analysis.com/api/v2/quick-scan/\(scanId)") else {
                    break
                }

                let pollReq = newRequest(url: pollUrl)
                let (pollData, pollResp) = try await session.data(for: pollReq)
                guard let pollHttp = pollResp as? HTTPURLResponse else {
                    break
                }

                if let error = ScanParsers.errorFor(pollHttp.statusCode) {
                    return ServiceResult(
                        service: .hybridAnalysis,
                        verdict: .unknown,
                        reportUrl: reportUrl,
                        error: error
                    )
                }

                if let result = ScanParsers.haQuickScan(pollData, reportUrl: reportUrl) {
                    return result
                }
            }

            return ServiceResult(
                service: .hybridAnalysis,
                verdict: .unknown,
                detail: "Still being checked. Try again in a few minutes.",
                reportUrl: reportUrl,
                error: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ServiceResult(
                service: .hybridAnalysis,
                verdict: .unknown,
                reportUrl: reportUrl,
                error: .offline
            )
        }
    }

    func submitLink(url: String) async throws -> PendingAnalysis {
        _ = url
        throw ScanException(.other)
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
            guard let endpoint = URL(string: "https://hybrid-analysis.com/api/v2/quick-scan/file") else {
                throw ScanException(.other)
            }

            let boundary = "Boundary-\(UUID().uuidString)"
            let tempURL = try ScanMultipart.createTempFile(
                fileURL: fileURL,
                fileName: fileURL.lastPathComponent,
                boundary: boundary,
                extraFields: [(name: "scan_type", value: "all")]
            )
            defer { try? FileManager.default.removeItem(at: tempURL) }

            var postReq = newRequest(url: endpoint)
            postReq.httpMethod = "POST"
            postReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            let (postData, postResp) = try await session.upload(for: postReq, fromFile: tempURL)
            guard let http = postResp as? HTTPURLResponse else {
                throw ScanException(.other)
            }
            if let err = ScanParsers.errorFor(http.statusCode) {
                throw ScanException(err)
            }
            guard let analysisId = ScanParsers.haQuickScanId(postData) else {
                throw ScanException(.other)
            }

            return PendingAnalysis(service: .hybridAnalysis, analysisId: analysisId, startedAt: Date())
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
        let reportUrl = sha256.map { ScanLinks.fileReport(service: .hybridAnalysis, sha256: $0) }
            ?? "https://hybrid-analysis.com/"
        do {
            guard let url = URL(string: "https://hybrid-analysis.com/api/v2/quick-scan/\(pending.analysisId)") else {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            let request = newRequest(url: url)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: .other
                )
            }

            if let error = ScanParsers.errorFor(http.statusCode) {
                return ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .unknown,
                    reportUrl: reportUrl,
                    error: error
                )
            }

            let scanResult = ScanParsers.haQuickScan(data, reportUrl: reportUrl)
            if scanResult != nil, let sha = sha256 {
                let fileRes = try await lookupFile(sha256: sha)
                if fileRes.verdict != .unknown {
                    return fileRes
                }
            }
            return scanResult
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ServiceResult(
                service: .hybridAnalysis,
                verdict: .unknown,
                reportUrl: reportUrl,
                error: .offline
            )
        }
    }
}

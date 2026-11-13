import Foundation
import Combine

// MARK: - Download Checks

@MainActor
final class DownloadChecks: ObservableObject {
    let prefs: CheckPrefs
    let store: ScanStore

    init(prefs: CheckPrefs, store: ScanStore) {
        self.prefs = prefs
        self.store = store

        self.store.resumePending { [weak self] service in
            self?.client(for: service)
        }
    }

    func client(for service: ScanService) -> ScanClient? {
        guard let key = prefs.key(for: service)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        switch service {
        case .virusTotal:
            return VirusTotalClient(apiKey: key)
        case .hybridAnalysis:
            return HybridAnalysisClient(apiKey: key)
        }
    }

    // MARK: - Link Checks

    func checkLink(url: String, services: [ScanService]) async -> ScanResult {
        var results: [ServiceResult] = []
        for service in services {
            guard let c = client(for: service) else {
                results.append(failed(service: service, error: .badKey))
                continue
            }
            do {
                let r = try await c.lookupLink(url: url)
                results.append(r)
            } catch {
                results.append(failed(service: service, error: errorOf(error)))
            }
        }

        let scanResult = ScanResult(
            kind: .link,
            sha256: nil,
            services: results,
            checkedAt: Date()
        )
        store.set(scanResult, for: url)
        return scanResult
    }

    // MARK: - File Fingerprint & Checks

    func fingerprint(fileURL: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try DownloadManager.computeSHA256(for: fileURL)
        }.value
    }

    func checkFile(sha256: String, services: [ScanService]) async -> ScanResult {
        var results: [ServiceResult] = []
        for service in services {
            guard let c = client(for: service) else {
                results.append(failed(service: service, error: .badKey))
                continue
            }
            do {
                let r = try await c.lookupFile(sha256: sha256)
                results.append(r)
            } catch {
                results.append(failed(service: service, error: errorOf(error)))
            }
        }

        let scanResult = ScanResult(
            kind: .file,
            sha256: sha256,
            services: results,
            checkedAt: Date()
        )
        store.set(scanResult, for: sha256)
        return scanResult
    }

    // MARK: - Upload

    func upload(
        fileURL: URL,
        sha256: String,
        service: ScanService,
        previous: ScanResult?
    ) async -> ScanResult {
        let existingServices = previous?.services.filter { $0.service != service } ?? []
        let existingPending = previous?.pending.filter { $0.service != service } ?? []
        let kind = previous?.kind ?? .file

        guard let c = client(for: service) else {
            let errResult = failed(service: service, error: .badKey)
            let res = ScanResult(
                kind: kind,
                sha256: sha256,
                services: existingServices + [errResult],
                checkedAt: Date(),
                pending: existingPending
            )
            store.set(res, for: sha256)
            return res
        }

        do {
            let pendingAnalysis = try await c.upload(fileName: fileURL.lastPathComponent, fileURL: fileURL)
            let res = ScanResult(
                kind: kind,
                sha256: sha256,
                services: existingServices,
                checkedAt: Date(),
                pending: existingPending + [pendingAnalysis]
            )
            store.set(res, for: sha256)
            trackInBackground(res, fileName: fileURL.lastPathComponent)
            return res
        } catch {
            let errResult = ServiceResult(
                service: service,
                verdict: .unknown,
                error: errorOf(error)
            )
            let res = ScanResult(
                kind: kind,
                sha256: sha256,
                services: existingServices + [errResult],
                checkedAt: Date(),
                pending: existingPending
            )
            store.set(res, for: sha256)
            return res
        }
    }

    // MARK: - Link Submission

    func submitLink(url: String, service: ScanService) async -> ScanResult {
        let reportUrl = ScanLinks.linkReport(service: service, url: url)
        guard let c = client(for: service) else {
            let res = ScanResult(
                kind: .link,
                sha256: nil,
                services: [failed(service: service, error: .badKey)],
                checkedAt: Date()
            )
            store.set(res, for: url)
            return res
        }

        let pending: PendingAnalysis
        do {
            pending = try await c.submitLink(url: url)
        } catch {
            let res = ScanResult(
                kind: .link,
                sha256: nil,
                services: [failed(service: service, error: errorOf(error))],
                checkedAt: Date()
            )
            store.set(res, for: url)
            return res
        }

        let initial = ScanResult(
            kind: .link,
            sha256: nil,
            services: [],
            checkedAt: Date(),
            pending: [pending]
        )
        store.set(initial, for: url)

        var done = await awaitPending(initial, pollEvery: 5.0)
        for i in 0..<done.services.count {
            if done.services[i].reportUrl == nil {
                done.services[i].reportUrl = reportUrl
            }
        }
        store.set(done, for: url)
        return done
    }

    // MARK: - Polling Pending Analyses

    func awaitPending(_ result: ScanResult, pollEvery: TimeInterval = 30.0) async -> ScanResult {
        let maxWait: TimeInterval = 20.0 * 60.0
        let start = Date()
        var current = result

        while !current.pending.isEmpty {
            var remainingPending: [PendingAnalysis] = []
            var updatedServices = current.services

            for pending in current.pending {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= maxWait {
                    updatedServices.removeAll { $0.service == pending.service }
                    updatedServices.append(
                        ServiceResult(
                            service: pending.service,
                            verdict: .unknown,
                            detail: "Analysis is taking longer than usual. Check again later.",
                            reportUrl: current.sha256.map { ScanLinks.fileReport(service: pending.service, sha256: $0) },
                            error: nil
                        )
                    )
                } else if let c = client(for: pending.service) {
                    do {
                        if let pollResult = try await c.poll(pending: pending, sha256: current.sha256) {
                            updatedServices.removeAll { $0.service == pending.service }
                            updatedServices.append(pollResult)
                        } else {
                            remainingPending.append(pending)
                        }
                    } catch {
                        updatedServices.removeAll { $0.service == pending.service }
                        updatedServices.append(failed(service: pending.service, error: errorOf(error)))
                    }
                } else {
                    updatedServices.removeAll { $0.service == pending.service }
                    updatedServices.append(failed(service: pending.service, error: .badKey))
                }
            }

            current.services = updatedServices
            current.checkedAt = Date()
            current.pending = remainingPending

            if !current.pending.isEmpty {
                if Date().timeIntervalSince(start) >= maxWait {
                    continue
                }
                try? await Task.sleep(nanoseconds: UInt64(pollEvery * 1_000_000_000))
            }
        }
        return current
    }

    // MARK: - Background Tracking

    func trackInBackground(_ result: ScanResult, fileName: String?) {
        Task { [weak self] in
            guard let self = self else { return }
            let finalResult = await self.awaitPending(result)
            let key = finalResult.sha256 ?? fileName ?? "scan"
            self.store.set(finalResult, for: key)

            let title = (finalResult.kind == .file)
                ? "Analysis finished"
                : "Link scan finished"
            let name = fileName ?? "File"
            let body = "\(name): \(finalResult.verdict.label)"
            Notifier.postScanFinished(title: title, body: body)
        }
    }

    // MARK: - Private Helpers

    private func errorOf(_ error: Error) -> ScanError {
        if let scanEx = error as? ScanException {
            return scanEx.error
        }
        return .other
    }

    private func failed(service: ScanService, error: ScanError) -> ServiceResult {
        ServiceResult(service: service, verdict: .unknown, error: error)
    }
}

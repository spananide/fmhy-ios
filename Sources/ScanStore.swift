import Foundation

// MARK: - Scan Store

@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var results: [String: ScanResult] = [:]

    private let fileURL: URL
    private var activeTasks: [String: Task<Void, Never>] = [:]

    init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = appSupport.appendingPathComponent("scans.json")
        }
        load()
    }

    func result(for key: String) -> ScanResult? {
        results[key]
    }

    func set(_ result: ScanResult, for key: String) {
        results[key] = result
        save()
    }

    func remove(_ key: String) {
        if let current = results[key] {
            for p in current.pending {
                activeTasks[p.analysisId]?.cancel()
                activeTasks.removeValue(forKey: p.analysisId)
            }
        }
        results.removeValue(forKey: key)
        save()
    }

    func resumePending(clientFor: @escaping (ScanService) -> ScanClient?) {
        for (key, scanResult) in results {
            guard scanResult.isRunning else { continue }
            for pending in scanResult.pending {
                guard activeTasks[pending.analysisId] == nil else { continue }
                guard let client = clientFor(pending.service) else { continue }

                let interval: TimeInterval
                let timeout: TimeInterval = 20.0 * 60.0

                switch (pending.service, scanResult.kind) {
                case (.virusTotal, .file):
                    interval = 30.0
                case (.virusTotal, .link):
                    interval = 5.0
                case (.hybridAnalysis, _):
                    interval = 5.0
                }

                let task = Task { [weak self] in
                    var elapsed = Date().timeIntervalSince(pending.startedAt)
                    var finishedResult: ServiceResult?

                    while elapsed < timeout {
                        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                        if Task.isCancelled { return }

                        do {
                            if let res = try await client.poll(pending: pending, sha256: scanResult.sha256) {
                                finishedResult = res
                                break
                            }
                        } catch {
                            if let scanEx = error as? ScanException {
                                finishedResult = ServiceResult(
                                    service: pending.service,
                                    verdict: .unknown,
                                    reportUrl: scanResult.sha256.map { ScanLinks.fileReport(service: pending.service, sha256: $0) },
                                    error: scanEx.error
                                )
                                break
                            }
                        }

                        elapsed = Date().timeIntervalSince(pending.startedAt)
                    }

                    if finishedResult == nil && elapsed >= timeout {
                        finishedResult = ServiceResult(
                            service: pending.service,
                            verdict: .unknown,
                            detail: "Scan timed out",
                            reportUrl: scanResult.sha256.map { ScanLinks.fileReport(service: pending.service, sha256: $0) },
                            error: nil
                        )
                    }

                    if let finalResult = finishedResult {
                        await self?.handleAnalysisFinished(key: key, pending: pending, serviceResult: finalResult)
                    } else {
                        await self?.removeActiveTask(pending.analysisId)
                    }
                }
                activeTasks[pending.analysisId] = task
            }
        }
    }

    // MARK: - Private Methods

    private func handleAnalysisFinished(key: String, pending: PendingAnalysis, serviceResult: ServiceResult) {
        activeTasks.removeValue(forKey: pending.analysisId)

        guard var current = results[key] else { return }
        current.pending.removeAll { $0.analysisId == pending.analysisId }
        if let idx = current.services.firstIndex(where: { $0.service == pending.service }) {
            current.services[idx] = serviceResult
        } else {
            current.services.append(serviceResult)
        }
        current.checkedAt = Date()
        results[key] = current
        save()

        let title: String
        if current.kind == .file {
            title = "Scan finished: \(pending.service.label)"
        } else {
            title = "Link scan finished: \(pending.service.label)"
        }

        let body: String
        if let flagged = serviceResult.flagged, let engines = serviceResult.engines {
            body = "\(serviceResult.verdict.label) — \(ScanText.engines(flagged: flagged, engines: engines))"
        } else if let detail = serviceResult.detail {
            body = "\(serviceResult.verdict.label): \(detail)"
        } else if let error = serviceResult.error {
            body = ScanText.error(service: pending.service, e: error)
        } else {
            body = serviceResult.verdict.label
        }

        Notifier.postScanFinished(title: title, body: body)
    }

    private func removeActiveTask(_ analysisId: String) {
        activeTasks.removeValue(forKey: analysisId)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([String: ScanResult].self, from: data) {
            self.results = decoded
        }
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(results) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

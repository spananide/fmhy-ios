import Foundation
import WebKit
import CryptoKit
import Combine

enum DownloadState: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case cancelled
    case checking
    case awaitingDecision
}

struct DownloadItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sourceURL: String
    var fileName: String
    var state: DownloadState
    var bytesReceived: Int64
    var bytesTotal: Int64 // -1 unknown
    var relativePath: String? // inside Documents, e.g. "Downloads/file.zip"
    var startedAt: Date
    var errorMessage: String?
    var sha256: String?
    var check: ScanResult?
    var vt: VTResult?
    var isRisky: Bool
    var riskyConfirmed: Bool

    init(
        id: UUID = UUID(),
        sourceURL: String,
        fileName: String,
        state: DownloadState = .downloading,
        bytesReceived: Int64 = 0,
        bytesTotal: Int64 = -1,
        relativePath: String? = nil,
        startedAt: Date = Date(),
        errorMessage: String? = nil,
        sha256: String? = nil,
        check: ScanResult? = nil,
        vt: VTResult? = nil,
        isRisky: Bool = false,
        riskyConfirmed: Bool = false
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.state = state
        self.bytesReceived = bytesReceived
        self.bytesTotal = bytesTotal
        self.relativePath = relativePath
        self.startedAt = startedAt
        self.errorMessage = errorMessage
        self.sha256 = sha256
        self.check = check
        self.vt = vt
        self.isRisky = isRisky
        self.riskyConfirmed = riskyConfirmed
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    @Published var keyPromptItem: UUID?

    var checks: DownloadChecks?

    var activeCount: Int {
        items.filter { $0.state == .downloading || $0.state == .queued || $0.state == .checking }.count
    }

    private var activeWebDownloads: [UUID: WKDownload] = [:]
    private var webDelegates: [UUID: WebDownloadDelegate] = [:]
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    private var taskToItemId: [Int: UUID] = [:]
    private var resumeDataInMemory: [UUID: Data] = [:]

    private var session: URLSession!
    private var sessionCoordinator: URLDownloadCoordinator!

    private static let riskyExtensions: Set<String> = [
        "ipa", "exe", "msi", "apk", "dmg", "pkg", "bat", "cmd", "scr", "jar",
        "deb", "rpm", "appimage", "sh", "ps1", "vbs", "js", "com", "app", "iso"
    ]

    var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Downloads", isDirectory: true)
    }

    private var persistenceURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("downloads.json")
    }

    private var resumeDataDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ResumeData", isDirectory: true)
    }

    override init() {
        super.init()

        // Create required directories
        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: resumeDataDirectory, withIntermediateDirectories: true)

        // Set up URLSession
        let coordinator = URLDownloadCoordinator(manager: self)
        self.sessionCoordinator = coordinator
        self.session = URLSession(configuration: .default, delegate: coordinator, delegateQueue: nil)

        // Load items from persistence
        loadPersistedItems()
    }

    // MARK: - Persistence

    private func loadPersistedItems() {
        guard let data = try? Data(contentsOf: persistenceURL),
              var loadedItems = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return
        }

        for i in 0..<loadedItems.count {
            loadedItems[i].state = CheckPolicy.restoredState(loadedItems[i].state)
            if loadedItems[i].state == .downloading || loadedItems[i].state == .queued {
                if hasResumeData(for: loadedItems[i].id) {
                    loadedItems[i].state = .paused
                } else {
                    loadedItems[i].state = .failed
                    loadedItems[i].errorMessage = "Interrupted"
                }
            }
        }

        self.items = loadedItems
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // Silently ignore or log error
        }
    }

    private func resumeDataURL(for id: UUID) -> URL {
        resumeDataDirectory.appendingPathComponent(id.uuidString)
    }

    private func hasResumeData(for id: UUID) -> Bool {
        if resumeDataInMemory[id] != nil { return true }
        let file = resumeDataURL(for: id)
        return FileManager.default.fileExists(atPath: file.path)
    }

    private func saveResumeData(_ data: Data, for id: UUID) {
        resumeDataInMemory[id] = data
        let file = resumeDataURL(for: id)
        try? data.write(to: file, options: .atomic)
    }

    private func removeResumeData(for id: UUID) {
        resumeDataInMemory.removeValue(forKey: id)
        let file = resumeDataURL(for: id)
        try? FileManager.default.removeItem(at: file)
    }

    private func getResumeData(for id: UUID) -> Data? {
        if let data = resumeDataInMemory[id] {
            return data
        }
        let file = resumeDataURL(for: id)
        return try? Data(contentsOf: file)
    }

    // MARK: - Common API

    func fileURL(for item: DownloadItem) -> URL? {
        guard let rel = item.relativePath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(rel)
    }

    func confirmRisky(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].riskyConfirmed = true
        save()
    }

    func setVT(_ result: VTResult?, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].vt = result
        save()
    }

    func delete(_ item: DownloadItem) {
        cancel(item)

        if let url = fileURL(for: item) {
            try? FileManager.default.removeItem(at: url)
        }

        removeResumeData(for: item.id)
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearFinished() {
        items.removeAll { $0.state == .completed || $0.state == .failed || $0.state == .cancelled }
        save()
    }

    func keepAfterCheck(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if items[idx].state == .awaitingDecision {
            items[idx].state = .completed
            save()
        }
    }

    func checkItem(_ id: UUID, services: [ScanService]) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let wasAwaiting = (items[idx].state == .awaitingDecision)
        items[idx].state = .checking
        save()
        Task { [weak self] in
            await self?.performCheckAndTransition(
                for: id,
                services: services,
                targetState: wasAwaiting ? .awaitingDecision : .completed
            )
        }
    }

    func uploadItem(_ id: UUID, service: ScanService) {
        guard let item = items.first(where: { $0.id == id }),
              let fileURL = fileURL(for: item),
              FileManager.default.fileExists(atPath: fileURL.path),
              let checks = checks else {
            return
        }

        Task { [weak self] in
            var sha = item.sha256
            if sha == nil {
                sha = try? await checks.fingerprint(fileURL: fileURL)
                if let sha = sha {
                    await MainActor.run {
                        self?.updateSHA256(sha, for: id)
                    }
                }
            }
            guard let sha256 = sha else { return }

            let updated = await checks.upload(fileURL: fileURL, sha256: sha256, service: service, previous: item.check)
            await MainActor.run { [weak self] in
                guard let self = self, let idx = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[idx].check = updated
                self.save()
            }
        }
    }

    func checkVirusTotal(_ id: UUID) async {
        await performCheckAndTransition(for: id, services: [.virusTotal], targetState: nil)
    }

    private func performCheckAndTransition(
        for id: UUID,
        services: [ScanService],
        targetState: DownloadState?
    ) async {
        guard let item = items.first(where: { $0.id == id }),
              let fileURL = fileURL(for: item),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            if let targetState = targetState, let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].state = targetState
                save()
            }
            return
        }

        var sha = item.sha256
        if sha == nil {
            do {
                sha = try await checks?.fingerprint(fileURL: fileURL)
                    ?? (try await Task.detached(priority: .userInitiated) {
                        try Self.computeSHA256(for: fileURL)
                    }.value)
                if let sha = sha {
                    updateSHA256(sha, for: id)
                }
            } catch {
                setErrorMessage("Failed to hash file: \(error.localizedDescription)", for: id)
                if let targetState = targetState, let idx = items.firstIndex(where: { $0.id == id }) {
                    items[idx].state = targetState
                    save()
                }
                return
            }
        }

        guard let sha256 = sha else {
            if let targetState = targetState, let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].state = targetState
                save()
            }
            return
        }

        if let checks = checks {
            let scanResult = await checks.checkFile(sha256: sha256, services: services)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].check = scanResult
                items[idx].errorMessage = nil
                if let targetState = targetState {
                    items[idx].state = targetState
                }
                save()
            }
            checks.store.set(scanResult, for: sha256)
        } else {
            if let targetState = targetState, let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].state = targetState
                save()
            }
        }
    }

    private func runAfterDownloadPolicy(for itemId: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        let fileName = items[idx].fileName
        let readyServices = checks?.prefs.readyServices ?? []
        let holdPref = checks?.prefs.hold ?? false
        let autoRiskyPref = checks?.prefs.autoRisky ?? true
        let keyPromptShown = checks?.prefs.keyPromptShown ?? false

        let decision = CheckPolicy.afterDownload(
            fileName: fileName,
            readyCount: readyServices.count,
            hold: holdPref,
            autoCheckRisky: autoRiskyPref,
            keyPromptShown: keyPromptShown
        )

        if decision.keyPrompt {
            keyPromptItem = itemId
        }

        if decision.hold {
            items[idx].state = .checking
            save()
            if decision.checkNow {
                Task { [weak self] in
                    await self?.performCheckAndTransition(
                        for: itemId,
                        services: readyServices,
                        targetState: .awaitingDecision
                    )
                }
            } else {
                items[idx].state = .awaitingDecision
                save()
                startBackgroundHash(for: itemId)
            }
        } else {
            items[idx].state = .completed
            save()
            if decision.checkNow {
                Task { [weak self] in
                    await self?.performCheckAndTransition(
                        for: itemId,
                        services: readyServices,
                        targetState: nil
                    )
                }
            } else {
                startBackgroundHash(for: itemId)
            }
        }
    }

    private func setErrorMessage(_ message: String, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].errorMessage = message
        save()
    }

    // MARK: - Browser Downloads (WKDownload)

    func adopt(_ download: WKDownload, suggestedFilename: String?, sourceURL: URL?) {
        let rawName: String
        if let s = suggestedFilename, !s.isEmpty {
            rawName = s
        } else if let u = sourceURL, !u.lastPathComponent.isEmpty {
            rawName = u.lastPathComponent
        } else {
            rawName = "download"
        }
        let cleanName = Self.sanitizedFileName(rawName)
        let item = DownloadItem(
            sourceURL: sourceURL?.absoluteString ?? download.originalRequest?.url?.absoluteString ?? "",
            fileName: cleanName,
            state: .downloading,
            bytesReceived: 0,
            bytesTotal: -1,
            relativePath: nil,
            startedAt: Date(),
            errorMessage: nil,
            sha256: nil,
            vt: nil,
            isRisky: Self.isRisky(fileName: cleanName),
            riskyConfirmed: false
        )
        items.insert(item, at: 0)
        save()

        activeWebDownloads[item.id] = download
        let delegate = WebDownloadDelegate(
            manager: self,
            itemId: item.id,
            initialSuggestedFilename: suggestedFilename,
            sourceURL: sourceURL
        )
        webDelegates[item.id] = delegate
        download.delegate = delegate
    }

    func prepareDestination(for itemId: UUID, suggestedName: String) -> URL {
        let folder = downloadsDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let unique = Self.uniqueFileName(suggestedName, existing: existing)
        let destURL = folder.appendingPathComponent(unique)

        if let idx = items.firstIndex(where: { $0.id == itemId }) {
            items[idx].fileName = unique
            items[idx].relativePath = "Downloads/\(unique)"
            items[idx].isRisky = Self.isRisky(fileName: unique)
            save()
        }
        return destURL
    }

    func updateProgress(for itemId: UUID, received: Int64, total: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].bytesReceived = received
        items[idx].bytesTotal = total
    }

    func handleDownloadDidFinish(for itemId: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }

        if let url = fileURL(for: items[idx]),
           let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attr[.size] as? Int64 {
            items[idx].bytesReceived = size
            if items[idx].bytesTotal <= 0 {
                items[idx].bytesTotal = size
            }
        }

        items[idx].isRisky = Self.isRisky(fileName: items[idx].fileName)

        activeWebDownloads.removeValue(forKey: itemId)
        webDelegates.removeValue(forKey: itemId)
        removeResumeData(for: itemId)

        runAfterDownloadPolicy(for: itemId)
    }

    func handleDownloadDidFail(for itemId: UUID, error: Error, resumeData: Data?) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }

        if let resumeData = resumeData {
            saveResumeData(resumeData, for: itemId)
        }

        if items[idx].state == .paused {
            activeWebDownloads.removeValue(forKey: itemId)
            webDelegates.removeValue(forKey: itemId)
            return
        }

        let nsError = error as NSError
        let isCancelled = (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) || items[idx].state == .cancelled

        if isCancelled {
            items[idx].state = .cancelled
        } else {
            items[idx].state = .failed
            items[idx].errorMessage = error.localizedDescription
        }
        save()

        activeWebDownloads.removeValue(forKey: itemId)
        webDelegates.removeValue(forKey: itemId)
    }

    // MARK: - URL Downloads (URLSession)

    func start(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return
        }
        let rawName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let cleanName = Self.sanitizedFileName(rawName)
        let item = DownloadItem(
            sourceURL: url.absoluteString,
            fileName: cleanName,
            state: .downloading,
            bytesReceived: 0,
            bytesTotal: -1,
            relativePath: nil,
            startedAt: Date(),
            errorMessage: nil,
            sha256: nil,
            vt: nil,
            isRisky: Self.isRisky(fileName: cleanName),
            riskyConfirmed: false
        )
        items.insert(item, at: 0)
        save()

        let task = session.downloadTask(with: url)
        activeTasks[item.id] = task
        taskToItemId[task.taskIdentifier] = item.id
        task.resume()
    }

    func pause(_ item: DownloadItem) {
        if let task = activeTasks[item.id] {
            task.cancel(byProducingResumeData: { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let data = data {
                        self.saveResumeData(data, for: item.id)
                    }
                    if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[idx].state = .paused
                        self.save()
                    }
                    self.activeTasks.removeValue(forKey: item.id)
                }
            })
        } else if let download = activeWebDownloads[item.id] {
            download.cancel { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let data = data {
                        self.saveResumeData(data, for: item.id)
                    }
                    if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[idx].state = .paused
                        self.save()
                    }
                    self.activeWebDownloads.removeValue(forKey: item.id)
                }
            }
        }
    }

    func resume(_ item: DownloadItem) {
        guard item.state == .paused else { return }
        if let data = getResumeData(for: item.id) {
            removeResumeData(for: item.id)
            let task = session.downloadTask(withResumeData: data)
            activeTasks[item.id] = task
            taskToItemId[task.taskIdentifier] = item.id
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].state = .downloading
                items[idx].errorMessage = nil
                save()
            }
            task.resume()
        } else if let url = URL(string: item.sourceURL),
                  url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" {
            let task = session.downloadTask(with: url)
            activeTasks[item.id] = task
            taskToItemId[task.taskIdentifier] = item.id
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].state = .downloading
                items[idx].errorMessage = nil
                save()
            }
            task.resume()
        }
    }

    func cancel(_ item: DownloadItem) {
        if let task = activeTasks[item.id] {
            task.cancel()
            activeTasks.removeValue(forKey: item.id)
        }
        if let download = activeWebDownloads[item.id] {
            download.cancel { _ in }
            activeWebDownloads.removeValue(forKey: item.id)
        }
        removeResumeData(for: item.id)
        webDelegates.removeValue(forKey: item.id)

        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].state = .cancelled
            save()
        }
    }

    func retry(_ item: DownloadItem) {
        guard let url = URL(string: item.sourceURL),
              url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" else {
            return
        }
        cancel(item)

        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].state = .downloading
            items[idx].errorMessage = nil
            items[idx].bytesReceived = 0
            items[idx].bytesTotal = -1
            save()
        }

        let task = session.downloadTask(with: url)
        activeTasks[item.id] = task
        taskToItemId[task.taskIdentifier] = item.id
        task.resume()
    }

    nonisolated func syncPrepareAndMove(from tempURL: URL, suggestedName: String, taskId: Int) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let unique = DownloadManager.uniqueFileName(suggestedName, existing: existing)
        let destURL = folder.appendingPathComponent(unique)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return destURL
    }

    func handleURLTaskFinished(taskId: Int, destinationURL: URL) {
        guard let itemId = taskToItemId[taskId],
              let idx = items.firstIndex(where: { $0.id == itemId }) else {
            return
        }

        let fileName = destinationURL.lastPathComponent
        let relPath = "Downloads/\(fileName)"
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? items[idx].bytesReceived

        items[idx].fileName = fileName
        items[idx].relativePath = relPath
        items[idx].bytesReceived = fileSize
        items[idx].bytesTotal = fileSize
        items[idx].isRisky = Self.isRisky(fileName: fileName)

        activeTasks.removeValue(forKey: itemId)
        taskToItemId.removeValue(forKey: taskId)
        removeResumeData(for: itemId)

        runAfterDownloadPolicy(for: itemId)
    }

    func handleURLTaskProgress(taskId: Int, received: Int64, total: Int64) {
        guard let itemId = taskToItemId[taskId],
              let idx = items.firstIndex(where: { $0.id == itemId }) else {
            return
        }
        items[idx].bytesReceived = received
        items[idx].bytesTotal = total
    }

    func handleURLTaskFailed(taskId: Int, error: Error) {
        guard let itemId = taskToItemId[taskId],
              let idx = items.firstIndex(where: { $0.id == itemId }) else {
            return
        }

        if items[idx].state == .paused {
            activeTasks.removeValue(forKey: itemId)
            taskToItemId.removeValue(forKey: taskId)
            return
        }

        let nsError = error as NSError
        let isCancelled = (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) || items[idx].state == .cancelled

        if isCancelled {
            items[idx].state = .cancelled
        } else {
            items[idx].state = .failed
            items[idx].errorMessage = error.localizedDescription
        }
        save()

        activeTasks.removeValue(forKey: itemId)
        taskToItemId.removeValue(forKey: taskId)
    }

    // MARK: - SHA-256 Computation

    private func startBackgroundHash(for itemId: UUID) {
        guard let item = items.first(where: { $0.id == itemId }),
              let url = fileURL(for: item) else {
            return
        }

        Task.detached(priority: .utility) {
            do {
                let hash = try Self.computeSHA256(for: url)
                await MainActor.run { [weak self] in
                    self?.updateSHA256(hash, for: itemId)
                }
            } catch {
                // Silently leave sha256 as nil
            }
        }
    }

    private func updateSHA256(_ hash: String, for itemId: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].sha256 = hash
        save()
    }

    nonisolated static func computeSHA256(for fileURL: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024 // 1 MB chunks
        while let data = try fileHandle.read(upToCount: chunkSize), !data.isEmpty {
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Utility Functions

    nonisolated static func isRisky(fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ext.isEmpty else { return false }
        return riskyExtensions.contains(ext)
    }

    nonisolated static func sanitizedFileName(_ name: String) -> String {
        var sanitized = ""
        for ch in name {
            if ch == "/" || ch == "\\" || ch == ":" {
                continue
            }
            if ch.isASCII && (ch.asciiValue! < 32 || ch.asciiValue! == 127) {
                continue
            }
            sanitized.append(ch)
        }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        while sanitized.hasPrefix(".") {
            if sanitized.count > 1 && sanitized.dropFirst().contains(".") {
                sanitized.removeFirst()
            } else {
                break
            }
        }

        if sanitized.isEmpty || sanitized == "." || sanitized == ".." {
            return "download"
        }

        if sanitized.hasPrefix(".") && !sanitized.dropFirst().contains(".") {
            return "download" + sanitized
        }

        return sanitized
    }

    nonisolated static func uniqueFileName(_ name: String, existing: Set<String>) -> String {
        if !existing.contains(name) {
            return name
        }

        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension

        var counter = 2
        while true {
            let candidate: String
            if ext.isEmpty {
                candidate = "\(base) (\(counter))"
            } else {
                candidate = "\(base) (\(counter)).\(ext)"
            }
            if !existing.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }
}

// MARK: - WebDownloadDelegate

private final class WebDownloadDelegate: NSObject, WKDownloadDelegate {
    private weak var manager: DownloadManager?
    private let itemId: UUID
    private let initialSuggestedFilename: String?
    private let sourceURL: URL?
    private var progressObservation: NSKeyValueObservation?
    private var lastProgressTime: Date = .distantPast

    init(manager: DownloadManager, itemId: UUID, initialSuggestedFilename: String?, sourceURL: URL?) {
        self.manager = manager
        self.itemId = itemId
        self.initialSuggestedFilename = initialSuggestedFilename
        self.sourceURL = sourceURL
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let rawName: String
        if !suggestedFilename.isEmpty {
            rawName = suggestedFilename
        } else if let initial = initialSuggestedFilename, !initial.isEmpty {
            rawName = initial
        } else if let respSuggested = response.suggestedFilename, !respSuggested.isEmpty {
            rawName = respSuggested
        } else if let last = sourceURL?.lastPathComponent, !last.isEmpty {
            rawName = last
        } else {
            rawName = "download"
        }

        let cleanName = DownloadManager.sanitizedFileName(rawName)
        setupProgress(download.progress)

        Task { @MainActor [weak manager, itemId] in
            guard let manager = manager else {
                completionHandler(nil)
                return
            }
            let destURL = manager.prepareDestination(for: itemId, suggestedName: cleanName)
            completionHandler(destURL)
        }
    }

    private func setupProgress(_ progress: Progress) {
        progressObservation = progress.observe(\.completedUnitCount) { [weak self] prog, _ in
            self?.throttleProgressUpdate(prog)
        }
    }

    private func throttleProgressUpdate(_ progress: Progress) {
        let now = Date()
        guard now.timeIntervalSince(lastProgressTime) >= 0.25 || progress.isFinished else {
            return
        }
        lastProgressTime = now
        let received = progress.completedUnitCount
        let total = progress.totalUnitCount > 0 ? progress.totalUnitCount : -1

        Task { @MainActor [weak manager, itemId] in
            manager?.updateProgress(for: itemId, received: received, total: total)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        progressObservation?.invalidate()
        progressObservation = nil
        Task { @MainActor [weak manager, itemId] in
            manager?.handleDownloadDidFinish(for: itemId)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        progressObservation?.invalidate()
        progressObservation = nil
        Task { @MainActor [weak manager, itemId] in
            manager?.handleDownloadDidFail(for: itemId, error: error, resumeData: resumeData)
        }
    }
}

// MARK: - URLDownloadCoordinator

private final class URLDownloadCoordinator: NSObject, URLSessionDownloadDelegate {
    private weak var manager: DownloadManager?
    private var lastProgressTimes: [Int: Date] = [:]

    init(manager: DownloadManager) {
        self.manager = manager
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let suggested = downloadTask.response?.suggestedFilename
            ?? downloadTask.currentRequest?.url?.lastPathComponent
            ?? "download"
        let cleanName = DownloadManager.sanitizedFileName(suggested)

        guard let manager = manager else { return }

        do {
            let destURL = try manager.syncPrepareAndMove(from: location, suggestedName: cleanName, taskId: downloadTask.taskIdentifier)
            Task { @MainActor [weak manager] in
                manager?.handleURLTaskFinished(taskId: downloadTask.taskIdentifier, destinationURL: destURL)
            }
        } catch {
            Task { @MainActor [weak manager] in
                manager?.handleURLTaskFailed(taskId: downloadTask.taskIdentifier, error: error)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        let taskId = downloadTask.taskIdentifier
        let last = lastProgressTimes[taskId] ?? .distantPast
        let isDone = (totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite)
        guard now.timeIntervalSince(last) >= 0.25 || isDone else { return }
        lastProgressTimes[taskId] = now

        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : -1
        Task { @MainActor [weak manager] in
            manager?.handleURLTaskProgress(taskId: taskId, received: totalBytesWritten, total: expected)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lastProgressTimes.removeValue(forKey: task.taskIdentifier)
        if let error = error {
            Task { @MainActor [weak manager] in
                manager?.handleURLTaskFailed(taskId: task.taskIdentifier, error: error)
            }
        }
    }
}

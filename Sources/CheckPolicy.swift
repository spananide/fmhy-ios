import Foundation

// MARK: - After Download Result

public struct AfterDownload: Equatable, Sendable {
    public let hold: Bool
    public let checkNow: Bool
    public let keyPrompt: Bool

    public init(hold: Bool, checkNow: Bool, keyPrompt: Bool) {
        self.hold = hold
        self.checkNow = checkNow
        self.keyPrompt = keyPrompt
    }
}

// MARK: - Check Policy

public enum CheckPolicy {
    public static let riskyExtensions: Set<String> = [
        "apk", "xapk", "apks", "exe", "msi", "bat", "cmd", "scr", "dmg", "pkg", "jar", "vbs", "ps1"
    ]

    public static let autoCheckExtensions: Set<String> = riskyExtensions.union([
        "sh", "py", "js", "jse", "wsf", "hta", "com", "lnk", "appimage", "deb", "rpm", "msix", "appx"
    ])

    public nonisolated static func extractExtension(_ fileNameOrUrl: String) -> String {
        let clean = fileNameOrUrl.components(separatedBy: "?").first?
            .components(separatedBy: "#").first?
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ")) ?? ""
        guard let lastDot = clean.lastIndex(of: ".") else { return "" }
        let ext = String(clean[clean.index(after: lastDot)...])
        if ext.contains("/") || ext.contains("\\") { return "" }
        return ext.lowercased()
    }

    public nonisolated static func isAutoCheckType(_ fileName: String) -> Bool {
        let ext = extractExtension(fileName)
        return autoCheckExtensions.contains(ext)
    }

    public nonisolated static func isRiskyExtension(_ fileNameOrUrl: String) -> Bool {
        let ext = extractExtension(fileNameOrUrl)
        return riskyExtensions.contains(ext)
    }

    public nonisolated static func warningMessage(host: String) -> String {
        "This file can install software. Only download it if you trust \(host)."
    }

    public nonisolated static func afterDownload(
        fileName: String,
        readyCount: Int,
        hold: Bool,
        autoCheckRisky: Bool,
        keyPromptShown: Bool
    ) -> AfterDownload {
        let ready = readyCount > 0
        let risky = isAutoCheckType(fileName)
        let checkNow = ready && (hold || (autoCheckRisky && risky))
        let keyPrompt = !ready && !keyPromptShown && ((autoCheckRisky && risky) || hold)
        return AfterDownload(hold: hold, checkNow: checkNow, keyPrompt: keyPrompt)
    }

    nonisolated static func restoredState(_ s: DownloadState) -> DownloadState {
        switch s {
        case .downloading:
            return .queued
        case .checking:
            return .awaitingDecision
        default:
            return s
        }
    }

    nonisolated static func needsExtraConfirm(_ r: ScanResult?) -> Bool {
        r?.verdict == .dangerous
    }

    nonisolated static func needsExtraConfirm(_ item: DownloadItem) -> Bool {
        needsExtraConfirm(item.check)
    }
}

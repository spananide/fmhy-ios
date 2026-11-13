import Foundation
import Combine

// MARK: - Check Preferences

@MainActor
final class CheckPrefs: ObservableObject {
    private let defaults: UserDefaults

    @Published var vtEnabled: Bool {
        didSet {
            defaults.set(vtEnabled, forKey: "check.vt.enabled")
        }
    }

    @Published var haEnabled: Bool {
        didSet {
            defaults.set(haEnabled, forKey: "check.ha.enabled")
        }
    }

    @Published var hold: Bool {
        didSet {
            defaults.set(hold, forKey: "check.hold")
        }
    }

    @Published var autoRisky: Bool {
        didSet {
            defaults.set(autoRisky, forKey: "check.autoRisky")
        }
    }

    @Published var keyPromptShown: Bool {
        didSet {
            defaults.set(keyPromptShown, forKey: "check.keyPromptShown")
        }
    }

    @Published var fmhyStatus: Bool {
        didSet {
            defaults.set(fmhyStatus, forKey: "check.fmhyStatus")
        }
    }

    @Published private var vtKey: String?
    @Published private var haKey: String?

    // Convenient aliases matching Android naming
    var holdUntilChecked: Bool {
        get { hold }
        set { hold = newValue }
    }

    var autoCheckRisky: Bool {
        get { autoRisky }
        set { autoRisky = newValue }
    }

    var virusTotalOn: Bool {
        get { vtEnabled }
        set { vtEnabled = newValue }
    }

    var hybridOn: Bool {
        get { haEnabled }
        set { haEnabled = newValue }
    }

    var virusTotalKey: String {
        vtKey ?? ""
    }

    var hybridKey: String {
        haKey ?? ""
    }

    var fmhyDownloadStatus: Bool {
        get { fmhyStatus }
        set { fmhyStatus = newValue }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            "check.vt.enabled": true,
            "check.ha.enabled": true,
            "check.hold": false,
            "check.autoRisky": true,
            "check.keyPromptShown": false,
            "check.fmhyStatus": true
        ])

        self.vtEnabled = defaults.bool(forKey: "check.vt.enabled")
        self.haEnabled = defaults.bool(forKey: "check.ha.enabled")
        self.hold = defaults.bool(forKey: "check.hold")
        self.autoRisky = defaults.bool(forKey: "check.autoRisky")
        self.keyPromptShown = defaults.bool(forKey: "check.keyPromptShown")
        self.fmhyStatus = defaults.bool(forKey: "check.fmhyStatus")

        self.vtKey = KeychainStore.get("vt.apiKey")
        self.haKey = KeychainStore.get("ha.apiKey")
    }

    var readyServices: [ScanService] {
        var services: [ScanService] = []
        if vtEnabled, let k = vtKey, !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            services.append(.virusTotal)
        }
        if haEnabled, let k = haKey, !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            services.append(.hybridAnalysis)
        }
        return services
    }

    var enabledServices: [ScanService] {
        var services: [ScanService] = []
        if vtEnabled { services.append(.virusTotal) }
        if haEnabled { services.append(.hybridAnalysis) }
        return services
    }

    func isEnabled(for service: ScanService) -> Bool {
        switch service {
        case .virusTotal:
            return vtEnabled
        case .hybridAnalysis:
            return haEnabled
        }
    }

    func setEnabled(_ enabled: Bool, for service: ScanService) {
        switch service {
        case .virusTotal:
            vtEnabled = enabled
        case .hybridAnalysis:
            haEnabled = enabled
        }
    }

    func key(for service: ScanService) -> String? {
        switch service {
        case .virusTotal:
            return vtKey
        case .hybridAnalysis:
            return haKey
        }
    }

    func maskedKey(for service: ScanService) -> String {
        guard let raw = key(for: service)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }
        let last4 = String(raw.suffix(4))
        return "••••" + last4
    }

    func setKey(_ key: String?, for service: ScanService) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalValue = (trimmed?.isEmpty == false) ? trimmed : nil
        switch service {
        case .virusTotal:
            KeychainStore.set(finalValue, for: "vt.apiKey")
            vtKey = finalValue
        case .hybridAnalysis:
            KeychainStore.set(finalValue, for: "ha.apiKey")
            haKey = finalValue
        }
    }
}

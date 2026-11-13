import Foundation
import Combine

struct SiteConfig: Codable, Equatable {
    var host: String
    var javaScript: Bool
    var popups: Bool
    var desktop: Bool
    var darkPage: Bool

    init(
        host: String,
        javaScript: Bool = true,
        popups: Bool = false,
        desktop: Bool = false,
        darkPage: Bool = false
    ) {
        self.host = host
        self.javaScript = javaScript
        self.popups = popups
        self.desktop = desktop
        self.darkPage = darkPage
    }

    var hasCustomOverrides: Bool {
        !javaScript || popups || desktop || darkPage
    }
}

@MainActor final class SiteSettingsStore: ObservableObject {
    private let storageKey = "sites.v1"
    private let userDefaults: UserDefaults

    @Published private var sites: [String: SiteConfig] = [:]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: SiteConfig].self, from: data) {
            self.sites = decoded
        }
    }

    var hosts: [String] {
        Array(sites.keys).sorted()
    }

    func config(for host: String?) -> SiteConfig {
        let norm = Self.normalizeHost(host)
        guard !norm.isEmpty else {
            return SiteConfig(host: "")
        }
        if let existing = sites[norm] {
            return existing
        }
        return SiteConfig(host: norm)
    }

    func update(_ config: SiteConfig) {
        let norm = Self.normalizeHost(config.host)
        guard !norm.isEmpty else { return }
        var updated = config
        updated.host = norm
        sites[norm] = updated
        persist()
    }

    func reset(host: String?) {
        let norm = Self.normalizeHost(host)
        guard !norm.isEmpty else { return }
        sites.removeValue(forKey: norm)
        persist()
    }

    func resetAll() {
        sites.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sites) {
            userDefaults.set(data, forKey: storageKey)
        }
    }

    nonisolated static func normalizeHost(_ host: String?) -> String {
        guard let raw = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return ""
        }
        if raw.hasPrefix("www.") {
            return String(raw.dropFirst(4))
        }
        return raw
    }
}

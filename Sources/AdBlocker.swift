import Foundation
import WebKit

@MainActor final class AdBlocker: ObservableObject {
    static let shared = AdBlocker()

    private let enabledKey = "adblock.enabled"
    private let allowlistKey = "adblock.allowlist"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            refreshControllers()
        }
    }

    @Published var allowlist: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(allowlist).sorted(), forKey: allowlistKey)
            refreshControllers()
        }
    }

    @Published private(set) var isReady = false
    private(set) var lists: [WKContentRuleList] = []

    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let cosmeticScript: WKUserScript = Self.makeCosmeticUserScript()
    private var inFlightCompileTask: Task<Int, Never>?

    static let cosmeticCSS: String = """
    #onetrust-consent-sdk,
    #CybotCookiebotDialog,
    .cookie-banner,
    .cookie-consent,
    .cc-window,
    .fc-consent-root,
    #cookie-law-info-bar,
    [id^="sp_message_container"],
    .qc-cmp2-container,
    #didomi-host,
    .truste_overlay,
    .adsbygoogle,
    ins.adsbygoogle,
    [id^="google_ads_iframe"],
    div[id^="div-gpt-ad"],
    .ad-container,
    .advert,
    .ads-banner,
    [aria-label="advertisement"],
    #cmpbox,
    .cookie-notice,
    #CookieReportsBanner,
    .ad-box,
    .ad-wrapper,
    .advertisement,
    #ad-banner,
    .sponsor-banner {
        display:none !important;
    }
    """

    init() {
        let initialEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        self.isEnabled = initialEnabled

        let initialList = UserDefaults.standard.stringArray(forKey: allowlistKey) ?? []
        self.allowlist = Set(initialList.compactMap { host in
            let norm = Self.normalizeHost(host)
            return norm.isEmpty ? nil : norm
        })
    }

    static func normalizeHost(_ host: String?) -> String {
        guard let raw = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return ""
        }
        if raw.hasPrefix("www.") {
            return String(raw.dropFirst(4))
        }
        return raw
    }

    func isAllowlisted(host: String?) -> Bool {
        guard let host = host else { return false }
        let norm = Self.normalizeHost(host)
        guard !norm.isEmpty else { return false }
        return allowlist.contains(norm)
    }

    func setAllowlisted(_ host: String, _ on: Bool) {
        let norm = Self.normalizeHost(host)
        guard !norm.isEmpty else { return }
        if on {
            allowlist.insert(norm)
        } else {
            allowlist.remove(norm)
        }
    }

    func shouldBlock(host: String?) -> Bool {
        guard isEnabled else { return false }
        return !isAllowlisted(host: host)
    }

    func compileAll() async -> Int {
        if isReady {
            return lists.count
        }
        if let inFlight = inFlightCompileTask {
            return await inFlight.value
        }
        let task = Task { @MainActor in
            await self.performCompileAll()
        }
        inFlightCompileTask = task
        let count = await task.value
        inFlightCompileTask = nil
        return count
    }

    private func performCompileAll() async -> Int {
        let bundleDir = WikiStore.bundledDataURL()
        let fileManager = FileManager.default

        var foundFiles: [(n: Int, url: URL, size: Int64)] = []

        if let contents = try? fileManager.contentsOfDirectory(
            at: bundleDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            let prefix = "blocklist-"
            let suffix = ".json"
            for fileURL in contents {
                let name = fileURL.lastPathComponent
                if name.hasPrefix(prefix) && name.hasSuffix(suffix) && name.count > prefix.count + suffix.count {
                    let numPart = name.dropFirst(prefix.count).dropLast(suffix.count)
                    if let n = Int(numPart) {
                        let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
                        let size = (attrs?[.size] as? NSNumber)?.int64Value
                            ?? Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                        foundFiles.append((n: n, url: fileURL, size: size))
                    }
                }
            }
        }

        if foundFiles.isEmpty {
            var index = 0
            while true {
                let candidate = bundleDir.appendingPathComponent("blocklist-\(index).json")
                if fileManager.fileExists(atPath: candidate.path) {
                    let attrs = try? fileManager.attributesOfItem(atPath: candidate.path)
                    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                    foundFiles.append((n: index, url: candidate, size: size))
                    index += 1
                } else {
                    break
                }
            }
        }

        foundFiles.sort { $0.n < $1.n }

        guard let store = WKContentRuleListStore.default() else {
            print("WKContentRuleListStore.default() returned nil")
            self.lists = []
            self.isReady = true
            refreshControllers()
            return 0
        }

        var activeLists: [WKContentRuleList] = []
        for file in foundFiles {
            let identifier = "fmhy-blocklist-\(file.n)-\(file.size)"

            var ruleList: WKContentRuleList? = await withCheckedContinuation { continuation in
                store.lookUpContentRuleList(forIdentifier: identifier) { list, error in
                    continuation.resume(returning: list)
                }
            }

            if ruleList == nil {
                if let jsonString = try? String(contentsOf: file.url, encoding: .utf8) {
                    ruleList = await withCheckedContinuation { continuation in
                        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: jsonString) { list, error in
                            if let error = error {
                                print("Failed to compile rule list '\(identifier)': \(error)")
                            }
                            continuation.resume(returning: list)
                        }
                    }
                } else {
                    print("Failed to read blocklist file at \(file.url.path)")
                }
            }

            if let list = ruleList {
                activeLists.append(list)
            }
        }

        let currentIdentifiers = Set(foundFiles.map { "fmhy-blocklist-\($0.n)-\($0.size)" })
        let available = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            store.getAvailableContentRuleListIdentifiers { ids in
                continuation.resume(returning: ids ?? [])
            }
        }

        for ident in available {
            if ident.hasPrefix("fmhy-blocklist-") && !currentIdentifiers.contains(ident) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    store.removeContentRuleList(forIdentifier: ident) { error in
                        if let error = error {
                            print("Failed to remove stale content rule list '\(ident)': \(error)")
                        }
                        continuation.resume()
                    }
                }
            }
        }

        self.lists = activeLists
        self.isReady = true
        refreshControllers()
        return activeLists.count
    }

    func install(in controller: WKUserContentController) {
        controllers.add(controller)
        apply(to: controller, host: nil)
    }

    func apply(to controller: WKUserContentController, host: String?) {
        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()
        if shouldBlock(host: host) {
            if isReady {
                for list in lists {
                    controller.add(list)
                }
            }
            controller.addUserScript(cosmeticScript)
        }
    }

    func refreshControllers() {
        for controller in controllers.allObjects {
            apply(to: controller, host: nil)
        }
    }

    private static func makeCosmeticUserScript() -> WKUserScript {
        let css = cosmeticCSS
        let jsonEncoded: String
        if let data = try? JSONEncoder().encode(css),
           let str = String(data: data, encoding: .utf8) {
            jsonEncoded = str
        } else {
            let escaped = css
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
            jsonEncoded = "\"\(escaped)\""
        }

        let js = """
        (function() {
            var css = \(jsonEncoded);
            var style = document.createElement('style');
            style.type = 'text/css';
            style.appendChild(document.createTextNode(css));
            (document.head || document.documentElement).appendChild(style);
        })();
        """

        return WKUserScript(
            source: js,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }
}

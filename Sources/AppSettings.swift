import SwiftUI
import Network

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case black

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .black: return "Black"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark, .black:
            return .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case purple
    case blue
    case green
    case orange
    case pink
    case red

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .purple: return "Purple"
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .pink: return "Pink"
        case .red: return "Red"
        }
    }

    var color: Color {
        switch self {
        case .purple: return Color(red: 0.65, green: 0.19, blue: 0.95)
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .red: return .red
        }
    }
}

enum TextSizeChoice: String, CaseIterable, Identifiable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .extraLarge: return .xxLarge
        }
    }
}

enum SearchEngineChoice: String, CaseIterable, Identifiable {
    case duckDuckGo
    case google
    case bing
    case brave
    case startpage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google: return "Google"
        case .bing: return "Bing"
        case .brave: return "Brave"
        case .startpage: return "Startpage"
        }
    }

    var baseURLString: String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com/?q="
        case .google: return "https://www.google.com/search?q="
        case .bing: return "https://www.bing.com/search?q="
        case .brave: return "https://search.brave.com/search?q="
        case .startpage: return "https://www.startpage.com/do/search?q="
        }
    }

    func searchURL(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: baseURLString + encoded)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: "ui.theme") }
    }

    @Published var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: "ui.accent") }
    }

    @Published var textSize: TextSizeChoice {
        didSet { defaults.set(textSize.rawValue, forKey: "ui.textSize") }
    }

    @Published var searchEngine: SearchEngineChoice {
        didSet { defaults.set(searchEngine.rawValue, forKey: "browser.searchEngine") }
    }

    @Published var openInSafari: Bool {
        didSet { defaults.set(openInSafari, forKey: "openInSafari") }
    }

    @Published var wifiOnlyRefresh: Bool {
        didSet { defaults.set(wifiOnlyRefresh, forKey: "data.wifiOnly") }
    }

    @Published var isShowingOnboarding: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let rawTheme = defaults.string(forKey: "ui.theme") ?? ""
        self.theme = AppTheme(rawValue: rawTheme) ?? .system

        let rawAccent = defaults.string(forKey: "ui.accent") ?? ""
        self.accent = AccentChoice(rawValue: rawAccent) ?? .purple

        let rawTextSize = defaults.string(forKey: "ui.textSize") ?? ""
        self.textSize = TextSizeChoice(rawValue: rawTextSize) ?? .standard

        let rawEngine = defaults.string(forKey: "browser.searchEngine") ?? ""
        self.searchEngine = SearchEngineChoice(rawValue: rawEngine) ?? .duckDuckGo

        self.openInSafari = defaults.bool(forKey: "openInSafari")
        self.wifiOnlyRefresh = defaults.bool(forKey: "data.wifiOnly")

        let isDone = defaults.bool(forKey: "onboarding.done.v1")
        let forceShow = defaults.bool(forKey: "onboarding")
        self.isShowingOnboarding = (!isDone || forceShow)
    }

    func completeOnboarding() {
        defaults.set(true, forKey: "onboarding.done.v1")
        isShowingOnboarding = false
    }

    func exportSettingsMap() -> [String: String] {
        [
            "theme": theme.rawValue,
            "accent": accent.rawValue,
            "textSize": textSize.rawValue,
            "searchEngine": searchEngine.rawValue,
            "openInSafari": String(openInSafari),
            "wifiOnly": String(wifiOnlyRefresh),
            "adblock": String(AdBlocker.shared.isEnabled)
        ]
    }

    func importSettingsMap(_ map: [String: String]) {
        if let rawTheme = map["theme"], let t = AppTheme(rawValue: rawTheme) {
            self.theme = t
        }
        if let rawAccent = map["accent"], let a = AccentChoice(rawValue: rawAccent) {
            self.accent = a
        }
        if let rawTextSize = map["textSize"], let s = TextSizeChoice(rawValue: rawTextSize) {
            self.textSize = s
        }
        if let rawEngine = map["searchEngine"], let e = SearchEngineChoice(rawValue: rawEngine) {
            self.searchEngine = e
        }
        if let safariStr = map["openInSafari"] {
            self.openInSafari = (safariStr == "true")
        }
        if let wifiStr = map["wifiOnly"] {
            self.wifiOnlyRefresh = (wifiStr == "true")
        }
        if let adblockStr = map["adblock"] {
            AdBlocker.shared.isEnabled = (adblockStr == "true")
        }
    }
}

enum NetworkPolicy {
    @MainActor
    static func allowsRefresh(wifiOnly: Bool) async -> Bool {
        guard wifiOnly else { return true }

        let isCellularOrExpensive = await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "de.spanani.fmhy.networkPolicy")

            final class State: @unchecked Sendable {
                var finished = false
                let lock = NSLock()
            }
            let state = State()

            monitor.pathUpdateHandler = { path in
                state.lock.lock()
                defer { state.lock.unlock() }
                if !state.finished {
                    state.finished = true
                    monitor.cancel()
                    continuation.resume(returning: path.isExpensive || path.isConstrained)
                }
            }

            monitor.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 1.0) {
                state.lock.lock()
                defer { state.lock.unlock() }
                if !state.finished {
                    state.finished = true
                    monitor.cancel()
                    continuation.resume(returning: false)
                }
            }
        }

        return !isCellularOrExpensive
    }
}

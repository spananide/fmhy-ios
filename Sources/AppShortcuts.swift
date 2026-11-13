import UIKit
import SwiftUI
import Combine

enum AppShortcutDestination: String {
    case search
    case saved
    case check
    case downloads
}

enum RootSheetDestination: Identifiable {
    case checkLink
    case downloads

    var id: String {
        switch self {
        case .checkLink: return "checkLink"
        case .downloads: return "downloads"
        }
    }
}

@MainActor final class AppShortcuts: ObservableObject {
    static let shared = AppShortcuts()

    @Published var activeSheet: RootSheetDestination?

    weak var hub: BrowserHub? {
        didSet {
            if let pending = pendingDestination {
                pendingDestination = nil
                _ = perform(action: pending)
            }
        }
    }

    private var pendingDestination: AppShortcutDestination?

    @discardableResult
    func handleShortcut(_ item: UIApplicationShortcutItem) -> Bool {
        guard let dest = destination(for: item.type) else {
            return false
        }
        return perform(action: dest)
    }

    nonisolated static func parseDestination(type: String) -> AppShortcutDestination? {
        if type.hasSuffix("search") || type == "search" {
            return .search
        } else if type.hasSuffix("saved") || type == "saved" {
            return .saved
        } else if type.hasSuffix("check") || type == "check" {
            return .check
        } else if type.hasSuffix("downloads") || type == "downloads" {
            return .downloads
        }
        return nil
    }

    func destination(for type: String) -> AppShortcutDestination? {
        Self.parseDestination(type: type)
    }

    func perform(action: AppShortcutDestination) -> Bool {
        switch action {
        case .search:
            if let hub = hub {
                hub.requestedTab = 1
            } else {
                pendingDestination = .search
            }
            return true
        case .saved:
            if let hub = hub {
                hub.requestedTab = 2
            } else {
                pendingDestination = .saved
            }
            return true
        case .check:
            activeSheet = .checkLink
            return true
        case .downloads:
            activeSheet = .downloads
            return true
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: connectingSceneSession.configuration.name,
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            Task { @MainActor in
                _ = AppShortcuts.shared.handleShortcut(shortcutItem)
            }
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            let handled = AppShortcuts.shared.handleShortcut(shortcutItem)
            completionHandler(handled)
        }
    }
}

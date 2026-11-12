import Foundation
import UserNotifications
import BackgroundTasks

enum Notifier {
    static let taskIdentifier = "de.spanani.fmhy.refresh"
    private static let lastNotifiedKey = "notify.lastTs.v1"

    final class SharedHolder: @unchecked Sendable {
        let changes: ChangesStore
        let follows: Follows
        let store: WikiStore

        init(changes: ChangesStore, follows: Follows, store: WikiStore) {
            self.changes = changes
            self.follows = follows
            self.store = store
        }
    }

    private(set) static var shared: SharedHolder?

    static func configure(changes: ChangesStore, follows: Follows, store: WikiStore) {
        self.shared = SharedHolder(changes: changes, follows: follows, store: store)
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    @MainActor
    static func notifyIfNeeded(changes: ChangesStore, follows: Follows, sections: [WikiSection]) {
        guard !follows.isEmpty else { return }

        let defaults = UserDefaults.standard
        let lastNotifiedTs: Int
        if let stored = defaults.object(forKey: lastNotifiedKey) as? Int {
            lastNotifiedTs = stored
        } else {
            // First run: store newest ts so nothing fires on first launch
            if let newest = changes.changes.first?.ts {
                defaults.set(newest, forKey: lastNotifiedKey)
            }
            return
        }

        let qualifying = changes.changes.filter { change in
            change.ts > lastNotifiedTs &&
            (change.kind == "added" || change.kind == "starred") &&
            follows.isFollowing(change.sectionId)
        }

        guard !qualifying.isEmpty else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let count = qualifying.count
            let title = count == 1 ? "FMHY: 1 new site" : "FMHY: \(count) new sites"

            let prefix = qualifying.prefix(3)
            let names = prefix.map { $0.name }.joined(separator: ", ")

            var sectionTitles: [String] = []
            for change in prefix {
                let secTitle = sections.first(where: { $0.id == change.sectionId })?.title ?? change.sectionId
                if !sectionTitles.contains(secTitle) {
                    sectionTitles.append(secTitle)
                }
            }
            let sectionsString = sectionTitles.joined(separator: ", ")
            let body: String
            if !sectionsString.isEmpty {
                body = "\(names) in \(sectionsString)"
            } else {
                body = names
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "fmhy-changes-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )

            try? await center.add(request)
        }

        if let newest = qualifying.map({ $0.ts }).max() {
            defaults.set(max(newest, lastNotifiedTs), forKey: lastNotifiedKey)
        }
    }

    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleBackgroundRefresh(task: refreshTask)
        }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background tasks scheduling may fail if background refresh is disabled or in simulator
        }
    }

    private static func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        let refreshTask = Task { @MainActor in
            guard let shared = shared else {
                task.setTaskCompleted(success: false)
                return
            }

            await shared.changes.refresh()
            notifyIfNeeded(
                changes: shared.changes,
                follows: shared.follows,
                sections: shared.store.sections
            )
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }
}

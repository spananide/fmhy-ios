import Foundation
import WidgetKit

@MainActor
enum WidgetBridge {
    static func sync(store: WikiStore, follows: Follows) {
        guard !store.entries.isEmpty else { return }
        let sites = sampleStarred(from: store.entries, limit: WidgetPayload.maxStarred)
        let followed = store.sections.filter { follows.isFollowing($0.id) }
        let pins = Array(followed.prefix(WidgetPayload.maxPins)).map { section in
            WidgetPin(id: section.id, title: section.title, emoji: sectionEmoji(section.id))
        }
        let payload = buildPayload(starred: sites, pins: pins, updatedAt: Date())
        WidgetStore.write(payload)
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated static func sampleStarred(from entries: [Entry], limit: Int = 60) -> [WidgetSite] {
        let starred = entries.filter { $0.tier >= 1 }
        let pool = starred.isEmpty ? entries : starred
        guard !pool.isEmpty else { return [] }

        let selected: [Entry]
        if pool.count <= limit {
            selected = pool
        } else {
            selected = Array(pool.shuffled().prefix(limit))
        }

        return selected.map { entry in
            WidgetSite(name: entry.name, url: entry.url, description: entry.description)
        }
    }

    nonisolated static func buildPayload(
        starred: [WidgetSite],
        pins: [WidgetPin],
        updatedAt: Date = Date()
    ) -> WidgetPayload {
        WidgetStore.buildPayload(starred: starred, pins: pins, updatedAt: updatedAt)
    }
}

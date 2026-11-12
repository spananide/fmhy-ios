import Foundation
import Combine

@MainActor final class Bookmarks: ObservableObject {
    @Published private(set) var ids: [String] = []
    private let storageKey = "bookmarks.v1"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.ids = decoded
        } else {
            self.ids = []
        }
    }

    func isSaved(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        save()
    }

    @discardableResult
    func merge(ids: [String]) -> Int {
        var added = 0
        for id in ids {
            if !self.ids.contains(id) {
                self.ids.append(id)
                added += 1
            }
        }
        if added > 0 {
            save()
        }
        return added
    }

    func entries(from all: [Entry]) -> [Entry] {
        guard !ids.isEmpty && !all.isEmpty else { return [] }
        let map = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { map[$0] }
    }

    func shareText(entries: [Entry]) -> String {
        entries.map { "- \($0.name) \u{2014} \($0.url)" }.joined(separator: "\n")
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(ids) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}

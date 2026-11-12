import Foundation
import Combine

@MainActor final class Follows: ObservableObject {
    @Published private(set) var sectionIds: Set<String>
    private let storageKey = "follows.v1"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.sectionIds = Set(decoded)
        } else {
            self.sectionIds = []
        }
    }

    var isEmpty: Bool {
        sectionIds.isEmpty
    }

    func isFollowing(_ id: String) -> Bool {
        sectionIds.contains(id)
    }

    func toggle(_ id: String) {
        if sectionIds.contains(id) {
            sectionIds.remove(id)
        } else {
            sectionIds.insert(id)
        }
        save()
    }

    @discardableResult
    func merge(ids: [String]) -> Int {
        var added = 0
        for id in ids {
            if !sectionIds.contains(id) {
                sectionIds.insert(id)
                added += 1
            }
        }
        if added > 0 {
            save()
        }
        return added
    }

    private func save() {
        let array = Array(sectionIds).sorted()
        if let encoded = try? JSONEncoder().encode(array) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}

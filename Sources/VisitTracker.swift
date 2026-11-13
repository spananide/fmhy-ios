import Foundation
import Combine

@MainActor final class VisitTracker: ObservableObject {
    @Published private(set) var counts: [String: Int] = [:]
    private let storageKey = "visits.v1"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let stored = userDefaults.dictionary(forKey: storageKey) as? [String: Int] {
            self.counts = stored
        } else {
            self.counts = [:]
        }
    }

    func record(sectionId: String) {
        let trimmed = sectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        counts[trimmed, default: 0] += 1
        userDefaults.set(counts, forKey: storageKey)
    }

    func topSections(limit: Int = 4) -> [String] {
        guard limit > 0 else { return [] }
        return counts
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map { $0.key }
    }
}

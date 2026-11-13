import Foundation
import Combine

@MainActor final class HomeLayoutStore: ObservableObject {
    @Published var layout: HomeLayout
    private let key = "home.layout"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let stored = userDefaults.string(forKey: key)
        self.layout = HomeLayout.decode(stored)
    }

    func set(_ newLayout: HomeLayout) {
        self.layout = newLayout
        userDefaults.set(newLayout.encode(), forKey: key)
    }

    func update(_ transform: (HomeLayout) -> HomeLayout) {
        set(transform(layout))
    }
}

import Foundation

enum HomeBlock: String, CaseIterable, Sendable {
    case search
    case newSince
    case randomPick
    case pinned
    case newInPinned
    case favourites
    case suggestions
    case sections

    var title: String {
        switch self {
        case .search:
            return "Search"
        case .newSince:
            return "New since last visit"
        case .randomPick:
            return "Random pick"
        case .pinned:
            return "Pinned categories"
        case .newInPinned:
            return "New in pinned categories"
        case .favourites:
            return "Favourites"
        case .suggestions:
            return "Suggestions"
        case .sections:
            return "Sections list"
        }
    }

    var summary: String {
        switch self {
        case .search:
            return "The search bar"
        case .newSince:
            return "A card with the number of sites added since you last opened the app"
        case .randomPick:
            return "One random recommended site"
        case .pinned:
            return "Tiles for the sections and categories you pinned"
        case .newInPinned:
            return "Sites added to your pinned categories since your last visit"
        case .favourites:
            return "Your latest saved sites"
        case .suggestions:
            return "A random pick plus sites from the sections you open most"
        case .sections:
            return "All FMHY sections, grouped like the website"
        }
    }

    var symbol: String {
        switch self {
        case .search:
            return "magnifyingglass"
        case .newSince:
            return "sparkles"
        case .randomPick:
            return "dice"
        case .pinned:
            return "pin"
        case .newInPinned:
            return "bell"
        case .favourites:
            return "star"
        case .suggestions:
            return "wand.and.stars"
        case .sections:
            return "list.bullet"
        }
    }
}

struct HomeLayoutEntry: Equatable, Hashable, Sendable {
    var block: HomeBlock
    var enabled: Bool

    init(block: HomeBlock, enabled: Bool) {
        self.block = block
        self.enabled = enabled
    }
}

struct HomeLayout: Equatable, Sendable {
    var entries: [HomeLayoutEntry]

    init(entries: [HomeLayoutEntry] = defaultEntries) {
        self.entries = entries
    }

    static let defaultEntries: [HomeLayoutEntry] = [
        HomeLayoutEntry(block: .search, enabled: true),
        HomeLayoutEntry(block: .newSince, enabled: true),
        HomeLayoutEntry(block: .randomPick, enabled: true),
        HomeLayoutEntry(block: .pinned, enabled: false),
        HomeLayoutEntry(block: .newInPinned, enabled: false),
        HomeLayoutEntry(block: .favourites, enabled: false),
        HomeLayoutEntry(block: .suggestions, enabled: false),
        HomeLayoutEntry(block: .sections, enabled: true)
    ]

    static let `default`: HomeLayout = HomeLayout(entries: defaultEntries)

    var enabledBlocks: [HomeBlock] {
        entries.filter { $0.enabled }.map { $0.block }
    }

    func isEnabled(_ block: HomeBlock) -> Bool {
        entries.first(where: { $0.block == block })?.enabled ?? false
    }

    func withEnabled(_ block: HomeBlock, _ on: Bool) -> HomeLayout {
        HomeLayout(entries: entries.map { entry in
            entry.block == block ? HomeLayoutEntry(block: entry.block, enabled: on) : entry
        })
    }

    func withEnabled(_ block: HomeBlock, on: Bool) -> HomeLayout {
        withEnabled(block, on)
    }

    func move(from: Int, to: Int) -> HomeLayout {
        guard from != to,
              entries.indices.contains(from),
              entries.indices.contains(to) else {
            return self
        }
        var mutable = entries
        let item = mutable.remove(at: from)
        mutable.insert(item, at: to)
        return HomeLayout(entries: mutable)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) -> HomeLayout {
        var mutable = entries
        mutable.move(fromOffsets: source, toOffset: destination)
        return HomeLayout(entries: mutable)
    }

    func reset() -> HomeLayout {
        Self.default
    }

    func encode() -> String {
        entries.map { "\($0.block.rawValue):\($0.enabled ? "1" : "0")" }.joined(separator: ",")
    }

    nonisolated static func ordinal(_ block: HomeBlock) -> Int {
        switch block {
        case .search: return 0
        case .newSince: return 1
        case .randomPick: return 2
        case .pinned: return 3
        case .newInPinned: return 4
        case .favourites: return 5
        case .suggestions: return 6
        case .sections: return 7
        }
    }

    nonisolated static func parseBlock(_ name: String) -> HomeBlock? {
        if let direct = HomeBlock(rawValue: name) {
            return direct
        }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch cleaned {
        case "SEARCH":
            return .search
        case "NEW_SINCE", "NEWSINCE":
            return .newSince
        case "RANDOM_PICK", "RANDOMPICK":
            return .randomPick
        case "PINNED":
            return .pinned
        case "NEW_IN_PINNED", "NEWINPINNED":
            return .newInPinned
        case "FAVOURITES", "FAVORITES":
            return .favourites
        case "SUGGESTIONS":
            return .suggestions
        case "SECTIONS":
            return .sections
        default:
            return nil
        }
    }

    nonisolated static func decode(_ s: String?) -> HomeLayout {
        guard let s = s else { return .default }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .default }

        let tokens = trimmed.split(separator: ",")
        var parsed: [HomeLayoutEntry] = []
        var seen = Set<HomeBlock>()

        for token in tokens {
            let parts = token.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let nameStr = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let flagStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            let enabled: Bool
            if flagStr == "1" {
                enabled = true
            } else if flagStr == "0" {
                enabled = false
            } else {
                continue
            }

            guard let block = parseBlock(nameStr) else { continue }
            if seen.insert(block).inserted {
                parsed.append(HomeLayoutEntry(block: block, enabled: enabled))
            }
        }

        guard !parsed.isEmpty else { return .default }

        var result = parsed
        for block in HomeBlock.allCases {
            if !seen.contains(block) {
                guard let defaultEntry = defaultEntries.first(where: { $0.block == block }) else { continue }
                let blockOrd = ordinal(block)
                let lastPrecedingIndex = result.lastIndex(where: { ordinal($0.block) < blockOrd })
                if let idx = lastPrecedingIndex {
                    result.insert(defaultEntry, at: idx + 1)
                } else {
                    let firstSucceedingIndex = result.firstIndex(where: { ordinal($0.block) > blockOrd })
                    if let idx = firstSucceedingIndex {
                        result.insert(defaultEntry, at: idx)
                    } else {
                        result.append(defaultEntry)
                    }
                }
            }
        }

        return HomeLayout(entries: result)
    }
}

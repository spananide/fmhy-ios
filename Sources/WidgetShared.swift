import Foundation

struct WidgetSite: Codable, Hashable, Sendable, Identifiable {
    var id: String { url }
    let name: String
    let url: String
    let description: String

    init(name: String, url: String, description: String) {
        self.name = name
        self.url = url
        self.description = description
    }
}

struct WidgetPin: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let emoji: String

    init(id: String, title: String, emoji: String) {
        self.id = id
        self.title = title
        self.emoji = emoji
    }
}

struct WidgetPayload: Codable, Hashable, Sendable {
    static let maxStarred: Int = 60
    static let maxPins: Int = 3

    let updatedAt: Date
    let starred: [WidgetSite]
    let pins: [WidgetPin]

    init(updatedAt: Date = Date(), starred: [WidgetSite], pins: [WidgetPin]) {
        self.updatedAt = updatedAt
        self.starred = starred
        self.pins = pins
    }

    nonisolated static func make(
        updatedAt: Date = Date(),
        starred: [WidgetSite],
        pins: [WidgetPin]
    ) -> WidgetPayload {
        let trimmedStarred = Array(starred.prefix(maxStarred))
        let trimmedPins = Array(pins.prefix(maxPins))
        return WidgetPayload(updatedAt: updatedAt, starred: trimmedStarred, pins: trimmedPins)
    }
}

enum WidgetStore {
    static let groupId: String = "group.de.spanani.fmhy"
    static let fileName: String = "widget.json"

    nonisolated static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }

    nonisolated static func fileURL() -> URL? {
        guard let container = containerURL() else { return nil }
        return container.appendingPathComponent(fileName)
    }

    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    nonisolated static func encode(_ payload: WidgetPayload) throws -> Data {
        try makeEncoder().encode(payload)
    }

    nonisolated static func decode(_ data: Data) throws -> WidgetPayload {
        try makeDecoder().decode(WidgetPayload.self, from: data)
    }

    @discardableResult
    nonisolated static func write(_ payload: WidgetPayload) -> Bool {
        guard let targetURL = fileURL() else { return false }
        return write(payload, to: targetURL)
    }

    @discardableResult
    nonisolated static func write(_ payload: WidgetPayload, to url: URL) -> Bool {
        do {
            let data = try encode(payload)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    nonisolated static func read() -> WidgetPayload? {
        guard let sourceURL = fileURL() else { return nil }
        return read(from: sourceURL)
    }

    nonisolated static func read(from url: URL) -> WidgetPayload? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decode(data)
        } catch {
            return nil
        }
    }

    nonisolated static func buildPayload(
        starred: [WidgetSite],
        pins: [WidgetPin],
        updatedAt: Date = Date()
    ) -> WidgetPayload {
        WidgetPayload.make(updatedAt: updatedAt, starred: starred, pins: pins)
    }
}

enum WidgetDeepLinks {
    static let scheme: String = "fmhy"

    static var searchURL: URL {
        URL(string: "fmhy://search")!
    }

    nonisolated static func openURL(urlString: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: urlString)]
        return components.url
    }

    nonisolated static func sectionURL(id: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "section"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }
}

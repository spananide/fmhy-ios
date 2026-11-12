import Foundation

struct Link: Codable, Hashable, Sendable {
    var label: String
    var url: String
}

struct WikiSection: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var description: String
    var ord: Int
}

struct Heading: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var sectionId: String
    var parentId: String?
    var level: Int
    var title: String
    var anchor: String
    var ord: Int
}

struct Note: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var sectionId: String
    var headingId: String?
    var ord: Int
    var text: String
}

struct Entry: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var sectionId: String
    var headingId: String?
    var ord: Int
    var name: String
    var url: String
    var originalUrl: String?
    var description: String
    var tags: [String]
    var headingPath: String
    var tier: Int
    var kind: Int
    var isInlineMore: Bool
    var isBase64: Bool
    var mirrors: [Link]
    var extraLinks: [Link]
}

struct ParsedSection: Sendable {
    var section: WikiSection
    var headings: [Heading]
    var entries: [Entry]
    var notes: [Note]
    var unparsedLines: Int
}

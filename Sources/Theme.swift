import SwiftUI

struct TagLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.15), in: Capsule())
    }
}

struct FMHYListStyle: ViewModifier {
    @EnvironmentObject var settings: AppSettings

    func body(content: Content) -> some View {
        if settings.theme == .black {
            content
                .scrollContentBackground(.hidden)
                .background(Color.black)
        } else {
            content
        }
    }
}

struct FMHYRowBackground: ViewModifier {
    @EnvironmentObject var settings: AppSettings

    func body(content: Content) -> some View {
        if settings.theme == .black {
            content
                .listRowBackground(Color(white: 0.08))
        } else {
            content
        }
    }
}

extension View {
    func fmhyListStyle() -> some View {
        modifier(FMHYListStyle())
    }

    func fmhyRowBackground() -> some View {
        modifier(FMHYRowBackground())
    }
}

enum SectionLayout {
    static let groups: [(title: String, ids: [String])] = [
        ("Wiki", [
            "privacy", "ai", "video", "audio", "gaming", "reading",
            "downloading", "torrenting", "educational", "mobile",
            "linux-macos", "non-english", "misc"
        ]),
        ("Tools", [
            "system-tools", "file-tools", "internet-tools", "social-media-tools",
            "text-tools", "gaming-tools", "image-tools", "video-tools",
            "audio-tools", "educational-tools", "developer-tools"
        ]),
        ("More", [
            "beginners-guide", "storage", "unsafe"
        ])
    ]

    static func layout(sections: [WikiSection]) -> [(title: String, sections: [WikiSection])] {
        let sectionMap = Dictionary(sections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let allKnownIds = Set(groups.flatMap { $0.ids })
        var result: [(title: String, sections: [WikiSection])] = []

        for group in groups {
            var groupSections = group.ids.compactMap { sectionMap[$0] }
            if group.title == "More" {
                let unlisted = sections.filter { !allKnownIds.contains($0.id) }
                groupSections.append(contentsOf: unlisted)
            }
            if !groupSections.isEmpty {
                result.append((title: group.title, sections: groupSections))
            }
        }
        return result
    }
}

func sectionSymbol(_ id: String) -> String {
    switch id.lowercased() {
    case "privacy": return "shield.lefthalf.filled"
    case "ai": return "sparkles"
    case "mobile": return "iphone"
    case "audio": return "headphones"
    case "beginners-guide": return "book"
    case "downloading": return "arrow.down.circle"
    case "educational": return "graduationcap"
    case "gaming": return "gamecontroller"
    case "linux-macos": return "desktopcomputer"
    case "misc": return "ellipsis.circle"
    case "nsfwpiracy": return "eye.slash"
    case "non-english": return "globe"
    case "reading": return "books.vertical"
    case "gaming-tools": return "gamecontroller.fill"
    case "developer-tools": return "hammer"
    case "image-tools": return "photo"
    case "audio-tools": return "waveform"
    case "system-tools": return "gearshape.2"
    case "file-tools": return "folder"
    case "video-tools": return "film"
    case "text-tools": return "doc.text"
    case "internet-tools": return "network"
    case "social-media-tools": return "bubble.left.and.bubble.right"
    case "storage": return "externaldrive"
    case "torrenting": return "arrow.up.and.down.circle"
    case "video": return "play.tv"
    case "base64": return "lock"
    case "unsafe": return "exclamationmark.triangle"
    case "recently-removed": return "clock.arrow.circlepath"
    default: return "folder"
    }
}

extension String {
    var hostOnly: String {
        if let h = SafeGuard.extractHostFromUrl(self) {
            return h
        }
        if let url = URL(string: self), let h = url.host {
            let lower = h.lowercased()
            return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
        }
        return self
    }
}

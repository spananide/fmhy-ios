import SwiftUI

let fmhyPurple = Color(red: 0.65, green: 0.19, blue: 0.95)

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

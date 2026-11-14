import WidgetKit
import SwiftUI

private let widgetPurple = Color(red: 0.65, green: 0.19, blue: 0.95)

struct FMHYEntry: TimelineEntry {
    let date: Date
    let site: WidgetSite?
    let pins: [WidgetPin]
    let hasData: Bool
}

struct FMHYTimelineProvider: TimelineProvider {
    typealias Entry = FMHYEntry

    func placeholder(in context: Context) -> FMHYEntry {
        FMHYEntry(
            date: Date(),
            site: WidgetSite(
                name: "FMHY",
                url: "https://fmhy.net",
                description: "Free Media Heck Yeah wiki"
            ),
            pins: [
                WidgetPin(id: "video", title: "Video", emoji: "📺"),
                WidgetPin(id: "audio", title: "Audio", emoji: "🎵"),
                WidgetPin(id: "gaming", title: "Gaming", emoji: "🎮")
            ],
            hasData: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FMHYEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(makeCurrentEntry(for: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FMHYEntry>) -> Void) {
        let now = Date()
        let entry = makeCurrentEntry(for: now)
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now.addingTimeInterval(6 * 3600)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    private func makeCurrentEntry(for date: Date) -> FMHYEntry {
        let payload = WidgetStore.read()
        let site = payload?.starred.randomElement()
        let pins = payload?.pins ?? []
        let hasData = (payload != nil && !(payload?.starred.isEmpty ?? true))
        return FMHYEntry(date: date, site: site, pins: pins, hasData: hasData)
    }
}

@main
struct FMHYWidgetBundle: WidgetBundle {
    var body: some Widget {
        FMHYWidget()
    }
}

struct FMHYWidget: Widget {
    let kind: String = "FMHYWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FMHYTimelineProvider()) { entry in
            FMHYWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("FMHY")
        .description("Search FMHY, discover starred sites, and jump to pinned categories.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FMHYWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: FMHYEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                FMHYSmallWidgetView(entry: entry)
            } else {
                FMHYMediumWidgetView(entry: entry)
            }
        }
    }
}

struct FMHYSearchPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(widgetPurple)
            Text("Search FMHY")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(Capsule())
    }
}

struct FMHYPlaceholderContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No sites loaded")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Open FMHY to load sites")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

struct FMHYSmallWidgetView: View {
    let entry: FMHYEntry

    private var searchURL: URL {
        WidgetDeepLinks.searchURL
    }

    private var targetURL: URL {
        if let site = entry.site, let url = WidgetDeepLinks.openURL(urlString: site.url) {
            return url
        }
        return searchURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwiftUI.Link(destination: searchURL) {
                FMHYSearchPill()
            }

            Spacer(minLength: 0)

            if entry.hasData, let site = entry.site {
                FMHYSmallSiteContent(site: site)
            } else {
                FMHYPlaceholderContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(targetURL)
    }
}

struct FMHYSmallSiteContent: View {
    let site: WidgetSite

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text(site.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if !site.description.isEmpty {
                Text(site.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct FMHYMediumWidgetView: View {
    let entry: FMHYEntry

    private var searchURL: URL {
        WidgetDeepLinks.searchURL
    }

    private var siteOpenURL: URL? {
        guard let site = entry.site else { return nil }
        return WidgetDeepLinks.openURL(urlString: site.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Link(destination: searchURL) {
                FMHYSearchPill()
            }

            if entry.hasData, let site = entry.site {
                if let url = siteOpenURL {
                    SwiftUI.Link(destination: url) {
                        FMHYMediumSiteCard(site: site)
                    }
                } else {
                    FMHYMediumSiteCard(site: site)
                }
            } else {
                FMHYPlaceholderContent()
            }

            if !entry.pins.isEmpty {
                FMHYPinsRow(pins: entry.pins)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FMHYMediumSiteCard: View {
    let site: WidgetSite

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text(site.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "safari")
                    .font(.caption2)
                    .foregroundStyle(widgetPurple)
            }

            if !site.description.isEmpty {
                Text(site.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct FMHYPinsRow: View {
    let pins: [WidgetPin]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(pins.prefix(3)) { pin in
                FMHYPinChip(pin: pin)
            }
            Spacer(minLength: 0)
        }
    }
}

struct FMHYPinChip: View {
    let pin: WidgetPin

    private var targetURL: URL {
        WidgetDeepLinks.sectionURL(id: pin.id) ?? WidgetDeepLinks.searchURL
    }

    var body: some View {
        SwiftUI.Link(destination: targetURL) {
            HStack(spacing: 4) {
                Text(pin.emoji)
                    .font(.caption)
                Text(pin.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemFill))
            .clipShape(Capsule())
        }
    }
}

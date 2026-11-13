import SwiftUI

struct LegendRow<Icon: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 14) {
            iconContainer
            textContainer
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var iconContainer: some View {
        ZStack {
            icon()
        }
        .frame(width: 32, alignment: .center)
    }

    private var textContainer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct LegendView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        List {
            markersSection
            linksAndRowsSection
            platformsSection
            gesturesSection
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
        .navigationTitle("Icon legend")
    }

    // MARK: - Sections

    private var markersSection: some View {
        SwiftUI.Section("Markers") {
            LegendRow(
                title: "Top pick",
                subtitle: "FMHY's absolute top choice in a category"
            ) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.body)
            }
            .fmhyRowBackground()

            LegendRow(
                title: "Recommended",
                subtitle: "Standout site or tool recommended by the community"
            ) {
                Image(systemName: "star")
                    .foregroundStyle(.yellow)
                    .font(.body)
            }
            .fmhyRowBackground()

            LegendRow(
                title: "Recently added",
                subtitle: "New entry added in the latest wiki updates"
            ) {
                Text("NEW")
                    .font(.caption2.bold())
                    .foregroundStyle(fmhyPurple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(fmhyPurple.opacity(0.15))
                    .clipShape(Capsule())
            }
            .fmhyRowBackground()
        }
    }

    private var linksAndRowsSection: some View {
        SwiftUI.Section("Links & Details") {
            LegendRow(
                title: "Mirrors",
                subtitle: "Numbered alternate domains for a site (e.g. 1, 2)"
            ) {
                Text("1, 2")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(settings.accent.color)
            }
            .fmhyRowBackground()

            LegendRow(
                title: "Decoded link",
                subtitle: "Base64 encoded link decoded automatically by the app"
            ) {
                Image(systemName: "lock.shield")
                    .font(.body)
                    .foregroundStyle(.orange)
            }
            .fmhyRowBackground()

            LegendRow(
                title: "Saved bookmark",
                subtitle: "Bookmarked entry stored in your local library"
            ) {
                Image(systemName: "bookmark.fill")
                    .font(.body)
                    .foregroundStyle(.yellow)
            }
            .fmhyRowBackground()

            LegendRow(
                title: "Subcategory path",
                subtitle: "Shows which section and subsection the item belongs to"
            ) {
                Image(systemName: "folder")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fmhyRowBackground()

            LegendRow(
                title: "Section note",
                subtitle: "Important context or instructions; tap to view full text"
            ) {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fmhyRowBackground()
        }
    }

    private var platformsSection: some View {
        SwiftUI.Section("Platforms & Tags") {
            LegendRow(title: "Windows", subtitle: "Available for Microsoft Windows") {
                Image(systemName: "desktopcomputer")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fmhyRowBackground()

            LegendRow(title: "macOS", subtitle: "Available for Apple Mac") {
                Image(systemName: "laptopcomputer")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fmhyRowBackground()

            LegendRow(title: "Linux", subtitle: "Available for Linux distributions") {
                Image(systemName: "terminal")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fmhyRowBackground()

            LegendRow(title: "Android", subtitle: "Available for Android devices") {
                Image(systemName: "phone")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fmhyRowBackground()

            LegendRow(title: "iOS", subtitle: "Available for iPhone and iPad") {
                Image(systemName: "apple.logo")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fmhyRowBackground()

            LegendRow(title: "Web", subtitle: "Runs in any web browser without installation") {
                Image(systemName: "globe")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fmhyRowBackground()
        }
    }

    private var gesturesSection: some View {
        SwiftUI.Section("Gestures") {
            LegendRow(
                title: "Tap an entry",
                subtitle: "Opens details with all mirrors, extra links, and full description"
            ) {
                Image(systemName: "hand.tap")
                    .font(.body)
                    .foregroundStyle(settings.accent.color)
            }
            .fmhyRowBackground()

            LegendRow(
                title: "Swipe an entry",
                subtitle: "Swipe right-to-left to quickly bookmark or unbookmark"
            ) {
                Image(systemName: "hand.draw")
                    .font(.body)
                    .foregroundStyle(settings.accent.color)
            }
            .fmhyRowBackground()

            LegendRow(
                title: "Hold an entry",
                subtitle: "Brings up quick actions: open site, open in Safari, copy, share"
            ) {
                Image(systemName: "contextualmenu.and.cursor")
                    .font(.body)
                    .foregroundStyle(settings.accent.color)
            }
            .fmhyRowBackground()
        }
    }
}

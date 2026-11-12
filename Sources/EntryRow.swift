import SwiftUI

struct EntryRow: View {
    let entry: Entry
    let onSelect: (Entry) -> Void

    @EnvironmentObject var bookmarks: Bookmarks
    @State private var safariTarget: SafariTarget?

    private var subtitle: String {
        entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button {
            onSelect(entry)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                if entry.tier == 2 {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.subheadline)
                        .accessibilityLabel("Top pick")
                } else if entry.tier == 1 {
                    Image(systemName: "star")
                        .foregroundStyle(.yellow)
                        .font(.subheadline)
                        .accessibilityLabel("Starred")
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !entry.url.hostOnly.isEmpty {
                        Text(entry.url.hostOnly)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                bookmarks.toggle(entry.id)
            } label: {
                Label(
                    bookmarks.isSaved(entry.id) ? "Unsave" : "Save",
                    systemImage: bookmarks.isSaved(entry.id) ? "bookmark.slash" : "bookmark"
                )
            }
            .tint(.yellow)
        }
        .contextMenu {
            Button {
                if let target = SafariTarget(urlString: entry.url) {
                    safariTarget = target
                }
            } label: {
                Label("Open site", systemImage: "safari")
            }
            .disabled(SafariTarget(urlString: entry.url) == nil)

            Button {
                UIPasteboard.general.string = entry.url
            } label: {
                Label("Copy link", systemImage: "doc.on.doc")
            }

            if let url = URL(string: entry.url) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                bookmarks.toggle(entry.id)
            } label: {
                Label(
                    bookmarks.isSaved(entry.id) ? "Unsave" : "Save",
                    systemImage: bookmarks.isSaved(entry.id) ? "bookmark.slash" : "bookmark"
                )
            }
        }
        .fullScreenCover(item: $safariTarget) { target in
            SafariView(url: target.url)
                .ignoresSafeArea()
        }
    }
}

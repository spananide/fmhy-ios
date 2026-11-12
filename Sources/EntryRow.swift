import SwiftUI

struct EntryRow: View {
    let entry: Entry
    let onSelect: (Entry) -> Void

    @EnvironmentObject var bookmarks: Bookmarks
    @EnvironmentObject var hub: BrowserHub
    @EnvironmentObject var changes: ChangesStore

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
                    HStack(alignment: .center, spacing: 6) {
                        Text(entry.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if changes.isRecentlyAdded(url: entry.url) {
                            Text("NEW")
                                .font(.caption2.bold())
                                .foregroundStyle(fmhyPurple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(fmhyPurple.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

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
                    hub.open(target.url)
                }
            } label: {
                Label("Open site", systemImage: "safari")
            }
            .disabled(SafariTarget(urlString: entry.url) == nil)

            Button {
                if let target = SafariTarget(urlString: entry.url) {
                    UIApplication.shared.open(target.url)
                }
            } label: {
                Label("Open in Safari", systemImage: "safari")
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
    }
}

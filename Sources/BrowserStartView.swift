import SwiftUI

struct BrowserStartView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var bookmarks: Bookmarks
    @EnvironmentObject var tabs: TabManager

    private var savedSites: [Entry] {
        Array(bookmarks.entries(from: store.entries).prefix(8))
    }

    private func loadURL(_ url: URL) {
        if let selected = tabs.selected {
            selected.load(url)
        } else {
            _ = tabs.newTab(url: url, isPrivate: false, select: true)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "safari")
                        .font(.system(size: 48))
                        .foregroundStyle(fmhyPurple)

                    Text("Browser")
                        .font(.title.bold())
                        .foregroundStyle(.primary)

                    Text("Search or enter an address above")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                Button {
                    if let url = URL(string: "https://fmhy.net") {
                        loadURL(url)
                    }
                } label: {
                    Label("Open fmhy.net", systemImage: "globe")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)

                if !savedSites.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Saved sites")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 24)

                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            ForEach(savedSites) { entry in
                                Button {
                                    if let url = URL(string: entry.url) {
                                        loadURL(url)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: entry.tier >= 1 ? "star.fill" : "bookmark.fill")
                                                .font(.caption)
                                                .foregroundStyle(entry.tier >= 1 ? .yellow : fmhyPurple)
                                            Spacer()
                                        }

                                        Text(entry.name)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        if !entry.url.hostOnly.isEmpty {
                                            Text(entry.url.hostOnly)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                Spacer(minLength: 20)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

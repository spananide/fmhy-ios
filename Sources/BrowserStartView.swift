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
        List {
            SwiftUI.Section {
                Button {
                    if let url = URL(string: "https://fmhy.net") { loadURL(url) }
                } label: {
                    Label("Open fmhy.net", systemImage: "globe")
                }
                .fmhyRowBackground()
            } footer: {
                Text("Search or enter an address above.")
            }

            if !savedSites.isEmpty {
                SwiftUI.Section("Saved sites") {
                    ForEach(savedSites) { entry in
                        Button {
                            if let url = URL(string: entry.url) { loadURL(url) }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name).font(.body).foregroundStyle(.primary).lineLimit(1)
                                    if !entry.url.hostOnly.isEmpty {
                                        Text(entry.url.hostOnly).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            } icon: {
                                Image(systemName: entry.tier >= 1 ? "star.fill" : "bookmark.fill")
                                    .foregroundStyle(entry.tier >= 1 ? Color.yellow : Color.accentColor)
                            }
                        }
                        .fmhyRowBackground()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
    }
}

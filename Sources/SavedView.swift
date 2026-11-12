import SwiftUI

struct SavedView: View {
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var bookmarks: Bookmarks
    @State private var savedEntries: [Entry] = []
    @State private var selectedEntry: Entry?

    private func updateEntries() {
        savedEntries = bookmarks.entries(from: store.entries)
    }

    var body: some View {
        NavigationStack {
            Group {
                if savedEntries.isEmpty {
                    ContentUnavailableView(
                        "No Saved Sites",
                        systemImage: "bookmark",
                        description: Text("Swipe right on any site to save it")
                    )
                } else {
                    List {
                        ForEach(savedEntries) { entry in
                            EntryRow(entry: entry) { selected in
                                selectedEntry = selected
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !savedEntries.isEmpty {
                        ShareLink(item: bookmarks.shareText(entries: savedEntries)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share saved sites")
                    }
                }
            }
            .task(id: "\(bookmarks.ids.count)_\(store.entries.count)") {
                updateEntries()
            }
            .onChange(of: bookmarks.ids) { _, _ in
                updateEntries()
            }
            .onChange(of: store.entries.count) { _, _ in
                updateEntries()
            }
            .sheet(item: $selectedEntry) { entry in
                EntryDetailSheet(entry: entry)
            }
        }
    }
}

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: WikiStore
    @State private var query: String
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var selectedEntry: Entry?
    @State private var isCheckPresented: Bool

    init() {
        let initialQuery = UserDefaults.standard.string(forKey: "query") ?? ""
        _query = State(initialValue: initialQuery)

        let showCheck = UserDefaults.standard.bool(forKey: "showCheck")
        let tab = UserDefaults.standard.integer(forKey: "tab")
        _isCheckPresented = State(initialValue: showCheck || tab == 3)
    }

    var body: some View {
        NavigationStack {
            Group {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    helpCard
                } else if results.isEmpty && !isSearching {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(results) { res in
                            EntryRow(entry: res.entry) { selected in
                                selectedEntry = selected
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .fmhyListStyle()
                }
            }
            .navigationTitle("Search")
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search wiki…"
            )
            .task(id: "\(query)_\(store.search != nil)") {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    results = []
                    isSearching = false
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                } catch {
                    return
                }

                guard let searchIndex = store.search else {
                    results = []
                    return
                }

                isSearching = true
                let searchResults = await Task.detached {
                    searchIndex.search(trimmed, limit: 100)
                }.value

                if !Task.isCancelled {
                    self.results = searchResults
                    self.isSearching = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCheckPresented = true
                    } label: {
                        Image(systemName: "checkmark.shield")
                    }
                    .accessibilityLabel("Check a link")
                }
            }
            .sheet(isPresented: $isCheckPresented) {
                CheckLinkView()
            }
            .sheet(item: $selectedEntry) { entry in
                EntryDetailSheet(entry: entry)
            }
        }
    }

    private var helpCard: some View {
        List {
            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search Filters")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Use filter keywords to narrow down wiki entries:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        filterRow(syntax: "in:video anime", note: "Search in video section")
                        filterRow(syntax: "is:starred", note: "Top picks and starred sites")
                        filterRow(syntax: "site:github.com", note: "Filter by website domain")
                        filterRow(syntax: "\"exact phrase\"", note: "Match exact words in quotes")
                    }

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Typos are fine — fuzzy search automatically finds close matches.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
    }

    @ViewBuilder
    private func filterRow(syntax: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(syntax)
                .font(.system(.subheadline, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.systemFill))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Spacer()
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

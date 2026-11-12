import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: WikiStore

    private var footerText: String {
        if let date = store.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
        } else {
            return "Bundled wiki"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    ForEach(store.sections) { section in
                        NavigationLink(value: section) {
                            HStack(spacing: 12) {
                                Image(systemName: sectionSymbol(section.id))
                                    .font(.title3)
                                    .foregroundStyle(fmhyPurple)
                                    .frame(width: 28, alignment: .center)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(section.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    if !section.description.isEmpty {
                                        Text(section.description)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } footer: {
                    VStack(alignment: .center, spacing: 4) {
                        if let error = store.errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                        Text(footerText)
                            .foregroundStyle(.secondary)
                        Text("[Send feedback](https://github.com/spananide/fmhy-ios/issues/new/choose)")
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("FMHY")
            .navigationDestination(for: WikiSection.self) { section in
                SectionView(section: section)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isRefreshing {
                        ProgressView()
                    } else {
                        Button {
                            Task {
                                await store.refresh()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh wiki")
                        .disabled(store.isLoading)
                    }
                }
            }
        }
    }
}

import SwiftUI

enum ChangeKind: String, CaseIterable, Identifiable {
    case added
    case removed
    case starred
    case unstarred
    case url_changed
    case renamed
    case moved
    case edited

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .added: return "Added"
        case .removed: return "Removed"
        case .starred: return "Starred"
        case .unstarred: return "Unstarred"
        case .url_changed: return "URL changed"
        case .renamed: return "Renamed"
        case .moved: return "Moved"
        case .edited: return "Edited"
        }
    }

    var symbolName: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        case .starred: return "star.fill"
        case .unstarred: return "star.slash"
        case .url_changed: return "arrow.triangle.2.circlepath"
        case .renamed, .edited: return "pencil.circle"
        case .moved: return "arrow.right.circle"
        }
    }

    var color: Color {
        switch self {
        case .added: return .green
        case .removed: return .red
        case .starred: return .yellow
        case .unstarred: return .gray
        case .url_changed: return .blue
        case .renamed: return .orange
        case .edited: return .secondary
        case .moved: return .purple
        }
    }
}

private struct DayGroup: Identifiable {
    let id: Date
    let title: String
    let changes: [WikiChange]
}

struct ChangesView: View {
    @EnvironmentObject var changes: ChangesStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var hub: BrowserHub
    @Environment(\.scenePhase) private var scenePhase

    private static let defaultKinds: Set<ChangeKind> = Set(ChangeKind.allCases.filter { $0 != .edited })

    @State private var selectedKinds: Set<ChangeKind> = defaultKinds
    @State private var onlyFollowed: Bool = false
    @State private var selectedSectionId: String? = nil

    private var filteredChanges: [WikiChange] {
        let allowedKinds = Set(selectedKinds.map { $0.rawValue })
        return changes.changes.filter { change in
            guard allowedKinds.contains(change.kind) else { return false }
            if onlyFollowed {
                guard follows.isFollowing(change.sectionId) else { return false }
            }
            if let secId = selectedSectionId {
                guard change.sectionId == secId else { return false }
            }
            return true
        }
    }

    private var displayedChanges: [WikiChange] {
        Array(filteredChanges.prefix(500))
    }

    private var dayGroups: [DayGroup] {
        let items = displayedChanges
        guard !items.isEmpty else { return [] }

        let calendar = Calendar.current
        var groups: [DayGroup] = []
        var currentDay: Date? = nil
        var currentChanges: [WikiChange] = []

        for change in items {
            let date = Date(timeIntervalSince1970: TimeInterval(change.ts))
            let startOfDay = calendar.startOfDay(for: date)

            if startOfDay == currentDay {
                currentChanges.append(change)
            } else {
                if let day = currentDay, !currentChanges.isEmpty {
                    groups.append(DayGroup(
                        id: day,
                        title: dayHeader(for: day, calendar: calendar),
                        changes: currentChanges
                    ))
                }
                currentDay = startOfDay
                currentChanges = [change]
            }
        }

        if let day = currentDay, !currentChanges.isEmpty {
            groups.append(DayGroup(
                id: day,
                title: dayHeader(for: day, calendar: calendar),
                changes: currentChanges
            ))
        }

        return groups
    }

    private func dayHeader(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    private func sectionTitle(for id: String) -> String {
        store.sections.first(where: { $0.id == id })?.title ?? id
    }

    var body: some View {
        NavigationStack {
            Group {
                if changes.changes.isEmpty && changes.isLoading {
                    ProgressView("Loading wiki changes…")
                } else if changes.changes.isEmpty && changes.errorMessage != nil {
                    ContentUnavailableView {
                        Label("Unable to Load Changes", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(changes.errorMessage ?? "An error occurred while loading changes.")
                    } actions: {
                        Button("Try Again") {
                            Task {
                                await changes.refresh()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if changes.changes.isEmpty {
                    ContentUnavailableView(
                        "No Changes",
                        systemImage: "bell.slash",
                        description: Text("No wiki changes available yet.")
                    )
                } else if displayedChanges.isEmpty {
                    ContentUnavailableView(
                        "No Matching Changes",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No changes match your current filter settings.")
                    )
                } else {
                    List {
                        ForEach(dayGroups) { group in
                            SwiftUI.Section {
                                ForEach(group.changes) { change in
                                    if change.kind == "removed" {
                                        rowContent(for: change)
                                    } else {
                                        Button {
                                            hub.open(change.url)
                                        } label: {
                                            rowContent(for: change)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            } header: {
                                Text(group.title)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await changes.refresh()
                    }
                }
            }
            .navigationTitle("What's new")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        SwiftUI.Section("Categories") {
                            Picker("Category", selection: $selectedSectionId) {
                                Text("All categories").tag(String?.none)
                                ForEach(store.sections) { sec in
                                    Text(sec.title).tag(String?(sec.id))
                                }
                            }
                        }

                        SwiftUI.Section("Filter by Type") {
                            ForEach(ChangeKind.allCases) { kind in
                                Button {
                                    if selectedKinds.contains(kind) {
                                        selectedKinds.remove(kind)
                                    } else {
                                        selectedKinds.insert(kind)
                                    }
                                } label: {
                                    if selectedKinds.contains(kind) {
                                        Label(kind.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(kind.displayName)
                                    }
                                }
                            }
                        }

                        SwiftUI.Section {
                            Button {
                                onlyFollowed.toggle()
                            } label: {
                                if onlyFollowed {
                                    Label("Only followed categories", systemImage: "checkmark")
                                } else {
                                    Text("Only followed categories")
                                }
                            }
                            .disabled(follows.isEmpty)
                        }
                    } label: {
                        let isFiltered = selectedSectionId != nil || onlyFollowed || selectedKinds != Self.defaultKinds
                        Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter changes")

                    if changes.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task {
                                await changes.refresh()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh changes")
                    }
                }
            }
            .task {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    changes.markSeen()
                } catch {}
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    changes.markSeen()
                }
            }
        }
    }

    @ViewBuilder
    private func rowContent(for change: WikiChange) -> some View {
        let kind = ChangeKind(rawValue: change.kind)
        let iconName = kind?.symbolName ?? "circle"
        let iconColor = kind?.color ?? .secondary
        let kindText = kind?.displayName ?? change.kind.capitalized
        let secTitle = sectionTitle(for: change.sectionId)

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(change.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text("\(kindText) \u{00B7} \(secTitle)")

                    if change.kind == "moved", !change.detail.isEmpty {
                        let destTitle = sectionTitle(for: change.detail)
                        Text("\u{2192} \(destTitle)")
                    }

                    if change.kind == "renamed", !change.detail.isEmpty {
                        Text("was: \(change.detail)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

                if change.kind == "url_changed", !change.detail.isEmpty {
                    let host = change.detail.hostOnly
                    if !host.isEmpty {
                        Text(host)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else if change.kind != "removed" && !change.url.hostOnly.isEmpty {
                    Text(change.url.hostOnly)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

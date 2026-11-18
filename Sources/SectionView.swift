import SwiftUI
import UserNotifications

struct SectionGroup: Identifiable {
    let id: String
    let heading: Heading?
    let entries: [Entry]
    let notes: [Note]
}

struct SectionView: View {
    let section: WikiSection
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var visits: VisitTracker

    @State private var allGroups: [SectionGroup] = []
    @State private var displayedGroups: [SectionGroup] = []
    @State private var topGroups: [OutlineGroup] = []
    @State private var rootNotes: [Note] = []
    @State private var filterText = ""
    @State private var selectedEntry: Entry?
    @State private var selectedNote: Note?

    private func computeGroups() {
        let sectionEntries = store.entries(in: section.id)
        let sectionNotes = store.notes(in: section.id)
        let sectionHeadings = store.headings(in: section.id)

        self.topGroups = SectionOutline.topGroups(headings: sectionHeadings, entries: sectionEntries)

        var entriesByHeading: [String: [Entry]] = [:]
        var rootEntries: [Entry] = []
        for entry in sectionEntries {
            if let hid = entry.headingId {
                entriesByHeading[hid, default: []].append(entry)
            } else {
                rootEntries.append(entry)
            }
        }

        var notesByHeading: [String: [Note]] = [:]
        var rootNotes: [Note] = []
        for note in sectionNotes {
            if let hid = note.headingId {
                notesByHeading[hid, default: []].append(note)
            } else {
                rootNotes.append(note)
            }
        }
        self.rootNotes = rootNotes

        var groups: [SectionGroup] = []

        if !rootEntries.isEmpty || !rootNotes.isEmpty {
            groups.append(SectionGroup(
                id: "_root_",
                heading: nil,
                entries: rootEntries,
                notes: rootNotes
            ))
        }

        for heading in sectionHeadings {
            let entries = entriesByHeading[heading.id] ?? []
            let notes = notesByHeading[heading.id] ?? []
            groups.append(SectionGroup(
                id: heading.id,
                heading: heading,
                entries: entries,
                notes: notes
            ))
        }

        self.allGroups = groups
        applyFilter()
    }

    private func applyFilter() {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            displayedGroups = allGroups
            return
        }

        var filtered: [SectionGroup] = []
        for group in allGroups {
            let matchedEntries = group.entries.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.description.localizedCaseInsensitiveContains(trimmed)
            }
            if !matchedEntries.isEmpty {
                filtered.append(SectionGroup(
                    id: group.id,
                    heading: group.heading,
                    entries: matchedEntries,
                    notes: []
                ))
            }
        }
        displayedGroups = filtered
    }

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case ..<2:
            return .title3.bold()
        case 2:
            return .headline
        default:
            return .subheadline.weight(.semibold)
        }
    }

    private func indentForLevel(_ level: Int) -> CGFloat {
        CGFloat(max(0, level - 1)) * 10.0
    }

    @ViewBuilder
    private func headingHeader(_ heading: Heading) -> some View {
        Text(heading.title)
            .font(fontForLevel(heading.level))
            .foregroundStyle(.primary)
            .padding(.leading, indentForLevel(heading.level))
            .textCase(nil)
    }

    var body: some View {
        if section.id == "beginners-guide" {
            ReaderView(path: "beginners-guide.md", title: section.title)
        } else {
            regularBody
        }
    }

    private var regularBody: some View {
        Group {
            if !filterText.isEmpty {
                if displayedGroups.isEmpty {
                    ContentUnavailableView.search(text: filterText)
                } else {
                    flatList
                }
            } else if topGroups.count >= 2 {
                overviewList
            } else {
                flatList
            }
        }
        .navigationTitle(section.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let wasEmpty = follows.isEmpty
                    let willFollow = !follows.isFollowing(section.id)
                    follows.toggle(section.id)
                    if willFollow && wasEmpty {
                        Task {
                            let settings = await UNUserNotificationCenter.current().notificationSettings()
                            if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
                                _ = await Notifier.requestAuthorization()
                            }
                        }
                    }
                } label: {
                    Image(systemName: follows.isFollowing(section.id) ? "bell.fill" : "bell")
                }
                .accessibilityLabel("Follow category")
            }
        }
        .sensoryFeedback(.selection, trigger: follows.isFollowing(section.id))
        .searchable(text: $filterText, prompt: "Filter in \(section.title)")
        .onAppear {
            visits.record(sectionId: section.id)
        }
        .task {
            computeGroups()
        }
        .onChange(of: filterText) { _, _ in
            applyFilter()
        }
        .onChange(of: store.entries.count) { _, _ in
            computeGroups()
        }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailSheet(entry: entry)
        }
        .sheet(item: $selectedNote) { note in
            NoteSheet(note: note)
        }
    }

    private var overviewList: some View {
        List {
            if !rootNotes.isEmpty {
                SwiftUI.Section {
                    ForEach(rootNotes) { note in
                        NoteRow(text: note.text) {
                            selectedNote = note
                        }
                    }
                }
            }

            SwiftUI.Section {
                ForEach(topGroups) { group in
                    NavigationLink(value: GroupRoute(sectionId: section.id, groupId: group.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.title)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if !group.preview.isEmpty {
                                Text(group.preview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Text(group.siteCount == 1 ? "1 site" : "\(group.siteCount) sites")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
    }

    private var flatList: some View {
        List {
            ForEach(displayedGroups) { group in
                if let heading = group.heading {
                    SwiftUI.Section {
                        ForEach(group.notes) { note in
                            NoteRow(text: note.text) {
                                selectedNote = note
                            }
                        }
                        ForEach(group.entries) { entry in
                            EntryRow(entry: entry) { selected in
                                selectedEntry = selected
                            }
                        }
                    } header: {
                        headingHeader(heading)
                    }
                } else {
                    SwiftUI.Section {
                        ForEach(group.notes) { note in
                            NoteRow(text: note.text) {
                                selectedNote = note
                            }
                        }
                        ForEach(group.entries) { entry in
                            EntryRow(entry: entry) { selected in
                                selectedEntry = selected
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
    }
}

struct NoteRow: View {
    let text: String
    var onSelect: (() -> Void)? = nil

    var body: some View {
        Button {
            onSelect?()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                if let attr = try? AttributedString(markdown: text) {
                    Text(attr)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

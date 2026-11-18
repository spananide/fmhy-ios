import SwiftUI

struct GroupView: View {
    let route: GroupRoute

    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var visits: VisitTracker

    @State private var groupSections: [GroupSection] = []
    @State private var selectedEntry: Entry?
    @State private var selectedNote: Note?

    private var pageTitle: String {
        if route.groupId == SectionOutline.generalId {
            return "General"
        }
        if let heading = store.headings(in: route.sectionId).first(where: { $0.id == route.groupId }) {
            return SectionOutline.cleanTitle(heading.title)
        }
        return "General"
    }

    private var titledSections: [GroupSection] {
        groupSections.filter { $0.title != nil }
    }

    private func loadSections() {
        let headings = store.headings(in: route.sectionId)
        let entries = store.entries(in: route.sectionId)
        let notes = store.notes(in: route.sectionId)
        groupSections = SectionOutline.sections(
            forGroup: route.groupId,
            headings: headings,
            entries: entries,
            notes: notes
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if titledSections.count >= 2 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(titledSections) { section in
                                if let title = section.title {
                                    Button {
                                        withAnimation {
                                            proxy.scrollTo(section.id, anchor: .top)
                                        }
                                    } label: {
                                        Text(title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.tint)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(Color(.secondarySystemFill))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .background(.bar)
                }

                List {
                    ForEach(groupSections) { groupSection in
                        if let title = groupSection.title {
                            SwiftUI.Section {
                                ForEach(groupSection.notes) { note in
                                    NoteRow(text: note.text) {
                                        selectedNote = note
                                    }
                                }
                                ForEach(groupSection.entries) { entry in
                                    EntryRow(entry: entry) { selected in
                                        selectedEntry = selected
                                    }
                                }
                            } header: {
                                Text(title)
                                    .font(.headline)
                                    .textCase(nil)
                            }
                            .id(groupSection.id)
                        } else {
                            SwiftUI.Section {
                                ForEach(groupSection.notes) { note in
                                    NoteRow(text: note.text) {
                                        selectedNote = note
                                    }
                                }
                                ForEach(groupSection.entries) { entry in
                                    EntryRow(entry: entry) { selected in
                                        selectedEntry = selected
                                    }
                                }
                            }
                            .id(groupSection.id)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .fmhyListStyle()
            }
        }
        .navigationTitle(pageTitle)
        .onAppear {
            visits.record(sectionId: route.sectionId)
        }
        .task {
            loadSections()
        }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailSheet(entry: entry)
        }
        .sheet(item: $selectedNote) { note in
            NoteSheet(note: note)
        }
    }
}

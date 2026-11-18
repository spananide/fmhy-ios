import XCTest
@testable import FMHY

final class SectionOutlineTests: XCTestCase {

    // MARK: - Helpers

    private func makeHeading(
        id: String,
        sectionId: String = "video",
        parentId: String? = nil,
        level: Int = 1,
        title: String,
        anchor: String = "",
        ord: Int = 0
    ) -> Heading {
        Heading(
            id: id,
            sectionId: sectionId,
            parentId: parentId,
            level: level,
            title: title,
            anchor: anchor.isEmpty ? id : anchor,
            ord: ord
        )
    }

    private func makeEntry(
        id: String,
        sectionId: String = "video",
        headingId: String? = nil,
        ord: Int = 0,
        name: String = "Site",
        url: String = "https://example.com",
        originalUrl: String? = nil,
        description: String = "Description",
        tags: [String] = [],
        headingPath: String = "",
        tier: Int = 0,
        kind: Int = 0,
        isInlineMore: Bool = false,
        isBase64: Bool = false,
        mirrors: [Link] = [],
        extraLinks: [Link] = []
    ) -> Entry {
        Entry(
            id: id,
            sectionId: sectionId,
            headingId: headingId,
            ord: ord,
            name: name,
            url: url,
            originalUrl: originalUrl,
            description: description,
            tags: tags,
            headingPath: headingPath,
            tier: tier,
            kind: kind,
            isInlineMore: isInlineMore,
            isBase64: isBase64,
            mirrors: mirrors,
            extraLinks: extraLinks
        )
    }

    private func makeNote(
        id: String,
        sectionId: String = "video",
        headingId: String? = nil,
        ord: Int = 0,
        text: String = "A note"
    ) -> Note {
        Note(
            id: id,
            sectionId: sectionId,
            headingId: headingId,
            ord: ord,
            text: text
        )
    }

    // MARK: - Clean Title Tests

    func testCleanTitle() {
        XCTAssertEqual(SectionOutline.cleanTitle("[Linux Games](https://x.y/z)"), "Linux Games")
        XCTAssertEqual(SectionOutline.cleanTitle("► **Bold** Title"), "Bold Title")
        XCTAssertEqual(SectionOutline.cleanTitle("Plain text unchanged"), "Plain text unchanged")

        // Markdown links with nested paren in URL
        XCTAssertEqual(SectionOutline.cleanTitle("[Linux Games](https://en.wikipedia.org/wiki/Linux_(kernel))"), "Linux Games")

        // Arrow characters, backticks, asterisks, whitespace collapsing
        XCTAssertEqual(SectionOutline.cleanTitle("▷ `code` and *italic* and **bold**"), "code and italic and bold")
        XCTAssertEqual(SectionOutline.cleanTitle("   Multiple    spaces   between   words  "), "Multiple spaces between words")
        XCTAssertEqual(SectionOutline.cleanTitle("[First Link](https://a.com) & [Second Link](https://b.com)"), "First Link & Second Link")
        XCTAssertEqual(SectionOutline.cleanTitle(""), "")
    }

    // MARK: - Top Groups Tests

    func testTopGroups() {
        let h1 = makeHeading(id: "h1", level: 1, title: "► **Streaming Sites**", ord: 10)
        let c1 = makeHeading(id: "c1", parentId: "h1", level: 2, title: "Anime", ord: 11)
        let c2 = makeHeading(id: "c2", parentId: "h1", level: 2, title: "Movies", ord: 12)
        let c3 = makeHeading(id: "c3", parentId: "h1", level: 2, title: "TV Shows", ord: 13)
        let c4 = makeHeading(id: "c4", parentId: "h1", level: 2, title: "Sports", ord: 14)
        let c5 = makeHeading(id: "c5", parentId: "h1", level: 2, title: "Documentaries", ord: 15)

        let h2 = makeHeading(id: "h2", level: 1, title: "Download Sites", ord: 20)
        let c6 = makeHeading(id: "c6", parentId: "h2", level: 2, title: "Direct DL", ord: 21)
        let c7 = makeHeading(id: "c7", parentId: "h2", level: 2, title: "Torrents", ord: 22)

        let h3 = makeHeading(id: "h3", level: 1, title: "Empty Category", ord: 30)

        let headings = [h1, c1, c2, c3, c4, c5, h2, c6, c7, h3]

        let entries = [
            makeEntry(id: "e_root1", headingId: nil, ord: 1),
            makeEntry(id: "e_root2", headingId: nil, ord: 2),
            makeEntry(id: "e_h1", headingId: "h1", ord: 3),
            makeEntry(id: "e_c1_1", headingId: "c1", ord: 4),
            makeEntry(id: "e_c1_2", headingId: "c1", ord: 5),
            makeEntry(id: "e_c5", headingId: "c5", ord: 6),
            makeEntry(id: "e_c6_1", headingId: "c6", ord: 7),
            makeEntry(id: "e_c6_2", headingId: "c6", ord: 8),
            makeEntry(id: "e_c7", headingId: "c7", ord: 9)
        ]

        let groups = SectionOutline.topGroups(headings: headings, entries: entries)

        // Empty group h3 dropped -> 3 groups total: General, h1, h2
        XCTAssertEqual(groups.count, 3)

        // 1. General group for nil headingId entries
        XCTAssertEqual(groups[0].id, SectionOutline.generalId)
        XCTAssertEqual(groups[0].title, "General")
        XCTAssertEqual(groups[0].preview, "")
        XCTAssertEqual(groups[0].siteCount, 2)

        // 2. h1 group: counts include descendants (1 + 2 + 1 = 4)
        XCTAssertEqual(groups[1].id, "h1")
        XCTAssertEqual(groups[1].title, "Streaming Sites")
        XCTAssertEqual(groups[1].siteCount, 4)
        // Preview lists first 4 child titles with trailing " ..."
        XCTAssertEqual(groups[1].preview, "Anime, Movies, TV Shows, Sports ...")

        // 3. h2 group: counts include descendants (2 + 1 = 3)
        XCTAssertEqual(groups[2].id, "h2")
        XCTAssertEqual(groups[2].title, "Download Sites")
        XCTAssertEqual(groups[2].siteCount, 3)
        // Preview lists 2 child titles, no trailing " ..."
        XCTAssertEqual(groups[2].preview, "Direct DL, Torrents")
    }

    func testTopGroupsNoGeneralWhenNoNilHeadingEntries() {
        let h1 = makeHeading(id: "h1", level: 1, title: "Solo Group", ord: 1)
        let entries = [makeEntry(id: "e1", headingId: "h1", ord: 1)]
        let groups = SectionOutline.topGroups(headings: [h1], entries: entries)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, "h1")
        XCTAssertEqual(groups[0].title, "Solo Group")
        XCTAssertEqual(groups[0].siteCount, 1)
        XCTAssertEqual(groups[0].preview, "")
    }

    // MARK: - Sections For Group Tests

    func testSectionsForGroup() {
        let h1 = makeHeading(id: "h1", level: 1, title: "Streaming Sites", ord: 10)
        let c1 = makeHeading(id: "c1", parentId: "h1", level: 2, title: "Anime", ord: 11)
        let c2 = makeHeading(id: "c2", parentId: "h1", level: 2, title: "Movies", ord: 12)
        let c3 = makeHeading(id: "c3", parentId: "h1", level: 2, title: "TV Shows", ord: 13)
        let gc1 = makeHeading(id: "gc1", parentId: "c3", level: 3, title: "4K TV", ord: 14)

        let headings = [h1, c1, c2, c3, gc1]

        let rootEntry = makeEntry(id: "e_root", headingId: nil, ord: 1)
        let h1Entry1 = makeEntry(id: "e_h1_1", headingId: "h1", ord: 2)
        let h1Entry2 = makeEntry(id: "e_h1_2", headingId: "h1", ord: 5)
        let c1Entry = makeEntry(id: "e_c1", headingId: "c1", ord: 3)
        let gc1Entry = makeEntry(id: "e_gc1", headingId: "gc1", ord: 4)

        let entries = [rootEntry, h1Entry1, h1Entry2, c1Entry, gc1Entry]

        let rootNote = makeNote(id: "n_root", headingId: nil, ord: 1, text: "Root Note")
        let h1Note = makeNote(id: "n_h1", headingId: "h1", ord: 1, text: "H1 Note")
        let c3Note = makeNote(id: "n_c3", headingId: "c3", ord: 2, text: "C3 Note")

        let notes = [rootNote, h1Note, c3Note]

        // 1. Regular group sections
        let sections = SectionOutline.sections(forGroup: "h1", headings: headings, entries: entries, notes: notes)

        // Section 0: own entries & notes with title == nil
        XCTAssertEqual(sections.count, 4)
        XCTAssertEqual(sections[0].id, "h1")
        XCTAssertNil(sections[0].title)
        XCTAssertEqual(sections[0].entries.map(\.id), ["e_h1_1", "e_h1_2"])
        XCTAssertEqual(sections[0].notes.map(\.id), ["n_h1"])

        // Section 1: child c1
        XCTAssertEqual(sections[1].id, "c1")
        XCTAssertEqual(sections[1].title, "Anime")
        XCTAssertEqual(sections[1].entries.map(\.id), ["e_c1"])
        XCTAssertEqual(sections[1].notes.count, 0)

        // c2 is skipped because it has neither entries nor notes

        // Section 2: child c3 (has note, no entries)
        XCTAssertEqual(sections[2].id, "c3")
        XCTAssertEqual(sections[2].title, "TV Shows")
        XCTAssertEqual(sections[2].entries.count, 0)
        XCTAssertEqual(sections[2].notes.map(\.id), ["n_c3"])

        // Section 3: grandchild gc1 in ord order
        XCTAssertEqual(sections[3].id, "gc1")
        XCTAssertEqual(sections[3].title, "4K TV")
        XCTAssertEqual(sections[3].entries.map(\.id), ["e_gc1"])
        XCTAssertEqual(sections[3].notes.count, 0)

        // 2. Group with no direct entries/notes does not create an untitled first section
        let sectionsNoDirect = SectionOutline.sections(forGroup: "c3", headings: headings, entries: entries, notes: notes)
        // c3 has 1 direct note ("n_c3"), so it has untitled section
        XCTAssertEqual(sectionsNoDirect.count, 2)
        XCTAssertNil(sectionsNoDirect[0].title)
        XCTAssertEqual(sectionsNoDirect[1].title, "4K TV")

        // Heading with neither entries nor notes has no untitled section if children have entries
        let emptyParent = makeHeading(id: "p_empty", level: 1, title: "Empty Parent", ord: 100)
        let childOfEmpty = makeHeading(id: "c_child", parentId: "p_empty", level: 2, title: "Child", ord: 101)
        let childEntry = makeEntry(id: "e_child", headingId: "c_child", ord: 1)
        let sectionsEmptyParent = SectionOutline.sections(
            forGroup: "p_empty",
            headings: [emptyParent, childOfEmpty],
            entries: [childEntry],
            notes: []
        )
        XCTAssertEqual(sectionsEmptyParent.count, 1)
        XCTAssertEqual(sectionsEmptyParent[0].id, "c_child")
        XCTAssertEqual(sectionsEmptyParent[0].title, "Child")

        // 3. General ID returns heading-less entries and notes
        let generalSections = SectionOutline.sections(
            forGroup: SectionOutline.generalId,
            headings: headings,
            entries: entries,
            notes: notes
        )
        XCTAssertEqual(generalSections.count, 1)
        XCTAssertEqual(generalSections[0].id, SectionOutline.generalId)
        XCTAssertNil(generalSections[0].title)
        XCTAssertEqual(generalSections[0].entries.map(\.id), ["e_root"])
        XCTAssertEqual(generalSections[0].notes.map(\.id), ["n_root"])
    }

    // MARK: - Performance Sanity Test

    func testPerformance22000Entries() {
        var headings: [Heading] = []
        var headingOrd = 0
        var allHeadingIds: [String] = []

        // 10 top groups, each with 5 sub-headings = 60 headings
        for g in 0..<10 {
            let groupId = "group_\(g)"
            headings.append(makeHeading(id: groupId, level: 1, title: "Group \(g)", ord: headingOrd))
            headingOrd += 1
            allHeadingIds.append(groupId)

            for s in 0..<5 {
                let subId = "sub_\(g)_\(s)"
                headings.append(makeHeading(id: subId, parentId: groupId, level: 2, title: "Sub \(g) \(s)", ord: headingOrd))
                headingOrd += 1
                allHeadingIds.append(subId)
            }
        }

        var entries: [Entry] = []
        entries.reserveCapacity(22_000)

        // 22,000 synthetic entries
        for i in 0..<22_000 {
            let hid: String? = (i % 20 == 0) ? nil : allHeadingIds[i % allHeadingIds.count]
            entries.append(makeEntry(id: "entry_\(i)", headingId: hid, ord: i, name: "Site \(i)"))
        }

        var notes: [Note] = []
        notes.reserveCapacity(500)
        for i in 0..<500 {
            let hid: String? = (i % 10 == 0) ? nil : allHeadingIds[i % allHeadingIds.count]
            notes.append(makeNote(id: "note_\(i)", headingId: hid, ord: i, text: "Note \(i)"))
        }

        let start = Date()

        let groups = SectionOutline.topGroups(headings: headings, entries: entries)
        XCTAssertFalse(groups.isEmpty)

        for group in groups {
            let sections = SectionOutline.sections(
                forGroup: group.id,
                headings: headings,
                entries: entries,
                notes: notes
            )
            XCTAssertFalse(sections.isEmpty)
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "Performance test with 22,000 entries took \(elapsed)s (must finish under 1.0s)")
    }
}

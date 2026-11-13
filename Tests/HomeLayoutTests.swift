import XCTest
@testable import FMHY

final class HomeLayoutTests: XCTestCase {
    func testDefaultLayout() {
        let layout = HomeLayout.default
        XCTAssertEqual(layout.entries.count, 8)

        let expectedBlocks: [HomeBlock] = [
            .search,
            .newSince,
            .randomPick,
            .pinned,
            .newInPinned,
            .favourites,
            .suggestions,
            .sections
        ]
        XCTAssertEqual(layout.entries.map { $0.block }, expectedBlocks)

        XCTAssertTrue(layout.isEnabled(.search))
        XCTAssertTrue(layout.isEnabled(.newSince))
        XCTAssertTrue(layout.isEnabled(.randomPick))
        XCTAssertFalse(layout.isEnabled(.pinned))
        XCTAssertFalse(layout.isEnabled(.newInPinned))
        XCTAssertFalse(layout.isEnabled(.favourites))
        XCTAssertFalse(layout.isEnabled(.suggestions))
        XCTAssertTrue(layout.isEnabled(.sections))

        let expectedEnabled: [HomeBlock] = [.search, .newSince, .randomPick, .sections]
        XCTAssertEqual(layout.enabledBlocks, expectedEnabled)
    }

    func testEncodeDecodeRoundTrip() {
        let defaultLayout = HomeLayout.default
        let encoded = defaultLayout.encode()
        let decoded = HomeLayout.decode(encoded)
        XCTAssertEqual(decoded, defaultLayout)

        let custom = defaultLayout
            .withEnabled(.pinned, on: true)
            .withEnabled(.search, on: false)
            .move(from: 0, to: 4)
        let customDecoded = HomeLayout.decode(custom.encode())
        XCTAssertEqual(customDecoded, custom)
    }

    func testDecodeNilBlankGarbageReturnsDefault() {
        XCTAssertEqual(HomeLayout.decode(nil), HomeLayout.default)
        XCTAssertEqual(HomeLayout.decode(""), HomeLayout.default)
        XCTAssertEqual(HomeLayout.decode("   \n\t  "), HomeLayout.default)
        XCTAssertEqual(HomeLayout.decode("garbage"), HomeLayout.default)
        XCTAssertEqual(HomeLayout.decode("foo:bar:baz"), HomeLayout.default)
        XCTAssertEqual(HomeLayout.decode("random_string_no_colons"), HomeLayout.default)
    }

    func testUnknownNamesAndBadFlagsDropped() {
        let input = "UNKNOWN:1,search:1,BAD_NAME:0,sections:1"
        let layout = HomeLayout.decode(input)
        XCTAssertEqual(layout.entries.count, 8)
        XCTAssertTrue(layout.isEnabled(.search))
        XCTAssertTrue(layout.isEnabled(.sections))

        let badFlagInput = "search:yes,sections:1"
        let badFlagLayout = HomeLayout.decode(badFlagInput)
        XCTAssertEqual(badFlagLayout.entries.count, 8)
        // search had an invalid flag so it was dropped and then re-inserted with default state (true)
        XCTAssertTrue(badFlagLayout.isEnabled(.search))
        XCTAssertTrue(badFlagLayout.isEnabled(.sections))
    }

    func testDuplicatesKeepFirst() {
        let input = "search:0,search:1,sections:1"
        let layout = HomeLayout.decode(input)
        XCTAssertFalse(layout.isEnabled(.search))
        XCTAssertTrue(layout.isEnabled(.sections))
        XCTAssertEqual(layout.entries.count, 8)
    }

    func testMissingBlocksReinsertedAtDefaultPosition() {
        let input = "sections:1,search:0"
        let layout = HomeLayout.decode(input)
        XCTAssertEqual(layout.entries.count, 8)
        XCTAssertEqual(layout.entries.first?.block, .sections)
        XCTAssertFalse(layout.isEnabled(.search))
        XCTAssertTrue(layout.isEnabled(.sections))
        // Verify all 8 blocks are present exactly once
        let setOfBlocks = Set(layout.entries.map { $0.block })
        XCTAssertEqual(setOfBlocks.count, 8)

        // Android format upper snake-case compatibility
        let androidStr = "SEARCH:1,NEW_SINCE:1,RANDOM_PICK:1,PINNED:0,NEW_IN_PINNED:0,FAVOURITES:0,SUGGESTIONS:0,SECTIONS:1"
        let androidDecoded = HomeLayout.decode(androidStr)
        XCTAssertEqual(androidDecoded, HomeLayout.default)
    }

    func testMove() {
        let initial = HomeLayout.default
        let moved = initial.move(from: 0, to: 2)
        XCTAssertEqual(moved.entries[0].block, .newSince)
        XCTAssertEqual(moved.entries[1].block, .randomPick)
        XCTAssertEqual(moved.entries[2].block, .search)

        // Invalid indices
        XCTAssertEqual(initial.move(from: -1, to: 2), initial)
        XCTAssertEqual(initial.move(from: 0, to: 99), initial)
        XCTAssertEqual(initial.move(from: 2, to: 2), initial)
    }

    func testWithEnabled() {
        let initial = HomeLayout.default
        let enabledPinned = initial.withEnabled(.pinned, on: true)
        XCTAssertTrue(enabledPinned.isEnabled(.pinned))

        let disabledSearch = initial.withEnabled(.search, on: false)
        XCTAssertFalse(disabledSearch.isEnabled(.search))
    }

    func testReset() {
        let modified = HomeLayout.default
            .withEnabled(.pinned, on: true)
            .move(from: 0, to: 5)
        XCTAssertNotEqual(modified, HomeLayout.default)
        XCTAssertEqual(modified.reset(), HomeLayout.default)
    }
}

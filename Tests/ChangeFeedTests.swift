import XCTest
@testable import FMHY

final class ChangeFeedTests: XCTestCase {
    private let fixtureBase64 = "H4sIAAAAAAAC/2WPQW6DMBBF7zJrC0KAluYA2eUEEUJTZgJWsR3ZJhBVvXvHSSMh1bL8PW/x/P0NoR/ZIBwKBQNb9hiZOowC3j+quijfikYB4T0I2e8UXDRPJMMZYgAFX9qSROA+amc7nQaLhiVmP8lJHFGnS++M0bELI0Ir04h24OQ5p4equm6aSgEScVLcNLGTPLnbXWKM8RoOeb4sS2YEZWHNBcvGz77Yl2J8anZpSZ2I3j9EOJNOoqNzG8/FuYxXNNeJt57q5Sn/PPKF7tl0W+o46ZX9VvcA2UD/WZhf8hra9ucXMzMkRnABAAA="

    func testDecodingYieldsThreeRowsInOrderWithCorrectFields() throws {
        guard let fixtureData = Data(base64Encoded: fixtureBase64) else {
            XCTFail("Failed to base64 decode fixture")
            return
        }

        let changes = try ChangeFeedDecoder.decode(gzip: fixtureData)
        XCTAssertEqual(changes.count, 3)

        // 1. added video "Movy" https://www.movy.sx/
        let first = changes[0]
        XCTAssertEqual(first.ts, 1794455884)
        XCTAssertEqual(first.kind, "added")
        XCTAssertEqual(first.sectionId, "video")
        XCTAssertEqual(first.name, "Movy")
        XCTAssertEqual(first.url, "https://www.movy.sx/")
        XCTAssertEqual(first.detail, "")
        XCTAssertEqual(first.commit, "abc123")

        // 2. starred audio "Foo" https://foo.example/
        let second = changes[1]
        XCTAssertEqual(second.ts, 1794400000)
        XCTAssertEqual(second.kind, "starred")
        XCTAssertEqual(second.sectionId, "audio")
        XCTAssertEqual(second.name, "Foo")
        XCTAssertEqual(second.url, "https://foo.example/")
        XCTAssertEqual(second.detail, "")
        XCTAssertEqual(second.commit, "abc124")

        // 3. url_changed video "Flixer" https://flixer.gd with detail https://flixer.su
        let third = changes[2]
        XCTAssertEqual(third.ts, 1794300000)
        XCTAssertEqual(third.kind, "url_changed")
        XCTAssertEqual(third.sectionId, "video")
        XCTAssertEqual(third.name, "Flixer")
        XCTAssertEqual(third.url, "https://flixer.gd")
        XCTAssertEqual(third.detail, "https://flixer.su")
        XCTAssertEqual(third.commit, "abc125")

        // Verify strictly descending order
        XCTAssertGreaterThan(first.ts, second.ts)
        XCTAssertGreaterThan(second.ts, third.ts)
    }

    func testGunzipProducesValidJSON() throws {
        guard let fixtureData = Data(base64Encoded: fixtureBase64) else {
            XCTFail("Failed to base64 decode fixture")
            return
        }

        let jsonData = try ChangeFeedDecoder.gunzip(fixtureData)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
        guard let dict = jsonObject as? [String: Any] else {
            XCTFail("Expected JSON dictionary at root")
            return
        }

        XCTAssertEqual(dict["schema"] as? Int, 1)
        XCTAssertEqual(dict["days"] as? Int, 120)
        let rows = dict["changes"] as? [[Any]]
        XCTAssertEqual(rows?.count, 3)
    }

    func testGarbageBytesThrows() {
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])
        XCTAssertThrowsError(try ChangeFeedDecoder.gunzip(garbage))
        XCTAssertThrowsError(try ChangeFeedDecoder.decode(gzip: garbage))

        let fakeGzipHeader = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF])
        XCTAssertThrowsError(try ChangeFeedDecoder.gunzip(fakeGzipHeader))
    }

    @MainActor
    func testFollowsTogglesAndPersists() {
        let suiteName = "test.follows.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let follows = Follows(userDefaults: defaults)
        XCTAssertTrue(follows.isEmpty)
        XCTAssertFalse(follows.isFollowing("video"))

        follows.toggle("video")
        XCTAssertFalse(follows.isEmpty)
        XCTAssertTrue(follows.isFollowing("video"))

        // Create a new instance with same defaults to verify persistence
        let restored = Follows(userDefaults: defaults)
        XCTAssertFalse(restored.isEmpty)
        XCTAssertTrue(restored.isFollowing("video"))

        // Toggle again to remove
        follows.toggle("video")
        XCTAssertTrue(follows.isEmpty)
        XCTAssertFalse(follows.isFollowing("video"))

        let restoredAfterRemove = Follows(userDefaults: defaults)
        XCTAssertTrue(restoredAfterRemove.isEmpty)
    }

    func testNameCleaningRemovesInvisibleCharacters() {
        let dirty = "Clean\u{2060}Name\u{200B}Here"
        let cleaned = ChangeFeedDecoder.cleanInvisibleCharacters(dirty)
        XCTAssertEqual(cleaned, "CleanNameHere")
        XCTAssertFalse(cleaned.contains("\u{2060}"))
        XCTAssertFalse(cleaned.contains("\u{200B}"))
    }

    @MainActor
    func testChangesStoreNewCountLogic() {
        let suiteName = "test.changes.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ChangesStore(userDefaults: defaults)
        let sampleChanges = [
            WikiChange(ts: 500, kind: "added", sectionId: "video", name: "Site A", url: "https://a.com", detail: "", commit: "c1"),
            WikiChange(ts: 400, kind: "starred", sectionId: "audio", name: "Site B", url: "https://b.com", detail: "", commit: "c2"),
            WikiChange(ts: 300, kind: "removed", sectionId: "video", name: "Site C", url: "https://c.com", detail: "", commit: "c3"),
            WikiChange(ts: 200, kind: "edited", sectionId: "audio", name: "Site D", url: "https://d.com", detail: "", commit: "c4"),
            WikiChange(ts: 100, kind: "added", sectionId: "video", name: "Site E", url: "https://e.com", detail: "", commit: "c5")
        ]

        store.setChangesForTesting(sampleChanges)

        // At first run with sampleChanges, lastSeenTs was set to newest (500)
        XCTAssertEqual(store.lastSeenTs, 500)
        XCTAssertEqual(store.newCount(followed: nil), 0)

        // Set lastSeenTs to 250
        store.lastSeenTs = 250
        // Qualifying with ts > 250 and (added or starred):
        // ts 500 (added, video) and ts 400 (starred, audio) -> count 2
        // ts 300 is removed (excluded)
        XCTAssertEqual(store.newCount(followed: nil), 2)

        // Restricted to followed "video": only ts 500 -> count 1
        XCTAssertEqual(store.newCount(followed: ["video"]), 1)

        // Restricted to followed "audio": only ts 400 -> count 1
        XCTAssertEqual(store.newCount(followed: ["audio"]), 1)

        // Restricted to followed "misc": none -> count 0
        XCTAssertEqual(store.newCount(followed: ["misc"]), 0)

        // Empty followed set: unrestricted -> count 2
        XCTAssertEqual(store.newCount(followed: []), 2)
    }

    @MainActor
    func testRecentlyAddedURLs() {
        let store = ChangesStore()
        let nowTs = Int(Date().timeIntervalSince1970)
        let change = WikiChange(ts: nowTs, kind: "added", sectionId: "video", name: "Site", url: "https://example.com/test/", detail: "", commit: "c1")
        store.setChangesForTesting([change])

        XCTAssertTrue(store.isRecentlyAdded(url: "https://example.com/test"))
        XCTAssertTrue(store.isRecentlyAdded(url: "https://example.com/test/"))
        XCTAssertTrue(store.isRecentlyAdded(url: "HTTPS://EXAMPLE.COM/TEST/"))
        XCTAssertFalse(store.isRecentlyAdded(url: "https://other.com"))
    }
}

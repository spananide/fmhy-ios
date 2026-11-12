import XCTest
import SwiftUI
@testable import FMHY

final class SettingsTests: XCTestCase {

    private var savedBookmarksData: Data?
    private var savedFollowsData: Data?

    override func setUp() {
        super.setUp()
        savedBookmarksData = UserDefaults.standard.data(forKey: "bookmarks.v1")
        savedFollowsData = UserDefaults.standard.data(forKey: "follows.v1")
        UserDefaults.standard.removeObject(forKey: "bookmarks.v1")
        UserDefaults.standard.removeObject(forKey: "follows.v1")
    }

    override func tearDown() {
        if let saved = savedBookmarksData {
            UserDefaults.standard.set(saved, forKey: "bookmarks.v1")
        } else {
            UserDefaults.standard.removeObject(forKey: "bookmarks.v1")
        }
        if let saved = savedFollowsData {
            UserDefaults.standard.set(saved, forKey: "follows.v1")
        } else {
            UserDefaults.standard.removeObject(forKey: "follows.v1")
        }
        super.tearDown()
    }

    // MARK: - BackupIO Tests

    func testBackupIORoundTrip() throws {
        // Floor date to second boundary because ISO8601 encoding strips fractional seconds
        let exportedDate = Date(timeIntervalSince1970: 1731448800)
        let backup = BackupFile(
            version: 1,
            exportedAt: exportedDate,
            bookmarks: ["entry-1", "entry-2"],
            follows: ["privacy", "video"],
            settings: [
                "theme": "dark",
                "accent": "blue",
                "textSize": "large",
                "searchEngine": "google",
                "openInSafari": "true",
                "wifiOnly": "false",
                "adblock": "true"
            ]
        )

        let encoded = try BackupIO.encode(backup)
        let decoded = try BackupIO.decode(encoded)

        XCTAssertEqual(decoded.version, backup.version)
        XCTAssertEqual(decoded.exportedAt, backup.exportedAt)
        XCTAssertEqual(decoded.bookmarks, backup.bookmarks)
        XCTAssertEqual(decoded.follows, backup.follows)
        XCTAssertEqual(decoded.settings, backup.settings)
    }

    func testBackupIODecodeGarbageThrows() {
        let garbage = Data("this is completely invalid json".utf8)
        XCTAssertThrowsError(try BackupIO.decode(garbage))
    }

    func testBackupIODecodeFutureVersionThrows() {
        let futureJSON = """
        {
            "version": 99,
            "exportedAt": "2026-11-12T20:00:00Z",
            "bookmarks": [],
            "follows": [],
            "settings": {}
        }
        """
        let data = Data(futureJSON.utf8)
        XCTAssertThrowsError(try BackupIO.decode(data)) { error in
            guard let backupError = error as? BackupError else {
                XCTFail("Expected BackupError, got \(error)")
                return
            }
            if case .unsupportedVersion(let v) = backupError {
                XCTAssertEqual(v, 99)
            } else {
                XCTFail("Expected unsupportedVersion(99), got \(backupError)")
            }
        }
    }

    // MARK: - Bookmarks and Follows Merge Tests

    @MainActor
    func testBookmarksMergeReturnsAddedCountsAndDoesNotDuplicate() {
        let bookmarks = Bookmarks()
        XCTAssertEqual(bookmarks.ids, [])

        let firstAdded = bookmarks.merge(ids: ["id1", "id2", "id3"])
        XCTAssertEqual(firstAdded, 3)
        XCTAssertEqual(bookmarks.ids, ["id1", "id2", "id3"])

        let secondAdded = bookmarks.merge(ids: ["id2", "id3", "id4", "id5"])
        XCTAssertEqual(secondAdded, 2)
        XCTAssertEqual(bookmarks.ids, ["id1", "id2", "id3", "id4", "id5"])

        let noAdded = bookmarks.merge(ids: ["id1", "id5"])
        XCTAssertEqual(noAdded, 0)
        XCTAssertEqual(bookmarks.ids, ["id1", "id2", "id3", "id4", "id5"])
    }

    @MainActor
    func testFollowsMergeReturnsAddedCountsAndDoesNotDuplicate() {
        let follows = Follows()
        XCTAssertTrue(follows.isEmpty)

        let firstAdded = follows.merge(ids: ["video", "gaming"])
        XCTAssertEqual(firstAdded, 2)
        XCTAssertTrue(follows.isFollowing("video"))
        XCTAssertTrue(follows.isFollowing("gaming"))

        let secondAdded = follows.merge(ids: ["gaming", "privacy"])
        XCTAssertEqual(secondAdded, 1)
        XCTAssertTrue(follows.isFollowing("privacy"))

        let noAdded = follows.merge(ids: ["video", "privacy"])
        XCTAssertEqual(noAdded, 0)
    }

    // MARK: - SearchEngineChoice Tests

    func testSearchEngineChoiceSearchURL() throws {
        let query = "a b&c"

        let engines: [(SearchEngineChoice, String)] = [
            (.duckDuckGo, "duckduckgo.com"),
            (.google, "www.google.com"),
            (.bing, "www.bing.com"),
            (.brave, "search.brave.com"),
            (.startpage, "www.startpage.com")
        ]

        for (engine, expectedHost) in engines {
            let url = try XCTUnwrap(engine.searchURL(for: query), "URL should be valid for \(engine)")
            XCTAssertEqual(url.host, expectedHost, "Host mismatch for \(engine)")
            XCTAssertTrue(url.absoluteString.contains("a%20b%26c"), "URL string should contain percent-encoded query for \(engine)")
        }
    }

    // MARK: - AppTheme ColorScheme Tests

    func testAppThemeColorScheme() {
        XCTAssertEqual(AppTheme.black.colorScheme, .dark)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertNil(AppTheme.system.colorScheme)
    }
}

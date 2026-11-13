import XCTest
@testable import FMHY

final class SiteCheckTests: XCTestCase {

    // MARK: - VtSiteChecks Tests

    @MainActor
    func testShouldRememberOnlyNoFlags() {
        XCTAssertTrue(VtSiteChecks.shouldRemember(.noFlags))
        XCTAssertFalse(VtSiteChecks.shouldRemember(.suspicious))
        XCTAssertFalse(VtSiteChecks.shouldRemember(.dangerous))
        XCTAssertFalse(VtSiteChecks.shouldRemember(.unknown))
    }

    @MainActor
    func testNormalizeHost() {
        XCTAssertEqual(VtSiteChecks.normalizeHost("  ExAmPlE.CoM  "), "example.com")
        XCTAssertEqual(VtSiteChecks.normalizeHost("\n\tFOO.BAR\t\n"), "foo.bar")
        XCTAssertEqual(VtSiteChecks.normalizeHost("already.normal"), "already.normal")
    }

    @MainActor
    func testRememberAndExpiry30Days() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtsites-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let siteChecks = VtSiteChecks(fileURL: tempURL, now: { currentTime })

        XCTAssertFalse(siteChecks.hasMarks)
        XCTAssertNil(siteChecks.markFor(host: "example.com"))

        siteChecks.remember(host: "Example.COM", flagged: 0, engines: 70)
        XCTAssertTrue(siteChecks.hasMarks)

        let mark = siteChecks.markFor(host: "example.com")
        XCTAssertNotNil(mark)
        XCTAssertEqual(mark?.flagged, 0)
        XCTAssertEqual(mark?.engines, 70)
        XCTAssertEqual(mark?.checkedAt, currentTime)

        // Advance 29 days (less than 30 days TTL) -> still valid
        currentTime = currentTime.addingTimeInterval(29 * 24 * 60 * 60)
        XCTAssertNotNil(siteChecks.markFor(host: "example.com"))
        XCTAssertTrue(siteChecks.hasMarks)

        // Advance 2 more days (31 days total, > 30 days TTL) -> expired
        currentTime = currentTime.addingTimeInterval(2 * 24 * 60 * 60)
        XCTAssertNil(siteChecks.markFor(host: "example.com"))
        XCTAssertFalse(siteChecks.hasMarks)
    }

    @MainActor
    func testCapOf500Entries() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtsites-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let siteChecks = VtSiteChecks(fileURL: tempURL, now: { currentTime })

        // Add 505 entries with increasing timestamps
        for i in 0..<505 {
            currentTime = currentTime.addingTimeInterval(1.0)
            siteChecks.remember(host: "site\(i).com", flagged: 0, engines: 70)
        }

        XCTAssertEqual(siteChecks.marks.count, 500)

        // Oldest 5 entries (site0 ... site4) should have been pruned
        for i in 0..<5 {
            XCTAssertNil(siteChecks.markFor(host: "site\(i).com"))
        }

        // Newest entries (site5 ... site504) should be kept
        for i in 5..<505 {
            XCTAssertNotNil(siteChecks.markFor(host: "site\(i).com"))
        }
    }

    @MainActor
    func testForgetAll() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtsites-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let siteChecks = VtSiteChecks(fileURL: tempURL, now: { currentTime })

        siteChecks.remember(host: "alpha.com", flagged: 0, engines: 70)
        siteChecks.remember(host: "beta.com", flagged: 0, engines: 70)
        XCTAssertTrue(siteChecks.hasMarks)
        XCTAssertEqual(siteChecks.marks.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        siteChecks.forgetAll()
        XCTAssertFalse(siteChecks.hasMarks)
        XCTAssertEqual(siteChecks.marks.count, 0)
        XCTAssertNil(siteChecks.markFor(host: "alpha.com"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    @MainActor
    func testPersistenceAcrossInstances() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtsites-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let instanceOne = VtSiteChecks(fileURL: tempURL, now: { currentTime })
        instanceOne.remember(host: "persisted.com", flagged: 0, engines: 65)

        let instanceTwo = VtSiteChecks(fileURL: tempURL, now: { currentTime })
        let loadedMark = instanceTwo.markFor(host: "persisted.com")
        XCTAssertNotNil(loadedMark)
        XCTAssertEqual(loadedMark?.flagged, 0)
        XCTAssertEqual(loadedMark?.engines, 65)

        // If time advances beyond 30 days, instanceThree filters it out on load
        currentTime = currentTime.addingTimeInterval(31 * 24 * 60 * 60)
        let instanceThree = VtSiteChecks(fileURL: tempURL, now: { currentTime })
        XCTAssertFalse(instanceThree.hasMarks)
        XCTAssertNil(instanceThree.markFor(host: "persisted.com"))
    }

    // MARK: - UrlExtractor Tests

    func testLooksLikeUrl() {
        // Positive cases
        XCTAssertTrue(UrlExtractor.looksLikeUrl("example.com"))
        XCTAssertTrue(UrlExtractor.looksLikeUrl("sub.domain.org"))
        XCTAssertTrue(UrlExtractor.looksLikeUrl("http://example.com"))
        XCTAssertTrue(UrlExtractor.looksLikeUrl("https://example.com/path?foo=bar#hash"))
        XCTAssertTrue(UrlExtractor.looksLikeUrl("localhost"))
        XCTAssertTrue(UrlExtractor.looksLikeUrl("localhost:8080"))
        XCTAssertTrue(UrlExtractor.looksLikeUrl("localhost/test"))
        XCTAssertTrue(UrlExtractor.looksLikeUrl("192.168.1.1"))

        // Negative cases
        XCTAssertFalse(UrlExtractor.looksLikeUrl(""))
        XCTAssertFalse(UrlExtractor.looksLikeUrl("   "))
        XCTAssertFalse(UrlExtractor.looksLikeUrl("hello world"))
        XCTAssertFalse(UrlExtractor.looksLikeUrl("just text"))
        XCTAssertFalse(UrlExtractor.looksLikeUrl("localhost foo"))
        XCTAssertFalse(UrlExtractor.looksLikeUrl("example .com"))
        XCTAssertFalse(UrlExtractor.looksLikeUrl("not_a_url"))
    }

    func testExtractFirstUrl() {
        XCTAssertEqual(
            UrlExtractor.extractFirstUrl("Visit https://fmhy.net/privacy for info"),
            "https://fmhy.net/privacy"
        )
        XCTAssertEqual(
            UrlExtractor.extractFirstUrl("Check out fmhy.net."),
            "fmhy.net"
        )
        XCTAssertEqual(
            UrlExtractor.extractFirstUrl("Here is a link: (https://example.com/test?a=1),"),
            "https://example.com/test?a=1"
        )
        XCTAssertEqual(
            UrlExtractor.extractFirstUrl("No links here"),
            "No links here"
        )
        XCTAssertEqual(
            UrlExtractor.extractFirstUrl(""),
            ""
        )
    }

    func testExtractHost() {
        XCTAssertEqual(UrlExtractor.extractHost(from: "Check out https://www.fmhy.net/privacy"), "fmhy.net")
        XCTAssertEqual(UrlExtractor.extractHost(from: "https://sub.domain.org/path"), "sub.domain.org")
        XCTAssertEqual(UrlExtractor.extractHost(from: "example.org"), "example.org")
        XCTAssertNil(UrlExtractor.extractHost(from: "just some random text"))
    }

    func testUrlHasPath() {
        XCTAssertFalse(UrlExtractor.urlHasPath("example.com"))
        XCTAssertFalse(UrlExtractor.urlHasPath("example.com/"))
        XCTAssertFalse(UrlExtractor.urlHasPath("https://example.com"))
        XCTAssertFalse(UrlExtractor.urlHasPath("https://example.com/"))
        XCTAssertTrue(UrlExtractor.urlHasPath("example.com/path"))
        XCTAssertTrue(UrlExtractor.urlHasPath("https://example.com/a/b"))
    }

    func testHostForCheckJustHost() {
        let noDataWithPath = Verdict(
            status: .noData,
            input: "example.com/path",
            normalizedUrl: "https://example.com/path",
            host: "example.com",
            reason: nil,
            matches: [],
            lookalikes: []
        )
        XCTAssertEqual(UrlExtractor.hostForCheckJustHost(verdict: noDataWithPath), "example.com")

        let noDataNoPath = Verdict(
            status: .noData,
            input: "example.com",
            normalizedUrl: "https://example.com",
            host: "example.com",
            reason: nil,
            matches: [],
            lookalikes: []
        )
        XCTAssertNil(UrlExtractor.hostForCheckJustHost(verdict: noDataNoPath))

        let listedWithPath = Verdict(
            status: .listed,
            input: "example.com/path",
            normalizedUrl: "https://example.com/path",
            host: "example.com",
            reason: nil,
            matches: [],
            lookalikes: []
        )
        XCTAssertNil(UrlExtractor.hostForCheckJustHost(verdict: listedWithPath))
    }

    // MARK: - CheckLogic Tests

    func testPruneRecentChecksTypingStages() {
        let items = [
            RecentCheck(url: "example.com", status: .listed, ts: Date(timeIntervalSince1970: 200)),
            RecentCheck(url: "exa", status: .listed, ts: Date(timeIntervalSince1970: 100)),
            RecentCheck(url: "other.org", status: .noData, ts: Date(timeIntervalSince1970: 150))
        ]

        let pruned = UrlExtractor.pruneRecentChecks(items)
        XCTAssertEqual(pruned.count, 2)
        XCTAssertEqual(pruned[0].url, "example.com")
        XCTAssertEqual(pruned[1].url, "other.org")
    }

    func testPruneRecentChecksDuplicates() {
        let items = [
            RecentCheck(url: "EXAMPLE.COM", status: .listed, ts: Date(timeIntervalSince1970: 200)),
            RecentCheck(url: "example.com", status: .listed, ts: Date(timeIntervalSince1970: 100))
        ]

        let pruned = UrlExtractor.pruneRecentChecks(items)
        XCTAssertEqual(pruned.count, 1)
        XCTAssertEqual(pruned[0].url, "EXAMPLE.COM")
    }

    func testMatchBreadcrumb() {
        // Section matches first element of headingPath -> deduplicated
        let c1 = UrlExtractor.matchBreadcrumb(
            sectionTitle: "Privacy",
            headingPath: "Privacy > Adblockers > DNS"
        )
        XCTAssertEqual(c1, ["Privacy", "Adblockers", "DNS"])

        // Section does not match first element
        let c2 = UrlExtractor.matchBreadcrumb(
            sectionTitle: "Tools",
            headingPath: "System > Cleanup"
        )
        XCTAssertEqual(c2, ["Tools", "System", "Cleanup"])

        // Empty sectionTitle
        let c3 = UrlExtractor.matchBreadcrumb(
            sectionTitle: nil,
            headingPath: "Video > Streaming"
        )
        XCTAssertEqual(c3, ["Video", "Streaming"])

        // Empty headingPath
        let c4 = UrlExtractor.matchBreadcrumb(
            sectionTitle: "Audio",
            headingPath: ""
        )
        XCTAssertEqual(c4, ["Audio"])
    }
}

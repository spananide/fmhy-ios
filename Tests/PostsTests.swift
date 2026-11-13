import XCTest
@testable import FMHY

final class PostsTests: XCTestCase {

    func testMonthAndYearParsing() {
        let jan = PostsListing.parseMonthAndYear(from: "jan-2025.md")
        XCTAssertEqual(jan?.month, 1)
        XCTAssertEqual(jan?.year, 2025)

        let dec = PostsListing.parseMonthAndYear(from: "dec_2024.md")
        XCTAssertEqual(dec?.month, 12)
        XCTAssertEqual(dec?.year, 2024)

        let march = PostsListing.parseMonthAndYear(from: "march-2023")
        XCTAssertEqual(march?.month, 3)
        XCTAssertEqual(march?.year, 2023)

        let september = PostsListing.parseMonthAndYear(from: "september-2022.md")
        XCTAssertEqual(september?.month, 9)
        XCTAssertEqual(september?.year, 2022)

        let invalid = PostsListing.parseMonthAndYear(from: "announcement-post.md")
        XCTAssertNil(invalid)
    }

    func testParseDate() {
        let epochJan2025 = PostsListing.parseDate(fileName: "jan-2025.md", frontMatterDate: nil)
        // 2025-01-01 00:00:00 UTC = 1735689600
        XCTAssertEqual(epochJan2025, 1735689600)

        let epochWithFrontMatter = PostsListing.parseDate(fileName: "random.md", frontMatterDate: "2025-06-15")
        // 2025-06-15 00:00:00 UTC = 1750032000
        XCTAssertEqual(epochWithFrontMatter, 1750032000)

        let epochUnknown = PostsListing.parseDate(fileName: "unknown.md", frontMatterDate: nil)
        XCTAssertEqual(epochUnknown, 0)
    }

    func testFormatDefaultTitle() {
        XCTAssertEqual(PostsListing.formatDefaultTitle(fileName: "jan-2025.md"), "Monthly Updates [January 2025]")
        XCTAssertEqual(PostsListing.formatDefaultTitle(fileName: "feb_2024"), "Monthly Updates [February 2024]")
        XCTAssertEqual(PostsListing.formatDefaultTitle(fileName: "site-guidelines.md"), "Site Guidelines")
    }

    func testFormatDateText() {
        XCTAssertEqual(PostsListing.formatDateText(fileName: "jan-2025.md", frontMatterDate: nil, dateEpoch: 1735689600), "January 2025")
        XCTAssertEqual(PostsListing.formatDateText(fileName: "post.md", frontMatterDate: "2025-03-01", dateEpoch: 0), "2025-03-01")
        XCTAssertEqual(PostsListing.formatDateText(fileName: "other.md", frontMatterDate: nil, dateEpoch: 1735689600), "Jan 2025")
    }

    func testFrontMatterExtractionAndStripping() {
        let raw = """
        ---
        title: Custom Title
        date: 2025-05-10
        ---
        # Heading 1
        Here is the body content.
        """

        let (fm, body) = PostsListing.extractFrontMatter(raw)
        XCTAssertEqual(fm["title"], "Custom Title")
        XCTAssertEqual(fm["date"], "2025-05-10")
        XCTAssertEqual(body.trimmingCharacters(in: .whitespacesAndNewlines), "# Heading 1\nHere is the body content.")

        let stripped = PostsListing.stripFrontMatter(raw)
        XCTAssertEqual(stripped.trimmingCharacters(in: .whitespacesAndNewlines), "# Heading 1\nHere is the body content.")

        let plain = "# Hello World\nNo front matter here."
        let (emptyFm, plainBody) = PostsListing.extractFrontMatter(plain)
        XCTAssertTrue(emptyFm.isEmpty)
        XCTAssertEqual(plainBody, plain)
    }

    func testGitHubListingParsing() throws {
        let githubJSON = """
        [
          {"name": "jan-2025.md", "type": "file"},
          {"name": "feb-2025.md", "type": "file"},
          {"name": "assets", "type": "dir"},
          {"name": "info.txt", "type": "file"}
        ]
        """.data(using: .utf8)!

        let files = try PostsListing.parseGitHubListing(json: githubJSON)
        XCTAssertEqual(files, ["jan-2025.md", "feb-2025.md"])

        let jsdelivrJSON = """
        {
          "files": [
            {"name": "/docs/posts/jan-2025.md"},
            {"name": "/docs/posts/feb-2025.md"},
            {"name": "/docs/posts/nested/ignored.md"},
            {"name": "/docs/other.md"}
          ]
        }
        """.data(using: .utf8)!

        let jsdelivrFiles = try PostsListing.parseGitHubListing(json: jsdelivrJSON)
        XCTAssertEqual(jsdelivrFiles, ["jan-2025.md", "feb-2025.md"])
    }

    func testPostSiteRowParsing() {
        let boldRow = "- **[Braflix](https://braflix.st)** - Free movies and TV shows"
        let parsedBold = PostsListing.parsePostSiteRow(boldRow)
        XCTAssertNotNil(parsedBold)
        XCTAssertEqual(parsedBold?.name, "Braflix")
        XCTAssertEqual(parsedBold?.url, "https://braflix.st")
        XCTAssertEqual(parsedBold?.description, "Free movies and TV shows")

        let colonRow = "* [CyberChef](https://gchq.github.io/CyberChef/): The cyber Swiss Army knife"
        let parsedColon = PostsListing.parsePostSiteRow(colonRow)
        XCTAssertNotNil(parsedColon)
        XCTAssertEqual(parsedColon?.name, "CyberChef")
        XCTAssertEqual(parsedColon?.url, "https://gchq.github.io/CyberChef/")
        XCTAssertEqual(parsedColon?.description, "The cyber Swiss Army knife")

        let nonLink = "- Just a regular note without a site link"
        XCTAssertNil(PostsListing.parsePostSiteRow(nonLink))
    }

    @MainActor
    func testReadStateFirstRunAndMarkingRead() {
        let suiteName = "test.posts.read.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test UserDefaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = PostsStore(userDefaults: defaults)
        let post1 = WikiPost(path: "posts/jan-2025.md", title: "Jan 2025", date: 100)
        let post2 = WikiPost(path: "posts/feb-2025.md", title: "Feb 2025", date: 200)

        // First run: all posts loaded must be marked as read
        store.setPostsForTesting([post1, post2])
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(store.readPaths.contains("posts/jan-2025.md"))
        XCTAssertTrue(store.readPaths.contains("posts/feb-2025.md"))

        // Add a new post in subsequent run
        let post3 = WikiPost(path: "posts/mar-2025.md", title: "Mar 2025", date: 300)
        store.setPostsForTesting([post1, post2, post3])
        XCTAssertEqual(store.unreadCount, 1)
        XCTAssertFalse(store.readPaths.contains("posts/mar-2025.md"))

        // Mark it read
        store.markRead("posts/mar-2025.md")
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(store.readPaths.contains("posts/mar-2025.md"))

        // Verify persistence with a new store instance using the same defaults
        let restoredStore = PostsStore(userDefaults: defaults)
        restoredStore.setPostsForTesting([post1, post2, post3])
        XCTAssertEqual(restoredStore.unreadCount, 0)
    }

    func testNewPostsDecision() {
        let post1 = WikiPost(path: "posts/jan-2025.md", title: "Jan", date: 100)
        let post2 = WikiPost(path: "posts/feb-2025.md", title: "Feb", date: 200)
        let post3 = WikiPost(path: "posts/mar-2025.md", title: "Mar", date: 300)

        // First run returns empty list
        let firstRun = NewPostsDecision.newUnreadPosts(
            listed: [post1, post2],
            previouslyKnown: nil,
            read: nil
        )
        XCTAssertTrue(firstRun.isEmpty)

        // With baseline: only unknown and unread posts are returned
        let previouslyKnown: Set<String> = ["posts/jan-2025.md"]
        let read: Set<String> = ["posts/jan-2025.md", "posts/feb-2025.md"]
        let newPosts = NewPostsDecision.newUnreadPosts(
            listed: [post1, post2, post3],
            previouslyKnown: previouslyKnown,
            read: read
        )
        XCTAssertEqual(newPosts.count, 1)
        XCTAssertEqual(newPosts.first?.path, "posts/mar-2025.md")

        // Notification text
        let singleNotif = NewPostsDecision.newPostsNotificationText(newPosts: [post3])
        XCTAssertEqual(singleNotif?.title, "New FMHY post")
        XCTAssertEqual(singleNotif?.body, "Mar")

        let multipleNotif = NewPostsDecision.newPostsNotificationText(newPosts: [post3, post2])
        XCTAssertEqual(multipleNotif?.title, "New FMHY post")
        XCTAssertEqual(multipleNotif?.body, "Mar and 1 more")

        // Should check posts: at most once per 24 hours
        XCTAssertTrue(NewPostsDecision.shouldCheckPosts(lastCheckEpochSec: nil, nowSec: 1000))
        XCTAssertFalse(NewPostsDecision.shouldCheckPosts(lastCheckEpochSec: 1000, nowSec: 1000 + 3600))
        XCTAssertTrue(NewPostsDecision.shouldCheckPosts(lastCheckEpochSec: 1000, nowSec: 1000 + 86400))
        // Clock skew
        XCTAssertTrue(NewPostsDecision.shouldCheckPosts(lastCheckEpochSec: 2000, nowSec: 1000))
    }
}

import XCTest
@testable import FMHY

final class IssueUrlBuilderTests: XCTestCase {
    func testTitleFormatNormal() {
        let title = IssueUrlBuilder.buildTitle(area: .search, whatWentWrong: "Search results are empty")
        XCTAssertEqual(title, "[Search] Search results are empty")
    }

    func testTitleFormatEmpty() {
        let title = IssueUrlBuilder.buildTitle(area: .other, whatWentWrong: "")
        XCTAssertEqual(title, "[Other] (not described)")

        let whitespaceTitle = IssueUrlBuilder.buildTitle(area: .lists, whatWentWrong: "   \n\r  ")
        XCTAssertEqual(whitespaceTitle, "[Lists] (not described)")
    }

    func testTitleFormatTruncationAt60Chars() {
        let longDesc = String(repeating: "a", count: 100)
        let title = IssueUrlBuilder.buildTitle(area: .downloads, whatWentWrong: longDesc)
        let expectedDesc = String(repeating: "a", count: 60)
        XCTAssertEqual(title, "[Downloads] \(expectedDesc)")
    }

    func testTitleFormatNewlinesReplacedBySpaces() {
        let multiline = "Line 1\r\nLine 2\nLine 3"
        let title = IssueUrlBuilder.buildTitle(area: .update, whatWentWrong: multiline)
        XCTAssertEqual(title, "[Update] Line 1  Line 2 Line 3")
    }

    func testEncodingWithPercent20ForSpaces() {
        let encoded = IssueUrlBuilder.urlEncode("hello world test")
        XCTAssertEqual(encoded, "hello%20world%20test")
        XCTAssertFalse(encoded.contains("+"))

        let link = IssueUrlBuilder.build(title: "Test Title", body: "Test Body")
        XCTAssertTrue(link.url.contains("title=Test%20Title"))
        XCTAssertTrue(link.url.contains("body=Test%20Body"))
        XCTAssertFalse(link.url.contains("+"))
    }

    func testFullBodyKeptWhenShort() {
        let title = "[Search] Test"
        let body = "Short problem description\nNo need to truncate."
        let link = IssueUrlBuilder.build(title: title, body: body, maxLength: 7000)

        XCTAssertFalse(link.truncated)
        let expectedEncBody = IssueUrlBuilder.urlEncode(body)
        XCTAssertTrue(link.url.contains("body=\(expectedEncBody)"))
        XCTAssertLessThanOrEqual(link.url.count, 7000)
    }

    func testTruncationWhenExceedingMax() {
        let title = "[Other] Test"
        let manyLines = (1...200).map { "This is line number \($0) with lots of text to fill up the budget." }.joined(separator: "\n")
        let link = IssueUrlBuilder.build(title: title, body: manyLines, maxLength: 500)

        XCTAssertTrue(link.truncated)
        XCTAssertLessThanOrEqual(link.url.count, 500)
        XCTAssertTrue(link.url.contains(IssueUrlBuilder.urlEncode("(report shortened - the full text was copied)")))
    }

    func testUrlNeverLongerThanMaxUnderTightLimit() {
        let title = "[Other] Long title with extra content"
        let longBody = String(repeating: "Very long text that easily overflows. ", count: 50)
        let tightLimits = [200, 300, 500, 1000, 7000]

        for limit in tightLimits {
            let link = IssueUrlBuilder.build(title: title, body: longBody, maxLength: limit)
            XCTAssertLessThanOrEqual(link.url.count, limit, "URL exceeded max length \(limit)")
        }
    }
}

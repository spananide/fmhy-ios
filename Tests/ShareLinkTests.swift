import XCTest
@testable import FMHY

final class ShareLinkTests: XCTestCase {
    func testBasicRoundTrip() {
        let input = "https://fmhy.net"
        guard let checkURL = UrlExtractor.buildCheckURL(for: input) else {
            XCTFail("Failed to build check URL for \(input)")
            return
        }
        let parsed = UrlExtractor.parseCheckURL(checkURL)
        XCTAssertEqual(parsed, input)
    }

    func testRoundTripWithQueryCharacters() {
        let input = "https://example.com/search?q=swift%20testing&filter=all&page=1#section"
        guard let checkURL = UrlExtractor.buildCheckURL(for: input) else {
            XCTFail("Failed to build check URL for query link")
            return
        }
        let parsed = UrlExtractor.parseCheckURL(checkURL)
        XCTAssertEqual(parsed, input)
    }

    func testRoundTripWithMultipleQueryParametersAndSpecialChars() {
        let input = "https://example.com/api?a=1&b=test&c=foo%26bar%3Dbaz"
        guard let checkURL = UrlExtractor.buildCheckURL(for: input) else {
            XCTFail("Failed to build check URL")
            return
        }
        let parsed = UrlExtractor.parseCheckURL(checkURL)
        XCTAssertEqual(parsed, input)
    }

    func testRoundTripWithSpaces() {
        let input = "https://example.com/files/my special document.pdf"
        guard let checkURL = UrlExtractor.buildCheckURL(for: input) else {
            XCTFail("Failed to build check URL for link with spaces")
            return
        }
        let parsed = UrlExtractor.parseCheckURL(checkURL)
        XCTAssertEqual(parsed, input)
    }

    func testRoundTripWithUnicode() {
        let input = "https://example.com/wiki/Café_München_日本語?tag=über"
        guard let checkURL = UrlExtractor.buildCheckURL(for: input) else {
            XCTFail("Failed to build check URL for unicode link")
            return
        }
        let parsed = UrlExtractor.parseCheckURL(checkURL)
        XCTAssertEqual(parsed, input)
    }

    func testRejectNonHttpSchemesInBuild() {
        let invalidLinks = [
            "ftp://files.example.com/download.zip",
            "javascript:alert('xss')",
            "file:///Users/test/secret.txt",
            "data:text/plain;base64,SGVsbG8=",
            "fmhy://open?url=https://example.com",
            "mailto:admin@example.com",
            "tel:+1234567890",
            "sms:+1234567890"
        ]

        for link in invalidLinks {
            let result = UrlExtractor.buildCheckURL(for: link)
            XCTAssertNil(result, "Expected nil for non-http scheme link: \(link)")
        }
    }

    func testRejectNonHttpSchemesInParse() {
        let invalidDeepLinks = [
            "fmhy://check?url=ftp://files.example.com",
            "fmhy://check?url=javascript:alert(1)",
            "fmhy://check?url=file:///etc/passwd",
            "fmhy://check?url=data:text/html,test",
            "fmhy://check?url=fmhy://search"
        ]

        for deepLinkString in invalidDeepLinks {
            guard let url = URL(string: deepLinkString) else {
                continue
            }
            let parsed = UrlExtractor.parseCheckURL(url)
            XCTAssertNil(parsed, "Expected nil when parsing non-http URL in query: \(deepLinkString)")
        }
    }

    func testRejectEmptyOrInvalidInputs() {
        XCTAssertNil(UrlExtractor.buildCheckURL(for: ""))
        XCTAssertNil(UrlExtractor.buildCheckURL(for: "   "))
        XCTAssertNil(UrlExtractor.buildCheckURL(for: "http://"))
        XCTAssertNil(UrlExtractor.buildCheckURL(for: "https://"))
        XCTAssertNil(UrlExtractor.buildCheckURL(for: "just some random text"))
    }

    func testParseInvalidCheckURLs() {
        if let nonFmhy = URL(string: "https://fmhy.net/check?url=https://example.com") {
            XCTAssertNil(UrlExtractor.parseCheckURL(nonFmhy))
        }

        if let searchAction = URL(string: "fmhy://search?url=https://example.com") {
            XCTAssertNil(UrlExtractor.parseCheckURL(searchAction))
        }

        if let missingParam = URL(string: "fmhy://check") {
            XCTAssertNil(UrlExtractor.parseCheckURL(missingParam))
        }

        if let otherParam = URL(string: "fmhy://check?other=https://example.com") {
            XCTAssertNil(UrlExtractor.parseCheckURL(otherParam))
        }
    }

    func testHttpSchemeAllowed() {
        let httpLink = "http://insecure.example.com/test"
        guard let checkURL = UrlExtractor.buildCheckURL(for: httpLink) else {
            XCTFail("Failed to build check URL for http scheme")
            return
        }
        let parsed = UrlExtractor.parseCheckURL(checkURL)
        XCTAssertEqual(parsed, httpLink)
    }
}

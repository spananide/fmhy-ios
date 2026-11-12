import XCTest
import WebKit
@testable import FMHY

final class AdBlockTests: XCTestCase {

    func testCosmeticCSS() {
        let css = AdBlocker.cosmeticCSS
        XCTAssertTrue(css.contains("onetrust"))
        XCTAssertTrue(css.contains("display:none"))
    }

    @MainActor
    func testCompilesBundledRules() async {
        let n = await AdBlocker.shared.compileAll()
        XCTAssertGreaterThanOrEqual(n, 1)
        XCTAssertEqual(AdBlocker.shared.lists.count, n)
        let second = await AdBlocker.shared.compileAll()
        XCTAssertEqual(second, n)
    }

    @MainActor
    func testCompileInlineRule() async {
        guard let store = WKContentRuleListStore.default() else {
            XCTFail("WKContentRuleListStore.default() returned nil")
            return
        }
        let identifier = "fmhy-test-inline"
        let json = #"[{"trigger":{"url-filter":"ads\\.example\\.com"},"action":{"type":"block"}}]"#

        let list: WKContentRuleList? = await withCheckedContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { ruleList, error in
                continuation.resume(returning: ruleList)
            }
        }
        XCTAssertNotNil(list)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeContentRuleList(forIdentifier: identifier) { _ in
                continuation.resume()
            }
        }
    }

    @MainActor
    func testAllowlistLogic() {
        let initialEnabled = AdBlocker.shared.isEnabled
        let initialAllowlist = AdBlocker.shared.allowlist
        defer {
            AdBlocker.shared.isEnabled = initialEnabled
            AdBlocker.shared.allowlist = initialAllowlist
        }

        AdBlocker.shared.isEnabled = true
        AdBlocker.shared.setAllowlisted("example.org", true)

        XCTAssertFalse(AdBlocker.shared.shouldBlock(host: "example.org"))
        XCTAssertTrue(AdBlocker.shared.shouldBlock(host: "other.org"))
    }
}

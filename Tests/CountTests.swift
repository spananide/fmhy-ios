import XCTest
@testable import FMHY

final class CountTests: XCTestCase {
    func testBundledDataCounts() throws {
        let dataURL = WikiStore.bundledDataURL()
        let snapshot = try WikiStore.parseAll(from: dataURL)
        let counts = WikiStore.sectionCounts(entries: snapshot.entries)

        let sum = counts.values.reduce(0, +)
        XCTAssertEqual(sum, snapshot.entries.count)
        XCTAssertGreaterThanOrEqual(snapshot.entries.count, 15000)
        XCTAssertGreaterThanOrEqual(sum, 15000)
    }
}

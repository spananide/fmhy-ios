import XCTest
@testable import FMHY

final class WidgetPayloadTests: XCTestCase {
    func testPayloadJSONRoundTrip() throws {
        let sites = [
            WidgetSite(name: "Site A", url: "https://example.com/a", description: "Alpha site"),
            WidgetSite(name: "Site B", url: "https://example.com/b", description: "Beta site")
        ]
        let pins = [
            WidgetPin(id: "video", title: "Video", emoji: "📺"),
            WidgetPin(id: "audio", title: "Audio", emoji: "🎵"),
            WidgetPin(id: "gaming", title: "Gaming", emoji: "🎮")
        ]
        let originalDate = Date(timeIntervalSince1970: 1700000000)
        let payload = WidgetPayload(updatedAt: originalDate, starred: sites, pins: pins)

        let data = try WidgetStore.encode(payload)
        let decoded = try WidgetStore.decode(data)

        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(decoded.starred.count, 2)
        XCTAssertEqual(decoded.starred[0].name, "Site A")
        XCTAssertEqual(decoded.starred[0].url, "https://example.com/a")
        XCTAssertEqual(decoded.starred[0].description, "Alpha site")
        XCTAssertEqual(decoded.starred[1].name, "Site B")
        XCTAssertEqual(decoded.pins.count, 3)
        XCTAssertEqual(decoded.pins[0].id, "video")
        XCTAssertEqual(decoded.pins[0].title, "Video")
        XCTAssertEqual(decoded.pins[0].emoji, "📺")
        XCTAssertEqual(decoded.pins[1].id, "audio")
        XCTAssertEqual(decoded.pins[2].id, "gaming")
    }

    func testWidgetStoreReadReturnsNilWithoutContainer() {
        let result = WidgetStore.read()
        XCTAssertNil(result)

        let nonExistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmhy_test_\(UUID().uuidString)")
            .appendingPathComponent("widget.json")
        let fileResult = WidgetStore.read(from: nonExistentURL)
        XCTAssertNil(fileResult)
    }

    func testPayloadBuildingLimits() {
        let hundredSites = (1...100).map { i in
            WidgetSite(name: "Site \(i)", url: "https://example.com/\(i)", description: "Desc \(i)")
        }
        let tenPins = (1...10).map { i in
            WidgetPin(id: "pin\(i)", title: "Pin \(i)", emoji: "📌")
        }

        let payloadFromStore = WidgetStore.buildPayload(starred: hundredSites, pins: tenPins)
        XCTAssertEqual(payloadFromStore.starred.count, 60)
        XCTAssertEqual(payloadFromStore.pins.count, 3)
        XCTAssertEqual(payloadFromStore.starred.first?.name, "Site 1")
        XCTAssertEqual(payloadFromStore.starred.last?.name, "Site 60")
        XCTAssertEqual(payloadFromStore.pins.first?.id, "pin1")
        XCTAssertEqual(payloadFromStore.pins.last?.id, "pin3")

        let payloadFromBridge = WidgetBridge.buildPayload(starred: hundredSites, pins: tenPins)
        XCTAssertEqual(payloadFromBridge.starred.count, 60)
        XCTAssertEqual(payloadFromBridge.pins.count, 3)

        let payloadFromMake = WidgetPayload.make(starred: hundredSites, pins: tenPins)
        XCTAssertEqual(payloadFromMake.starred.count, 60)
        XCTAssertEqual(payloadFromMake.pins.count, 3)
    }

    func testDeepLinkURLs() {
        let search = WidgetDeepLinks.searchURL
        XCTAssertEqual(search.absoluteString, "fmhy://search")

        let open = WidgetDeepLinks.openURL(urlString: "https://fmhy.net/test?a=1&b=2")
        XCTAssertNotNil(open)
        XCTAssertEqual(open?.scheme, "fmhy")
        XCTAssertEqual(open?.host, "open")

        if let openURL = open,
           let components = URLComponents(url: openURL, resolvingAgainstBaseURL: false) {
            let target = components.queryItems?.first(where: { $0.name == "url" })?.value
            XCTAssertEqual(target, "https://fmhy.net/test?a=1&b=2")
        } else {
            XCTFail("Failed to parse open URL components")
        }

        let section = WidgetDeepLinks.sectionURL(id: "gaming")
        XCTAssertNotNil(section)
        XCTAssertEqual(section?.absoluteString, "fmhy://section?id=gaming")
    }
}

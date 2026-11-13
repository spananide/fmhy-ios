import XCTest
#if canImport(FMHY)
@testable import FMHY
#elseif canImport(FMHYApp)
@testable import FMHYApp
#elseif canImport(fmhy_ios)
@testable import fmhy_ios
#endif

@MainActor
final class SiteSettingsTests: XCTestCase {
    func testSiteSettingsStoreDefaults() {
        let suiteName = "test-defaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SiteSettingsStore(userDefaults: defaults)
        XCTAssertTrue(store.hosts.isEmpty)

        let config = store.config(for: "example.com")
        XCTAssertEqual(config.host, "example.com")
        XCTAssertEqual(config.javaScript, true)
        XCTAssertEqual(config.popups, false)
        XCTAssertEqual(config.desktop, false)
        XCTAssertEqual(config.darkPage, false)
    }

    func testUpdateAndResetRoundTrip() {
        let suiteName = "test-roundtrip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store1 = SiteSettingsStore(userDefaults: defaults)
        let custom = SiteConfig(
            host: "www.example.com",
            javaScript: false,
            popups: true,
            desktop: true,
            darkPage: true
        )
        store1.update(custom)

        XCTAssertEqual(store1.hosts, ["example.com"])
        let savedConfig = store1.config(for: "example.com")
        XCTAssertEqual(savedConfig.host, "example.com")
        XCTAssertEqual(savedConfig.javaScript, false)
        XCTAssertEqual(savedConfig.popups, true)
        XCTAssertEqual(savedConfig.desktop, true)
        XCTAssertEqual(savedConfig.darkPage, true)

        let store2 = SiteSettingsStore(userDefaults: defaults)
        XCTAssertEqual(store2.hosts, ["example.com"])
        let reloadedConfig = store2.config(for: "example.com")
        XCTAssertEqual(reloadedConfig.host, "example.com")
        XCTAssertEqual(reloadedConfig.javaScript, false)
        XCTAssertEqual(reloadedConfig.popups, true)
        XCTAssertEqual(reloadedConfig.desktop, true)
        XCTAssertEqual(reloadedConfig.darkPage, true)

        store2.reset(host: "example.com")
        XCTAssertTrue(store2.hosts.isEmpty)
        let resetConfig = store2.config(for: "example.com")
        XCTAssertEqual(resetConfig.host, "example.com")
        XCTAssertEqual(resetConfig.javaScript, true)
        XCTAssertEqual(resetConfig.popups, false)
        XCTAssertEqual(resetConfig.desktop, false)
        XCTAssertEqual(resetConfig.darkPage, false)

        store2.update(SiteConfig(host: "site1.com", javaScript: false))
        store2.update(SiteConfig(host: "site2.com", desktop: true))
        XCTAssertEqual(store2.hosts.count, 2)
        store2.resetAll()
        XCTAssertTrue(store2.hosts.isEmpty)
    }

    func testHostNormalization() {
        XCTAssertEqual(SiteSettingsStore.normalizeHost("WWW.EXAMPLE.COM"), "example.com")
        XCTAssertEqual(SiteSettingsStore.normalizeHost("example.com"), "example.com")
        XCTAssertEqual(SiteSettingsStore.normalizeHost("  www.test.org  "), "test.org")
        XCTAssertEqual(SiteSettingsStore.normalizeHost(""), "")
        XCTAssertEqual(SiteSettingsStore.normalizeHost("   "), "")
        XCTAssertEqual(SiteSettingsStore.normalizeHost(nil), "")
    }

    func testZoomMathLimitsAndSteps() {
        XCTAssertEqual(BrowserTab.clampZoom(0.5), 1.0)
        XCTAssertEqual(BrowserTab.clampZoom(1.0), 1.0)
        XCTAssertEqual(BrowserTab.clampZoom(2.5), 2.5)
        XCTAssertEqual(BrowserTab.clampZoom(5.0), 5.0)
        XCTAssertEqual(BrowserTab.clampZoom(6.0), 5.0)

        XCTAssertEqual(BrowserTab.stepUpZoom(1.0), 1.25)
        XCTAssertEqual(BrowserTab.stepUpZoom(1.2), 1.25)
        XCTAssertEqual(BrowserTab.stepUpZoom(1.25), 1.50)
        XCTAssertEqual(BrowserTab.stepUpZoom(4.75), 5.0)
        XCTAssertEqual(BrowserTab.stepUpZoom(5.0), 5.0)

        XCTAssertEqual(BrowserTab.stepDownZoom(5.0), 4.75)
        XCTAssertEqual(BrowserTab.stepDownZoom(1.50), 1.25)
        XCTAssertEqual(BrowserTab.stepDownZoom(1.25), 1.0)
        XCTAssertEqual(BrowserTab.stepDownZoom(1.0), 1.0)

        XCTAssertFalse(BrowserTab.canResetZoom(1.0))
        XCTAssertTrue(BrowserTab.canResetZoom(1.25))
        XCTAssertTrue(BrowserTab.canResetZoom(0.99))

        XCTAssertEqual(BrowserTab.zoomPercentage(1.0), 100)
        XCTAssertEqual(BrowserTab.zoomPercentage(1.25), 125)
        XCTAssertEqual(BrowserTab.zoomPercentage(5.0), 500)
    }

    func testHasRealAddress() {
        XCTAssertTrue(BrowserTab.hasRealAddress(URL(string: "https://example.com")))
        XCTAssertTrue(BrowserTab.hasRealAddress(URL(string: "http://example.com/test?q=1")))
        XCTAssertFalse(BrowserTab.hasRealAddress(URL(string: "javascript:void(0)")))
        XCTAssertFalse(BrowserTab.hasRealAddress(URL(string: "about:blank")))
        XCTAssertFalse(BrowserTab.hasRealAddress(nil))
    }
}

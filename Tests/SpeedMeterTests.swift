import XCTest
@testable import FMHY

final class SpeedMeterTests: XCTestCase {

    func testMovingAverage() {
        var meter = SpeedMeter(alpha: 0.3)

        // First sample - speed is unknown (nil)
        meter.sample(totalBytes: 0, nowMs: 1000)
        XCTAssertNil(meter.bytesPerSecond)

        // Second sample 1000 ms later, 1,000,000 bytes transferred
        // Rate = 1,000,000 B/s. Since smoothedRate was nil, smoothedRate = instantRate = 1,000,000
        meter.sample(totalBytes: 1_000_000, nowMs: 2000)
        XCTAssertEqual(meter.bytesPerSecond, 1_000_000)

        // Third sample 1000 ms later, another 2,000,000 bytes transferred (total 3,000,000)
        // Instant rate = 2,000,000 B/s
        // Smoothed = 0.3 * 2,000,000 + 0.7 * 1,000,000 = 600,000 + 700,000 = 1,300,000
        meter.sample(totalBytes: 3_000_000, nowMs: 3000)
        XCTAssertEqual(meter.bytesPerSecond, 1_300_000)
    }

    func testZeroAndNegativeIntervals() {
        var meter = SpeedMeter()

        meter.sample(totalBytes: 100, nowMs: 1000)
        XCTAssertNil(meter.bytesPerSecond)

        // Interval < 250 ms (dt = 100 ms) should be ignored
        meter.sample(totalBytes: 500, nowMs: 1100)
        XCTAssertNil(meter.bytesPerSecond)

        // Zero interval (dt = 0 ms) should be ignored
        meter.sample(totalBytes: 600, nowMs: 1000)
        XCTAssertNil(meter.bytesPerSecond)

        // Negative interval (dt = -500 ms) should be ignored
        meter.sample(totalBytes: 700, nowMs: 500)
        XCTAssertNil(meter.bytesPerSecond)

        // Valid interval (dt = 1000 ms from the initial sample at 1000 ms)
        meter.sample(totalBytes: 1100, nowMs: 2000)
        // deltaBytes = 1100 - 100 = 1000, dt = 1000 ms -> rate = 1000 B/s
        XCTAssertEqual(meter.bytesPerSecond, 1000)
    }

    func testFormatting() {
        XCTAssertEqual(SpeedMeter.formatSpeed(-100), "0 B/s")
        XCTAssertEqual(SpeedMeter.formatSpeed(0), "0 B/s")
        XCTAssertEqual(SpeedMeter.formatSpeed(500), "500 B/s")
        XCTAssertEqual(SpeedMeter.formatSpeed(1_500), "1.5 KB/s")
        XCTAssertEqual(SpeedMeter.formatSpeed(3_200_000), "3.2 MB/s")
        XCTAssertEqual(SpeedMeter.formatSpeed(2_500_000_000), "2.5 GB/s")
    }

    func testEtaSecondsAndFormatting() {
        var meter = SpeedMeter()
        meter.sample(totalBytes: 0, nowMs: 1000)
        meter.sample(totalBytes: 1_000_000, nowMs: 2000) // 1,000,000 B/s

        XCTAssertEqual(meter.etaSeconds(remainingBytes: 0), 0)
        XCTAssertNil(meter.etaSeconds(remainingBytes: -10))
        XCTAssertEqual(meter.etaSeconds(remainingBytes: 3_200_000), 4) // ceil(3.2) = 4

        XCTAssertEqual(SpeedMeter.formatEta(0), "0s left")
        XCTAssertEqual(SpeedMeter.formatEta(45), "45s left")
        XCTAssertEqual(SpeedMeter.formatEta(120), "2m left")
        XCTAssertEqual(SpeedMeter.formatEta(3600), "1h left")
        XCTAssertNil(SpeedMeter.formatEta(-5))
    }

    func testReset() {
        var meter = SpeedMeter()
        meter.sample(totalBytes: 0, nowMs: 1000)
        meter.sample(totalBytes: 1_000_000, nowMs: 2000)
        XCTAssertEqual(meter.bytesPerSecond, 1_000_000)

        meter.reset()
        XCTAssertNil(meter.bytesPerSecond)

        // After reset, next sample is treated as first sample
        meter.sample(totalBytes: 5_000_000, nowMs: 3000)
        XCTAssertNil(meter.bytesPerSecond)

        meter.sample(totalBytes: 6_000_000, nowMs: 4000)
        XCTAssertEqual(meter.bytesPerSecond, 1_000_000)
    }

    func testReaderFmhyWebURL() {
        let guideURL = ReaderView.fmhyWebURL(for: "beginners-guide.md")
        XCTAssertEqual(guideURL?.absoluteString, "https://fmhy.net/beginners-guide")

        let docsGuideURL = ReaderView.fmhyWebURL(for: "docs/beginners-guide.md")
        XCTAssertEqual(docsGuideURL?.absoluteString, "https://fmhy.net/beginners-guide")

        let leadingSlashURL = ReaderView.fmhyWebURL(for: "/beginners-guide.md")
        XCTAssertEqual(leadingSlashURL?.absoluteString, "https://fmhy.net/beginners-guide")

        let faqURL = ReaderView.fmhyWebURL(for: "other/FAQ.md")
        XCTAssertEqual(faqURL?.absoluteString, "https://fmhy.net/other/FAQ")
    }
}

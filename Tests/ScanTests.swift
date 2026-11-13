import XCTest
@testable import FMHY

final class ScanTests: XCTestCase {

    // MARK: - ScanParsers Tests (ported from ScanParsersTest.kt)

    func testErrorForTable() {
        XCTAssertEqual(ScanParsers.errorFor(401), .badKey)
        XCTAssertEqual(ScanParsers.errorFor(403), .badKey)
        XCTAssertEqual(ScanParsers.errorFor(429), .limit)
        XCTAssertEqual(ScanParsers.errorFor(204), .limit)
        XCTAssertEqual(ScanParsers.errorFor(413), .tooBig)
        XCTAssertNil(ScanParsers.errorFor(404))
        XCTAssertNil(ScanParsers.errorFor(200))
        XCTAssertNil(ScanParsers.errorFor(201))
        XCTAssertNil(ScanParsers.errorFor(299))
        XCTAssertEqual(ScanParsers.errorFor(500), .other)
        XCTAssertEqual(ScanParsers.errorFor(502), .other)
        XCTAssertEqual(ScanParsers.errorFor(400), .other)
    }

    func testVtReportCleanAndFlagged() {
        let cleanJson = """
        {
            "data": {
                "attributes": {
                    "last_analysis_stats": {
                        "malicious": 0,
                        "suspicious": 0,
                        "undetected": 50,
                        "harmless": 20
                    },
                    "last_analysis_date": 1700000000
                }
            }
        }
        """
        let cleanRes = ScanParsers.vtReport(cleanJson, reportUrl: "https://report")
        XCTAssertNotNil(cleanRes)
        XCTAssertEqual(cleanRes?.verdict, .noFlags)
        XCTAssertEqual(cleanRes?.flagged, 0)
        XCTAssertEqual(cleanRes?.engines, 70)
        XCTAssertEqual(cleanRes?.scannedAt, Date(timeIntervalSince1970: 1700000000))
        XCTAssertEqual(cleanRes?.reportUrl, "https://report")

        let flaggedJson = """
        {
            "data": {
                "attributes": {
                    "last_analysis_stats": {
                        "malicious": 5,
                        "suspicious": 0,
                        "undetected": 45,
                        "harmless": 20
                    },
                    "last_analysis_date": 1700000100
                }
            }
        }
        """
        let flaggedRes = ScanParsers.vtReport(flaggedJson, reportUrl: "https://report")
        XCTAssertNotNil(flaggedRes)
        XCTAssertEqual(flaggedRes?.verdict, .dangerous)
        XCTAssertEqual(flaggedRes?.flagged, 5)
        XCTAssertEqual(flaggedRes?.engines, 70)
        XCTAssertEqual(flaggedRes?.scannedAt, Date(timeIntervalSince1970: 1700000100))
    }

    func testVtAnalysisQueuedAndCompleted() {
        let queuedJson = """
        {
            "data": {
                "attributes": {
                    "status": "queued"
                }
            }
        }
        """
        XCTAssertNil(ScanParsers.vtAnalysis(queuedJson, reportUrl: "https://report"))

        let completedJson = """
        {
            "data": {
                "attributes": {
                    "status": "completed",
                    "stats": {
                        "malicious": 1,
                        "suspicious": 1,
                        "undetected": 58,
                        "harmless": 10
                    },
                    "date": 1700000200
                }
            }
        }
        """
        let completedRes = ScanParsers.vtAnalysis(completedJson, reportUrl: "https://report")
        XCTAssertNotNil(completedRes)
        XCTAssertEqual(completedRes?.verdict, .suspicious)
        XCTAssertEqual(completedRes?.flagged, 2)
        XCTAssertEqual(completedRes?.engines, 70)
        XCTAssertEqual(completedRes?.scannedAt, Date(timeIntervalSince1970: 1700000200))
        XCTAssertEqual(completedRes?.reportUrl, "https://report")
    }

    func testVtUploadIdAndUploadUrl() {
        let idJson = """
        {
            "data": {
                "id": "u-analysis-id-xyz",
                "type": "analysis"
            }
        }
        """
        XCTAssertEqual(ScanParsers.vtAnalysisId(idJson), "u-analysis-id-xyz")

        let urlJson = """
        {
            "data": "https://www.virustotal.com/api/v3/files/upload_url/abc123"
        }
        """
        XCTAssertEqual(
            ScanParsers.vtUploadUrl(urlJson),
            "https://www.virustotal.com/api/v3/files/upload_url/abc123"
        )
    }

    func testHaOverviewCases() {
        let maliciousJson = """
        {
            "verdict": "malicious",
            "threat_score": 85,
            "last_multi_scan": "2026-10-01T12:00:00+00:00"
        }
        """
        let malRes = ScanParsers.haOverview(maliciousJson, reportUrl: "https://report")
        XCTAssertNotNil(malRes)
        XCTAssertEqual(malRes?.verdict, .dangerous)
        XCTAssertEqual(malRes?.detail, "Threat score 85 of 100")
        XCTAssertNotNil(malRes?.scannedAt)

        let cleanJson = """
        {
            "verdict": "no specific threat",
            "threat_score": 0,
            "analysis_start_time": "2026-10-01T12:00:00Z"
        }
        """
        let cleanRes = ScanParsers.haOverview(cleanJson, reportUrl: "https://report")
        XCTAssertNotNil(cleanRes)
        XCTAssertEqual(cleanRes?.verdict, .noFlags)
        XCTAssertEqual(cleanRes?.detail, "Threat score 0 of 100")

        let nullVerdictJson = """
        {
            "threat_score": null
        }
        """
        let nullRes = ScanParsers.haOverview(nullVerdictJson, reportUrl: "https://report")
        XCTAssertNotNil(nullRes)
        XCTAssertEqual(nullRes?.verdict, .unknown)
        XCTAssertNil(nullRes?.detail)
    }

    func testHaQuickScanUnfinishedAndFinished() {
        let idJson = """
        {
            "id": "quick-scan-id-456"
        }
        """
        XCTAssertEqual(ScanParsers.haQuickScanId(idJson), "quick-scan-id-456")

        let unfinishedJson = """
        {
            "finished": false,
            "scanners": []
        }
        """
        XCTAssertNil(ScanParsers.haQuickScan(unfinishedJson, reportUrl: "https://report"))

        let finishedJson = """
        {
            "finished": true,
            "scanners": [
                {"name": "s1", "status": "malicious"},
                {"name": "s2", "status": "clean"},
                {"name": "s3", "status": "clean"},
                {"name": "s4", "status": "clean"},
                {"name": "s5", "status": "clean"},
                {"name": "s6", "status": "clean"},
                {"name": "s7", "status": "clean"},
                {"name": "s8", "status": "clean"},
                {"name": "s9", "status": "clean"},
                {"name": "s10", "status": "clean"}
            ]
        }
        """
        let finishedRes = ScanParsers.haQuickScan(finishedJson, reportUrl: "https://report")
        XCTAssertNotNil(finishedRes)
        XCTAssertEqual(finishedRes?.verdict, .suspicious)
        XCTAssertEqual(finishedRes?.flagged, 1)
        XCTAssertEqual(finishedRes?.engines, 10)
        XCTAssertNil(finishedRes?.scannedAt)
    }

    func testMalformedJsonReturnsNullForEachParser() {
        let malformed = "not json {{"
        XCTAssertNil(ScanParsers.vtReport(malformed, reportUrl: "https://report"))
        XCTAssertNil(ScanParsers.vtAnalysisId(malformed))
        XCTAssertNil(ScanParsers.vtUploadUrl(malformed))
        XCTAssertNil(ScanParsers.vtAnalysis(malformed, reportUrl: "https://report"))
        XCTAssertNil(ScanParsers.haOverview(malformed, reportUrl: "https://report"))
        XCTAssertNil(ScanParsers.haQuickScanId(malformed))
        XCTAssertNil(ScanParsers.haQuickScan(malformed, reportUrl: "https://report"))

        let emptyObj = "{}"
        XCTAssertNil(ScanParsers.vtReport(emptyObj, reportUrl: "https://report"))
        XCTAssertNil(ScanParsers.vtAnalysisId(emptyObj))
        XCTAssertNil(ScanParsers.vtUploadUrl(emptyObj))
        XCTAssertNil(ScanParsers.vtAnalysis(emptyObj, reportUrl: "https://report"))
        XCTAssertNil(ScanParsers.haQuickScanId(emptyObj))
        XCTAssertNil(ScanParsers.haQuickScan(emptyObj, reportUrl: "https://report"))
    }

    // MARK: - ScanVerdicts Tests

    func testScanVerdictsFromCounts() {
        XCTAssertEqual(ScanVerdicts.fromCounts(malicious: 0, suspicious: 0, engines: 0), .unknown)
        XCTAssertEqual(ScanVerdicts.fromCounts(malicious: 0, suspicious: 0, engines: -1), .unknown)
        XCTAssertEqual(ScanVerdicts.fromCounts(malicious: 3, suspicious: 0, engines: 10), .dangerous)
        XCTAssertEqual(ScanVerdicts.fromCounts(malicious: 5, suspicious: 2, engines: 70), .dangerous)
        XCTAssertEqual(ScanVerdicts.fromCounts(malicious: 1, suspicious: 0, engines: 10), .suspicious)
        XCTAssertEqual(ScanVerdicts.fromCounts(malicious: 0, suspicious: 1, engines: 10), .suspicious)
        XCTAssertEqual(ScanVerdicts.fromCounts(malicious: 0, suspicious: 0, engines: 70), .noFlags)
    }

    func testScanVerdictsFromHybridVerdict() {
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict(nil), .unknown)
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict(""), .unknown)
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict("malicious"), .dangerous)
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict(" Malicious "), .dangerous)
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict("suspicious"), .suspicious)
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict("no specific threat"), .noFlags)
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict("no-specific-threat"), .noFlags)
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict("whitelisted"), .noFlags)
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict("clean"), .noFlags)
        XCTAssertEqual(ScanVerdicts.fromHybridVerdict("something else"), .unknown)
    }

    func testScanVerdictsCombine() {
        XCTAssertEqual(ScanVerdicts.combine([]), .unknown)

        let errored = [
            ServiceResult(service: .virusTotal, verdict: .dangerous, error: .badKey),
            ServiceResult(service: .hybridAnalysis, verdict: .unknown, error: nil)
        ]
        XCTAssertEqual(ScanVerdicts.combine(errored), .unknown)

        let noFlagsOnly = [
            ServiceResult(service: .virusTotal, verdict: .noFlags)
        ]
        XCTAssertEqual(ScanVerdicts.combine(noFlagsOnly), .noFlags)

        let suspiciousAndNoFlags = [
            ServiceResult(service: .virusTotal, verdict: .noFlags),
            ServiceResult(service: .hybridAnalysis, verdict: .suspicious)
        ]
        XCTAssertEqual(ScanVerdicts.combine(suspiciousAndNoFlags), .suspicious)

        let dangerousAndSuspicious = [
            ServiceResult(service: .virusTotal, verdict: .suspicious),
            ServiceResult(service: .hybridAnalysis, verdict: .dangerous)
        ]
        XCTAssertEqual(ScanVerdicts.combine(dangerousAndSuspicious), .dangerous)

        let erroredIgnored = [
            ServiceResult(service: .virusTotal, verdict: .dangerous, error: .limit),
            ServiceResult(service: .hybridAnalysis, verdict: .noFlags)
        ]
        XCTAssertEqual(ScanVerdicts.combine(erroredIgnored), .noFlags)
    }

    // MARK: - ScanLinks Tests

    func testScanLinksVtUrlId() {
        let url1 = "https://example.com"
        let id1 = ScanLinks.vtUrlId(url1)
        XCTAssertFalse(id1.contains("+"))
        XCTAssertFalse(id1.contains("/"))
        XCTAssertFalse(id1.contains("="))
        XCTAssertEqual(id1, "aHR0cHM6Ly9leGFtcGxlLmNvbQ")

        let url2 = "https://example.com/test?a=1&b=2"
        let id2 = ScanLinks.vtUrlId(url2)
        XCTAssertFalse(id2.contains("+"))
        XCTAssertFalse(id2.contains("/"))
        XCTAssertFalse(id2.contains("="))
        XCTAssertEqual(id2, "aHR0cHM6Ly9leGFtcGxlLmNvbS90ZXN0P2E9MSZiPTI")
    }

    func testScanLinksReports() {
        let fileVt = ScanLinks.fileReport(service: .virusTotal, sha256: "abc123")
        XCTAssertEqual(fileVt, "https://www.virustotal.com/gui/file/abc123")

        let fileHa = ScanLinks.fileReport(service: .hybridAnalysis, sha256: "abc123")
        XCTAssertEqual(fileHa, "https://hybrid-analysis.com/sample/abc123")

        let linkVt = ScanLinks.linkReport(service: .virusTotal, url: "https://example.com/test?a=1&b=2")
        XCTAssertTrue(linkVt.hasPrefix("https://www.virustotal.com/gui/search/"))
        XCTAssertFalse(linkVt.contains("?a=1&b=2"))

        let linkHa = ScanLinks.linkReport(service: .hybridAnalysis, url: "https://example.com/search?q=test&page=1")
        XCTAssertTrue(linkHa.hasPrefix("https://hybrid-analysis.com/search?query="))
        XCTAssertFalse(linkHa.contains("?q=test&page=1"))
        XCTAssertTrue(linkHa.contains("%3Fq%3Dtest%26page%3D1"))

        XCTAssertEqual(ScanLinks.uploadPage(service: .virusTotal), "https://www.virustotal.com/gui/home/upload")
        XCTAssertEqual(ScanLinks.uploadPage(service: .hybridAnalysis), "https://hybrid-analysis.com/")
    }

    // MARK: - ScanResult JSON Round Trip Tests

    func testScanResultJsonRoundTrip() throws {
        let original = ScanResult(
            kind: .file,
            sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            services: [
                ServiceResult(
                    service: .virusTotal,
                    verdict: .noFlags,
                    flagged: 0,
                    engines: 70,
                    detail: nil,
                    scannedAt: Date(timeIntervalSince1970: 1700000000),
                    reportUrl: "https://www.virustotal.com/gui/file/e3b0...",
                    error: nil
                ),
                ServiceResult(
                    service: .hybridAnalysis,
                    verdict: .suspicious,
                    flagged: 2,
                    engines: 50,
                    detail: "Threat score 40 of 100",
                    scannedAt: Date(timeIntervalSince1970: 1700000100),
                    reportUrl: "https://hybrid-analysis.com/sample/e3b0...",
                    error: nil
                )
            ],
            checkedAt: Date(timeIntervalSince1970: 1700000200),
            pending: [
                PendingAnalysis(
                    service: .virusTotal,
                    analysisId: "a-12345",
                    startedAt: Date(timeIntervalSince1970: 1700000300)
                )
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ScanResult.self, from: data)

        XCTAssertEqual(decoded.kind, original.kind)
        XCTAssertEqual(decoded.sha256, original.sha256)
        XCTAssertEqual(decoded.services.count, 2)
        XCTAssertEqual(decoded.services[0].service, .virusTotal)
        XCTAssertEqual(decoded.services[0].verdict, .noFlags)
        XCTAssertEqual(decoded.services[0].scannedAt, Date(timeIntervalSince1970: 1700000000))
        XCTAssertEqual(decoded.services[1].service, .hybridAnalysis)
        XCTAssertEqual(decoded.services[1].verdict, .suspicious)
        XCTAssertEqual(decoded.services[1].detail, "Threat score 40 of 100")
        XCTAssertEqual(decoded.checkedAt, Date(timeIntervalSince1970: 1700000200))
        XCTAssertEqual(decoded.pending.count, 1)
        XCTAssertEqual(decoded.pending[0].service, .virusTotal)
        XCTAssertEqual(decoded.pending[0].analysisId, "a-12345")
        XCTAssertEqual(decoded.pending[0].startedAt, Date(timeIntervalSince1970: 1700000300))
        XCTAssertEqual(decoded.verdict, .suspicious)
        XCTAssertTrue(decoded.isRunning)

        // Helper toJson / fromJson round trip
        let jsonString = original.toJson()
        XCTAssertNotNil(jsonString)
        let fromJsonResult = ScanResult.fromJson(jsonString)
        XCTAssertEqual(fromJsonResult?.kind, .file)
        XCTAssertEqual(fromJsonResult?.verdict, .suspicious)
        XCTAssertEqual(fromJsonResult?.pending.count, 1)

        // Inline JSON sample with uppercase enums and epoch milliseconds
        let inlineJson = """
        {
            "kind": "LINK",
            "sha256": null,
            "services": [
                {
                    "service": "VIRUSTOTAL",
                    "verdict": "DANGEROUS",
                    "flagged": 5,
                    "engines": 70,
                    "detail": null,
                    "scannedAt": 1700000000000,
                    "reportUrl": "https://virustotal.com",
                    "error": null
                }
            ],
            "checkedAt": 1700000000000,
            "pending": []
        }
        """
        guard let inlineData = inlineJson.data(using: .utf8) else {
            XCTFail("Failed to convert inline JSON to Data")
            return
        }
        let inlineDecoded = try decoder.decode(ScanResult.self, from: inlineData)
        XCTAssertEqual(inlineDecoded.kind, .link)
        XCTAssertEqual(inlineDecoded.verdict, .dangerous)
        XCTAssertEqual(inlineDecoded.services[0].scannedAt, Date(timeIntervalSince1970: 1700000000))
        XCTAssertFalse(inlineDecoded.isRunning)
    }

    // MARK: - ScanText Tests

    func testScanText() {
        XCTAssertEqual(ScanText.reminder, "“No flags” is not a guarantee, and “unknown” does not mean safe.")
        XCTAssertEqual(ScanText.unknownFile, "Not known to this service yet.")
        XCTAssertEqual(ScanText.engines(flagged: 3, engines: 70), "3 of 70 engines flagged this")
        XCTAssertEqual(
            ScanText.error(service: .virusTotal, e: .badKey),
            "The VirusTotal key isn't valid. Check it in settings or open the VirusTotal website instead."
        )
        XCTAssertEqual(
            ScanText.error(service: .hybridAnalysis, e: .limit),
            "Your free Hybrid Analysis key has reached its usage limit. Try again later or open the Hybrid Analysis website instead."
        )
        XCTAssertEqual(
            ScanText.error(service: .virusTotal, e: .offline),
            "Couldn't reach VirusTotal. Check your connection."
        )
        XCTAssertEqual(
            ScanText.error(service: .virusTotal, e: .tooBig),
            "This file is too big to upload to VirusTotal. Open the VirusTotal website instead."
        )
        XCTAssertEqual(
            ScanText.error(service: .virusTotal, e: .other),
            "VirusTotal couldn't check this right now."
        )
    }
}

import XCTest
@testable import FMHY

final class CheckTests: XCTestCase {

    // MARK: - CheckPolicy AfterDownload Truth Table Tests

    func testAfterDownloadReadyRiskyNoHold() {
        // readyServices present, risky file, no hold -> checkNow = true, hold = false, keyPrompt = false
        let decision = CheckPolicy.afterDownload(
            fileName: "installer.exe",
            readyCount: 1,
            hold: false,
            autoCheckRisky: true,
            keyPromptShown: false
        )
        XCTAssertEqual(decision, AfterDownload(hold: false, checkNow: true, keyPrompt: false))
    }

    func testAfterDownloadReadyNonRiskyNoHold() {
        // readyServices present, non-risky file, no hold -> checkNow = false, hold = false, keyPrompt = false
        let decision = CheckPolicy.afterDownload(
            fileName: "readme.txt",
            readyCount: 1,
            hold: false,
            autoCheckRisky: true,
            keyPromptShown: false
        )
        XCTAssertEqual(decision, AfterDownload(hold: false, checkNow: false, keyPrompt: false))
    }

    func testAfterDownloadReadyHold() {
        // readyServices present, hold = true -> checkNow = true, hold = true, keyPrompt = false
        let decision = CheckPolicy.afterDownload(
            fileName: "document.pdf",
            readyCount: 1,
            hold: true,
            autoCheckRisky: false,
            keyPromptShown: false
        )
        XCTAssertEqual(decision, AfterDownload(hold: true, checkNow: true, keyPrompt: false))
    }

    func testAfterDownloadNotReadyRiskyKeyPromptNotShown() {
        // no readyServices, risky file, keyPrompt not shown -> keyPrompt = true, checkNow = false, hold = false
        let decision = CheckPolicy.afterDownload(
            fileName: "tool.apk",
            readyCount: 0,
            hold: false,
            autoCheckRisky: true,
            keyPromptShown: false
        )
        XCTAssertEqual(decision, AfterDownload(hold: false, checkNow: false, keyPrompt: true))
    }

    func testAfterDownloadNotReadyRiskyKeyPromptAlreadyShown() {
        // no readyServices, risky file, keyPrompt already shown -> keyPrompt = false, checkNow = false, hold = false
        let decision = CheckPolicy.afterDownload(
            fileName: "tool.apk",
            readyCount: 0,
            hold: false,
            autoCheckRisky: true,
            keyPromptShown: true
        )
        XCTAssertEqual(decision, AfterDownload(hold: false, checkNow: false, keyPrompt: false))
    }

    func testAfterDownloadNotReadyHold() {
        // no readyServices, hold = true, keyPrompt not shown -> hold = true, checkNow = false, keyPrompt = true
        let decision = CheckPolicy.afterDownload(
            fileName: "archive.zip",
            readyCount: 0,
            hold: true,
            autoCheckRisky: false,
            keyPromptShown: false
        )
        XCTAssertEqual(decision, AfterDownload(hold: true, checkNow: false, keyPrompt: true))
    }

    func testAfterDownloadNotReadyNoHoldNonRisky() {
        // no readyServices, no hold, non-risky file -> hold = false, checkNow = false, keyPrompt = false
        let decision = CheckPolicy.afterDownload(
            fileName: "song.mp3",
            readyCount: 0,
            hold: false,
            autoCheckRisky: false,
            keyPromptShown: false
        )
        XCTAssertEqual(decision, AfterDownload(hold: false, checkNow: false, keyPrompt: false))
    }

    // MARK: - CheckPolicy isAutoCheckType Tests

    func testIsAutoCheckType() {
        let positive = [
            "setup.exe", "Setup.EXE", "app.apk", "game.xapk", "bundle.apks",
            "install.msi", "script.bat", "run.cmd", "screen.scr", "mac.dmg",
            "package.pkg", "app.jar", "macro.vbs", "deploy.ps1", "build.sh",
            "script.py", "module.js", "script.jse", "app.wsf", "hta.hta",
            "old.com", "shortcut.lnk", "bin.appimage", "dist.deb", "dist.rpm",
            "modern.msix", "store.appx"
        ]
        for name in positive {
            XCTAssertTrue(CheckPolicy.isAutoCheckType(name), "\(name) should be auto-check type")
        }

        let negative = [
            "readme.txt", "document.pdf", "image.png", "photo.jpg",
            "song.mp3", "movie.mp4", "archive.zip", "data.tar.gz",
            "code.swift", "notes.md", "noextension"
        ]
        for name in negative {
            XCTAssertFalse(CheckPolicy.isAutoCheckType(name), "\(name) should not be auto-check type")
        }

        // URLs with queries/fragments and trailing whitespace/dots
        XCTAssertTrue(CheckPolicy.isAutoCheckType("https://example.com/file.exe?download=true"))
        XCTAssertTrue(CheckPolicy.isAutoCheckType("https://example.com/archive.apk#hash"))
        XCTAssertTrue(CheckPolicy.isAutoCheckType("script.py. "))
    }

    // MARK: - CheckPolicy restoredState Tests

    func testRestoredState() {
        XCTAssertEqual(CheckPolicy.restoredState(.checking), .awaitingDecision)
        XCTAssertEqual(CheckPolicy.restoredState(.downloading), .queued)
        XCTAssertEqual(CheckPolicy.restoredState(.awaitingDecision), .awaitingDecision)
        XCTAssertEqual(CheckPolicy.restoredState(.completed), .completed)
        XCTAssertEqual(CheckPolicy.restoredState(.paused), .paused)
        XCTAssertEqual(CheckPolicy.restoredState(.failed), .failed)
        XCTAssertEqual(CheckPolicy.restoredState(.cancelled), .cancelled)
        XCTAssertEqual(CheckPolicy.restoredState(.queued), .queued)
    }

    // MARK: - CheckPolicy needsExtraConfirm Tests

    func testNeedsExtraConfirm() {
        XCTAssertFalse(CheckPolicy.needsExtraConfirm(nil as ScanResult?))

        let noFlagsResult = ScanResult(
            kind: .file,
            sha256: "dummy",
            services: [ServiceResult(service: .virusTotal, verdict: .noFlags)]
        )
        XCTAssertFalse(CheckPolicy.needsExtraConfirm(noFlagsResult))

        let suspiciousResult = ScanResult(
            kind: .file,
            sha256: "dummy",
            services: [ServiceResult(service: .virusTotal, verdict: .suspicious)]
        )
        XCTAssertFalse(CheckPolicy.needsExtraConfirm(suspiciousResult))

        let dangerousResult = ScanResult(
            kind: .file,
            sha256: "dummy",
            services: [ServiceResult(service: .virusTotal, verdict: .dangerous)]
        )
        XCTAssertTrue(CheckPolicy.needsExtraConfirm(dangerousResult))

        let unknownResult = ScanResult(
            kind: .file,
            sha256: "dummy",
            services: [ServiceResult(service: .virusTotal, verdict: .unknown)]
        )
        XCTAssertFalse(CheckPolicy.needsExtraConfirm(unknownResult))
    }

    // MARK: - CheckUiText Tests

    func testServiceLine() {
        let errorResult = ServiceResult(service: .virusTotal, verdict: .unknown, error: .badKey)
        XCTAssertEqual(
            CheckUiText.serviceLine(errorResult),
            ScanText.error(service: .virusTotal, e: .badKey)
        )

        let enginesResult = ServiceResult(service: .virusTotal, verdict: .dangerous, flagged: 3, engines: 72)
        XCTAssertEqual(CheckUiText.serviceLine(enginesResult), "3 of 72 engines flagged this")

        let detailResult = ServiceResult(service: .hybridAnalysis, verdict: .noFlags, detail: "Clean sandbox")
        XCTAssertEqual(CheckUiText.serviceLine(detailResult), "Clean sandbox")

        let unknownResult = ServiceResult(service: .virusTotal, verdict: .unknown)
        XCTAssertEqual(CheckUiText.serviceLine(unknownResult), ScanText.unknownFile)
    }

    func testVerdictTitle() {
        XCTAssertEqual(CheckUiText.verdictTitle(.noFlags), "No flags")
        XCTAssertEqual(CheckUiText.verdictTitle(.suspicious), "Suspicious")
        XCTAssertEqual(CheckUiText.verdictTitle(.dangerous), "Dangerous: don't open this file")
        XCTAssertEqual(CheckUiText.verdictTitle(.unknown), "Unknown")
    }

    func testLinkVerdictTitle() {
        XCTAssertEqual(CheckUiText.linkVerdictTitle(.noFlags), "No flags")
        XCTAssertEqual(CheckUiText.linkVerdictTitle(.suspicious), "Suspicious")
        XCTAssertEqual(CheckUiText.linkVerdictTitle(.dangerous), "Dangerous: don't download this file")
        XCTAssertEqual(CheckUiText.linkVerdictTitle(.unknown), "Unknown")
    }

    func testSendNote() {
        let single = CheckUiText.sendNote([.virusTotal])
        XCTAssertEqual(single, "The web address will be sent to VirusTotal. Some links contain personal or one-time codes.")

        let both = CheckUiText.sendNote([.virusTotal, .hybridAnalysis])
        XCTAssertEqual(both, "The web address will be sent to VirusTotal and Hybrid Analysis. Some links contain personal or one-time codes.")
    }

    func testCheckedLine() {
        let calendar = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 13
        comps.hour = 12
        let date = calendar.date(from: comps)!

        let result = ScanResult(kind: .file, sha256: "test", services: [], checkedAt: date)

        // Same year
        let nowSameYear = date
        let lineSameYear = CheckUiText.checkedLine(result, now: nowSameYear)
        XCTAssertTrue(lineSameYear.contains("13 Nov"))

        // Different year
        var nextYearComps = comps
        nextYearComps.year = 2027
        let nowNextYear = calendar.date(from: nextYearComps)!
        let lineNextYear = CheckUiText.checkedLine(result, now: nowNextYear)
        XCTAssertEqual(lineNextYear, "Checked 13 Nov 2026")
    }
}

import XCTest
import Security
@testable import FMHY

final class DownloadTests: XCTestCase {

    // MARK: - Risk Tests

    func testIsRisky() {
        XCTAssertTrue(DownloadManager.isRisky(fileName: "setup.EXE"))
        XCTAssertFalse(DownloadManager.isRisky(fileName: "readme.txt"))
        XCTAssertTrue(DownloadManager.isRisky(fileName: "app.ipa"))
        XCTAssertFalse(DownloadManager.isRisky(fileName: "noextension"))

        XCTAssertTrue(DownloadManager.isRisky(fileName: "tool.apk"))
        XCTAssertTrue(DownloadManager.isRisky(fileName: "installer.msi"))
        XCTAssertTrue(DownloadManager.isRisky(fileName: "script.bat"))
        XCTAssertTrue(DownloadManager.isRisky(fileName: "archive.iso"))
        XCTAssertFalse(DownloadManager.isRisky(fileName: "document.pdf"))
    }

    // MARK: - Sanitization and Unique Name Tests

    func testSanitizedFileName() {
        let sanitized = DownloadManager.sanitizedFileName("../../a/b:c.zip")
        XCTAssertFalse(sanitized.contains("/"))
        XCTAssertFalse(sanitized.contains("\\"))
        XCTAssertTrue(sanitized.hasSuffix(".zip"))

        XCTAssertEqual(DownloadManager.sanitizedFileName(""), "download")
        XCTAssertEqual(DownloadManager.sanitizedFileName("   "), "download")
        XCTAssertEqual(DownloadManager.sanitizedFileName("///"), "download")
        XCTAssertEqual(DownloadManager.sanitizedFileName(".zip"), "download.zip")
        XCTAssertEqual(DownloadManager.sanitizedFileName("normal_file.tar.gz"), "normal_file.tar.gz")
    }

    func testUniqueFileName() {
        let existing: Set<String> = ["a.zip", "a (2).zip"]
        let unique = DownloadManager.uniqueFileName("a.zip", existing: existing)
        XCTAssertEqual(unique, "a (3).zip")

        let uniqueFirst = DownloadManager.uniqueFileName("b.zip", existing: existing)
        XCTAssertEqual(uniqueFirst, "b.zip")
    }

    // MARK: - VirusTotal Report Parsing Tests

    func testVirusTotalParseFileReport() throws {
        let sha = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let jsonString = """
        {"data":{"attributes":{"last_analysis_stats":{"malicious":3,"suspicious":1,"harmless":60,"undetected":10}}}}
        """
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let result = try XCTUnwrap(VirusTotal.parseFileReport(data, sha256: sha))

        XCTAssertEqual(result.malicious, 3)
        XCTAssertEqual(result.suspicious, 1)
        XCTAssertEqual(result.harmless, 60)
        XCTAssertEqual(result.undetected, 10)
        XCTAssertTrue(result.found)
        XCTAssertTrue(result.permalink.contains(sha))
        XCTAssertEqual(result.verdictText, "4 engines flag this file")
    }

    func testVirusTotalParseFileReportGarbageReturnsNil() {
        let sha = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let garbage = Data("this is not json at all".utf8)
        XCTAssertNil(VirusTotal.parseFileReport(garbage, sha256: sha))

        let incompleteJSON = Data("{\"data\":{}}".utf8)
        XCTAssertNil(VirusTotal.parseFileReport(incompleteJSON, sha256: sha))
    }

    // MARK: - DownloadItem JSON Round Trip

    func testDownloadItemJSONRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1731448800)
        let vt = VTResult(
            malicious: 1,
            suspicious: 0,
            harmless: 65,
            undetected: 4,
            checkedAt: date,
            found: true,
            permalink: "https://www.virustotal.com/gui/file/test_sha"
        )
        let item = DownloadItem(
            id: UUID(uuidString: "98765432-4321-4321-4321-210987654321")!,
            sourceURL: "https://example.com/archive.zip",
            fileName: "archive.zip",
            state: .completed,
            bytesReceived: 5242880,
            bytesTotal: 5242880,
            relativePath: "Downloads/archive.zip",
            startedAt: date,
            errorMessage: nil,
            sha256: "test_sha",
            vt: vt,
            isRisky: false,
            riskyConfirmed: false
        )

        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(item)

        let decoder = JSONDecoder()
        let decodedItem = try decoder.decode(DownloadItem.self, from: encodedData)

        XCTAssertEqual(decodedItem.id, item.id)
        XCTAssertEqual(decodedItem.sourceURL, item.sourceURL)
        XCTAssertEqual(decodedItem.fileName, item.fileName)
        XCTAssertEqual(decodedItem.state, item.state)
        XCTAssertEqual(decodedItem.bytesReceived, item.bytesReceived)
        XCTAssertEqual(decodedItem.bytesTotal, item.bytesTotal)
        XCTAssertEqual(decodedItem.relativePath, item.relativePath)
        XCTAssertEqual(decodedItem.startedAt, item.startedAt)
        XCTAssertEqual(decodedItem.errorMessage, item.errorMessage)
        XCTAssertEqual(decodedItem.sha256, item.sha256)
        XCTAssertEqual(decodedItem.vt, item.vt)
        XCTAssertEqual(decodedItem.isRisky, item.isRisky)
        XCTAssertEqual(decodedItem.riskyConfirmed, item.riskyConfirmed)
    }

    // MARK: - KeychainStore Tests

    func testKeychainStoreRoundTrip() throws {
        let testKey = "test.keychain.\(UUID().uuidString)"
        let testValue = "vt_secret_test_value"

        KeychainStore.set(testValue, for: testKey)

        guard let retrieved = KeychainStore.get(testKey) else {
            throw XCTSkip("Keychain is unavailable on this runner")
        }

        XCTAssertEqual(retrieved, testValue)

        KeychainStore.set(nil, for: testKey)
        XCTAssertNil(KeychainStore.get(testKey))
    }
}

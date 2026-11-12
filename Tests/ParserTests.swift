import XCTest
@testable import FMHY

final class ParserTests: XCTestCase {

    func testInlineMovyParsing() {
        let section = WikiSection(id: "video", title: "Movies / TV / Anime", description: "", ord: 0)
        let markdown = "🌟 **[Movy](https://www.movy.sx/)** - 4K / Dual Audio / [Discord](https://discord.gg/x)"
        let b64 = Base64Map(html: "")
        let parsed = FmhyParser.parseSection(section, markdown: markdown, b64: b64)

        XCTAssertEqual(parsed.entries.count, 1)
        guard let entry = parsed.entries.first else { return }
        XCTAssertEqual(entry.tier, 2)
        XCTAssertEqual(entry.name, "Movy")
        XCTAssertTrue(entry.tags.contains("4K"))
        XCTAssertTrue(entry.tags.contains("Dual Audio"))
        XCTAssertTrue(entry.extraLinks.contains(where: { $0.label == "Discord" && $0.url == "https://discord.gg/x" }))
    }

    func testStarWithMirror() {
        let section = WikiSection(id: "test", title: "Test", description: "", ord: 0)
        let markdown = "* ⭐ **[A](https://a.com/)**, [2](https://a2.com/) - desc"
        let b64 = Base64Map(html: "")
        let parsed = FmhyParser.parseSection(section, markdown: markdown, b64: b64)

        XCTAssertEqual(parsed.entries.count, 1)
        guard let entry = parsed.entries.first else { return }
        XCTAssertEqual(entry.tier, 1)
        XCTAssertEqual(entry.mirrors.count, 1)
        XCTAssertEqual(entry.mirrors.first?.url, "https://a2.com/")
    }

    func testNoteParsing() {
        let section = WikiSection(id: "test", title: "Test", description: "", ord: 0)
        let markdown = "* **Note** - text"
        let b64 = Base64Map(html: "")
        let parsed = FmhyParser.parseSection(section, markdown: markdown, b64: b64)

        XCTAssertEqual(parsed.notes.count, 1)
        XCTAssertEqual(parsed.notes.first?.text, "text")
    }

    func testBase64Resolution() {
        let html = "<h4 id=\"x\"><code>aHR0cHM6Ly9leGFtcGxlLmNvbS8=</code></h4>"
        let b64 = Base64Map(html: html)
        let section = WikiSection(id: "test", title: "Test", description: "", ord: 0)
        let markdown = "* **[Example](https://rentry.co/FMHYB64#x)** - description"
        let parsed = FmhyParser.parseSection(section, markdown: markdown, b64: b64)

        XCTAssertEqual(parsed.entries.count, 1)
        guard let entry = parsed.entries.first else { return }
        XCTAssertEqual(entry.url, "https://example.com/")
        XCTAssertTrue(entry.isBase64)
        XCTAssertEqual(entry.originalUrl, "https://rentry.co/FMHYB64#x")
    }

    func testRealDataParsing() throws {
        let dataURL = WikiStore.bundledDataURL()
        let headersURL = dataURL.appendingPathComponent("headers.json")
        let headersData = try Data(contentsOf: headersURL)
        let sections = FmhyParser.parseSections(headersJSON: headersData)

        let rentryURL = dataURL.appendingPathComponent("rentry.html")
        let rentryHTML = (try? String(contentsOf: rentryURL, encoding: .utf8)) ?? ""
        let b64 = Base64Map(html: rentryHTML)

        var allEntries: [Entry] = []
        var parsedSectionsCount = 0

        for section in sections {
            let fileURL = dataURL.appendingPathComponent("\(section.id).md")
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let md = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            parsedSectionsCount += 1
            let parsed = FmhyParser.parseSection(section, markdown: md, b64: b64)
            allEntries.append(contentsOf: parsed.entries)
        }

        XCTAssertGreaterThanOrEqual(parsedSectionsCount, 20)
        XCTAssertGreaterThanOrEqual(allEntries.count, 15000)

        let tier2Count = allEntries.filter { $0.tier == 2 }.count
        let starredCount = allEntries.filter { $0.tier >= 1 }.count
        XCTAssertGreaterThan(starredCount, 100)
        XCTAssertTrue(tier2Count > 10 || tier2Count > 100)
    }

    func testSearchOnRealEntries() throws {
        let dataURL = WikiStore.bundledDataURL()
        let snapshot = try WikiStore.parseAll(from: dataURL)
        let search = snapshot.search

        // 1. stremo -> stremio
        let stremoResults = search.search("stremo")
        XCTAssertFalse(stremoResults.isEmpty)
        XCTAssertTrue(stremoResults.contains { $0.entry.name.lowercased().contains("stremio") })

        // 2. is:starred anime
        let starredResults = search.search("is:starred anime")
        XCTAssertFalse(starredResults.isEmpty)
        for res in starredResults {
            XCTAssertGreaterThanOrEqual(res.entry.tier, 1)
        }

        // 3. in:video netflix
        let videoResults = search.search("in:video netflix")
        XCTAssertFalse(videoResults.isEmpty)
        for res in videoResults {
            XCTAssertEqual(res.entry.sectionId, "video")
        }

        // 4. Performance under 1s
        let start = Date()
        _ = search.search("stremo")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testSafeGuard() throws {
        let dataURL = WikiStore.bundledDataURL()
        let snapshot = try WikiStore.parseAll(from: dataURL)
        let sg = snapshot.safeGuard

        // 1. fmhy.net -> .fmhySite
        let fmhyVerdict = sg.check("fmhy.net")
        XCTAssertEqual(fmhyVerdict.status, .fmhySite)

        // 2. movy.sx or a starred entry's URL
        let starredUrl: String
        if let movy = snapshot.entries.first(where: { $0.name.caseInsensitiveCompare("movy") == .orderedSame }) {
            starredUrl = "\(movy.url)/anything"
        } else if let anyStarred = snapshot.entries.first(where: { $0.tier >= 1 }) {
            starredUrl = "\(anyStarred.url)/anything"
        } else {
            starredUrl = "https://www.movy.sx/anything"
        }
        let starredVerdict = sg.check(starredUrl)
        XCTAssertNotEqual(starredVerdict.status, .noData)
        XCTAssertNotEqual(starredVerdict.status, .invalid)

        // 3. "not a url" -> .invalid
        let invalidVerdict = sg.check("not a url")
        XCTAssertEqual(invalidVerdict.status, .invalid)

        // 4. first plain domain in filterlist-domains.txt
        let unsafeDomainsURL = dataURL.appendingPathComponent("filterlist-domains.txt")
        let unsafeDomains = (try? String(contentsOf: unsafeDomainsURL, encoding: .utf8)) ?? ""
        var firstPlainDomain: String?
        for line in unsafeDomains.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !t.hasPrefix("#") && !t.hasPrefix("!") {
                firstPlainDomain = t
                break
            }
        }
        guard let domain = firstPlainDomain else {
            XCTFail("Could not find plain domain in filterlist-domains.txt")
            return
        }
        let unsafeVerdict = sg.check(domain)
        XCTAssertTrue(unsafeVerdict.status == .unsafe || unsafeVerdict.status == .potentiallyUnsafe)
    }
}

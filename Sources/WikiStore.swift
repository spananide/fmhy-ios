import Foundation
import Combine

struct WikiSnapshot: Sendable {
    let sections: [WikiSection]
    let headings: [Heading]
    let entries: [Entry]
    let notes: [Note]
    let search: SearchIndex
    let safeGuard: SafeGuard
}

@MainActor final class WikiStore: ObservableObject {
    @Published private(set) var sections: [WikiSection] = []
    @Published private(set) var headings: [Heading] = []
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var notes: [Note] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    private(set) var search: SearchIndex?
    private(set) var safeGuard: SafeGuard?

    nonisolated static func bundledDataURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Data")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        let bundleData = Bundle.main.bundleURL.appendingPathComponent("Data")
        if FileManager.default.fileExists(atPath: bundleData.path) {
            return bundleData
        }
        return Bundle.main.resourceURL?.appendingPathComponent("Data") ?? bundleData
    }

    private static var cacheDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("wiki")
    }

    nonisolated static func parseAll(from dirURL: URL) throws -> WikiSnapshot {
        let headersURL = dirURL.appendingPathComponent("headers.json")
        let headersData = try Data(contentsOf: headersURL)
        let sections = FmhyParser.parseSections(headersJSON: headersData)

        let rentryURL = dirURL.appendingPathComponent("rentry.html")
        let rentryHTML = (try? String(contentsOf: rentryURL, encoding: .utf8)) ?? ""
        let b64 = Base64Map(html: rentryHTML)

        var allHeadings: [Heading] = []
        var allEntries: [Entry] = []
        var allNotes: [Note] = []

        for section in sections {
            let fileURL = dirURL.appendingPathComponent("\(section.id).md")
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let md = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            let parsed = FmhyParser.parseSection(section, markdown: md, b64: b64)
            allHeadings.append(contentsOf: parsed.headings)
            allEntries.append(contentsOf: parsed.entries)
            allNotes.append(contentsOf: parsed.notes)
        }

        let unsafeDomainsURL = dirURL.appendingPathComponent("filterlist-domains.txt")
        let unsafeDomains = (try? String(contentsOf: unsafeDomainsURL, encoding: .utf8)) ?? ""

        let unsafeReasonsURL = dirURL.appendingPathComponent("filterlists-reasons.json")
        let unsafeReasons = (try? String(contentsOf: unsafeReasonsURL, encoding: .utf8)) ?? ""

        let fmhyListURL = dirURL.appendingPathComponent("fmhy-filterlist.txt")
        let fmhySites = (try? String(contentsOf: fmhyListURL, encoding: .utf8)) ?? ""

        let search = SearchIndex(entries: allEntries, sections: sections)
        let safeGuard = SafeGuard(
            entries: allEntries,
            unsafeDomains: unsafeDomains,
            unsafeReasonsJSON: unsafeReasons,
            fmhySitesList: fmhySites
        )

        return WikiSnapshot(
            sections: sections,
            headings: allHeadings,
            entries: allEntries,
            notes: allNotes,
            search: search,
            safeGuard: safeGuard
        )
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let cacheDir = Self.cacheDirectoryURL
        let cacheHeaders = cacheDir.appendingPathComponent("headers.json")
        let sourceURL: URL
        let cacheDate: Date?

        if FileManager.default.fileExists(atPath: cacheHeaders.path) {
            sourceURL = cacheDir
            if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheHeaders.path),
               let mod = attrs[.modificationDate] as? Date {
                cacheDate = mod
            } else {
                cacheDate = nil
            }
        } else {
            sourceURL = Self.bundledDataURL()
            cacheDate = nil
        }

        do {
            let snapshot = try await Task.detached {
                try Self.parseAll(from: sourceURL)
            }.value

            self.sections = snapshot.sections
            self.headings = snapshot.headings
            self.entries = snapshot.entries
            self.notes = snapshot.notes
            self.search = snapshot.search
            self.safeGuard = snapshot.safeGuard
            self.lastUpdated = cacheDate
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("wiki_refresh_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            self.errorMessage = error.localizedDescription
            return
        }

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        do {
            // 1. Download headers.json
            guard let headersData = try await Self.downloadData(
                primary: URL(string: "https://raw.githubusercontent.com/fmhy/edit/main/docs/.vitepress/transformer/headers.json")!,
                fallback: URL(string: "https://cdn.jsdelivr.net/gh/fmhy/edit@main/docs/.vitepress/transformer/headers.json"),
                allow404: false
            ) else {
                throw URLError(.badServerResponse)
            }
            try headersData.write(to: tempDir.appendingPathComponent("headers.json"))

            // 2. Download rentry.html
            guard let rentryData = try await Self.downloadData(
                primary: URL(string: "https://rentry.co/FMHYB64")!,
                fallback: nil,
                allow404: false
            ) else {
                throw URLError(.badServerResponse)
            }
            try rentryData.write(to: tempDir.appendingPathComponent("rentry.html"))

            // 3. Download filterlist-domains.txt
            guard let filterDomainsData = try await Self.downloadData(
                primary: URL(string: "https://raw.githubusercontent.com/fmhy/FMHYFilterlist/main/filterlist-domains.txt")!,
                fallback: nil,
                allow404: false
            ) else {
                throw URLError(.badServerResponse)
            }
            try filterDomainsData.write(to: tempDir.appendingPathComponent("filterlist-domains.txt"))

            // 4. Download filterlists-reasons.json
            guard let filterReasonsData = try await Self.downloadData(
                primary: URL(string: "https://raw.githubusercontent.com/fmhy/FMHYFilterlist/main/filterlists-reasons.json")!,
                fallback: nil,
                allow404: false
            ) else {
                throw URLError(.badServerResponse)
            }
            try filterReasonsData.write(to: tempDir.appendingPathComponent("filterlists-reasons.json"))

            // 5. Download fmhy-filterlist.txt
            guard let fmhyFilterData = try await Self.downloadData(
                primary: URL(string: "https://raw.githubusercontent.com/fmhy/FMHY-SafeGuard/main/fmhy-filterlist.txt")!,
                fallback: nil,
                allow404: false
            ) else {
                throw URLError(.badServerResponse)
            }
            try fmhyFilterData.write(to: tempDir.appendingPathComponent("fmhy-filterlist.txt"))

            // 6. Download section markdown files
            let candidateSections = FmhyParser.parseSections(headersJSON: headersData)
            for sec in candidateSections {
                let fileName = "\(sec.id).md"
                let primaryURL = URL(string: "https://raw.githubusercontent.com/fmhy/edit/main/docs/\(fileName)")!
                let fallbackURL = URL(string: "https://cdn.jsdelivr.net/gh/fmhy/edit@main/docs/\(fileName)")!
                if let fileData = try await Self.downloadData(primary: primaryURL, fallback: fallbackURL, allow404: true) {
                    try fileData.write(to: tempDir.appendingPathComponent(fileName))
                }
            }

            // Test parsing from tempDir
            let snapshot = try await Task.detached {
                try Self.parseAll(from: tempDir)
            }.value

            if self.entries.count > 0 && snapshot.entries.count < Int(Double(self.entries.count) * 0.7) {
                throw NSError(
                    domain: "WikiStore",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "Refresh aborted: incoming entries count is below 70% threshold"]
                )
            }

            let cacheDir = Self.cacheDirectoryURL
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: cacheDir.path) {
                try fileManager.removeItem(at: cacheDir)
            }
            let parentDir = cacheDir.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDir.path) {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            try fileManager.moveItem(at: tempDir, to: cacheDir)

            let modDate: Date
            if let attrs = try? fileManager.attributesOfItem(atPath: cacheDir.appendingPathComponent("headers.json").path),
               let d = attrs[.modificationDate] as? Date {
                modDate = d
            } else {
                modDate = Date()
            }

            self.sections = snapshot.sections
            self.headings = snapshot.headings
            self.entries = snapshot.entries
            self.notes = snapshot.notes
            self.search = snapshot.search
            self.safeGuard = snapshot.safeGuard
            self.lastUpdated = modDate
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private static func downloadData(primary: URL, fallback: URL? = nil, allow404: Bool = false) async throws -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: primary)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    return data
                } else if http.statusCode == 404 && allow404 {
                    return nil
                }
            }
        } catch {
            if fallback == nil && !allow404 {
                throw error
            }
        }

        if let fallback = fallback {
            do {
                let (data, response) = try await URLSession.shared.data(from: fallback)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        return data
                    } else if http.statusCode == 404 && allow404 {
                        return nil
                    } else if !allow404 {
                        throw URLError(.badServerResponse)
                    }
                }
            } catch {
                if !allow404 {
                    throw error
                }
            }
        }

        if allow404 {
            return nil
        }
        throw URLError(.badServerResponse)
    }

    func entries(in sectionId: String) -> [Entry] {
        entries.filter { $0.sectionId == sectionId }
    }

    func headings(in sectionId: String) -> [Heading] {
        headings.filter { $0.sectionId == sectionId }
    }

    func notes(in sectionId: String) -> [Note] {
        notes.filter { $0.sectionId == sectionId }
    }
}

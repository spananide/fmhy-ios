import Foundation

struct OutlineGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let siteCount: Int
    let preview: String
}

struct GroupSection: Identifiable, Sendable {
    let id: String
    let title: String?
    let entries: [Entry]
    let notes: [Note]
}

struct GroupRoute: Hashable, Sendable {
    let sectionId: String
    let groupId: String
}

enum SectionOutline {
    static let generalId = "_general_"

    static func cleanTitle(_ raw: String) -> String {
        var text = raw
        if let linkRegex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\((?:[^()]+|\\([^()]*\\))*\\)") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = linkRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
        }
        text = text.replacingOccurrences(of: "*", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: "►", with: "")
        text = text.replacingOccurrences(of: "▷", with: "")

        let parts = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    static func topGroups(headings: [Heading], entries: [Entry]) -> [OutlineGroup] {
        var entryCountsByHeading: [String: Int] = [:]
        var nilHeadingCount = 0
        for entry in entries {
            if let hid = entry.headingId {
                entryCountsByHeading[hid, default: 0] += 1
            } else {
                nilHeadingCount += 1
            }
        }

        let sortedHeadings = headings.sorted(by: { $0.ord < $1.ord })
        var directChildrenByParent: [String: [Heading]] = [:]
        for h in sortedHeadings {
            if let pid = h.parentId {
                directChildrenByParent[pid, default: []].append(h)
            }
        }

        var result: [OutlineGroup] = []

        if nilHeadingCount > 0 {
            result.append(OutlineGroup(
                id: generalId,
                title: "General",
                siteCount: nilHeadingCount,
                preview: ""
            ))
        }

        guard let minLevel = headings.map(\.level).min() else {
            return result
        }

        let topHeadings = sortedHeadings.filter { $0.level == minLevel }

        for topHeading in topHeadings {
            var groupHeadingIds = Set<String>()
            groupHeadingIds.insert(topHeading.id)
            var queue = [topHeading.id]
            while let current = queue.popLast() {
                if let children = directChildrenByParent[current] {
                    for child in children {
                        if groupHeadingIds.insert(child.id).inserted {
                            queue.append(child.id)
                        }
                    }
                }
            }

            let siteCount = groupHeadingIds.reduce(0) { $0 + (entryCountsByHeading[$1] ?? 0) }
            if siteCount == 0 {
                continue
            }

            let directChildren = directChildrenByParent[topHeading.id] ?? []
            let preview: String
            if directChildren.isEmpty {
                preview = ""
            } else {
                let titles = directChildren.prefix(4).map { cleanTitle($0.title) }
                var joined = titles.joined(separator: ", ")
                if directChildren.count > 4 {
                    joined += " ..."
                }
                preview = joined
            }

            result.append(OutlineGroup(
                id: topHeading.id,
                title: cleanTitle(topHeading.title),
                siteCount: siteCount,
                preview: preview
            ))
        }

        return result
    }

    static func sections(forGroup groupId: String, headings: [Heading], entries: [Entry], notes: [Note]) -> [GroupSection] {
        if groupId == generalId {
            let rootEntries = entries.filter { $0.headingId == nil }.sorted(by: { $0.ord < $1.ord })
            let rootNotes = notes.filter { $0.headingId == nil }.sorted(by: { $0.ord < $1.ord })
            return [GroupSection(id: generalId, title: nil, entries: rootEntries, notes: rootNotes)]
        }

        var entriesByHeading: [String: [Entry]] = [:]
        for entry in entries {
            if let hid = entry.headingId {
                entriesByHeading[hid, default: []].append(entry)
            }
        }

        var notesByHeading: [String: [Note]] = [:]
        for note in notes {
            if let hid = note.headingId {
                notesByHeading[hid, default: []].append(note)
            }
        }

        var result: [GroupSection] = []

        let groupEntries = (entriesByHeading[groupId] ?? []).sorted(by: { $0.ord < $1.ord })
        let groupNotes = (notesByHeading[groupId] ?? []).sorted(by: { $0.ord < $1.ord })
        if !groupEntries.isEmpty || !groupNotes.isEmpty {
            result.append(GroupSection(
                id: groupId,
                title: nil,
                entries: groupEntries,
                notes: groupNotes
            ))
        }

        var childrenByParent: [String: [String]] = [:]
        for h in headings {
            if let pid = h.parentId {
                childrenByParent[pid, default: []].append(h.id)
            }
        }

        var descendantIds = Set<String>()
        var queue = [groupId]
        while let current = queue.popLast() {
            if let children = childrenByParent[current] {
                for childId in children {
                    if descendantIds.insert(childId).inserted {
                        queue.append(childId)
                    }
                }
            }
        }

        let sortedDescendants = headings
            .filter { descendantIds.contains($0.id) }
            .sorted(by: { $0.ord < $1.ord })

        for descendant in sortedDescendants {
            let dEntries = (entriesByHeading[descendant.id] ?? []).sorted(by: { $0.ord < $1.ord })
            let dNotes = (notesByHeading[descendant.id] ?? []).sorted(by: { $0.ord < $1.ord })

            if !dEntries.isEmpty || !dNotes.isEmpty {
                result.append(GroupSection(
                    id: descendant.id,
                    title: cleanTitle(descendant.title),
                    entries: dEntries,
                    notes: dNotes
                ))
            }
        }

        return result
    }
}

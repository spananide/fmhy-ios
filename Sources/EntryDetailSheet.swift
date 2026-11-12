import SwiftUI

struct EntryDetailSheet: View {
    let entry: Entry
    @EnvironmentObject var bookmarks: Bookmarks
    @Environment(\.dismiss) private var dismiss
    @State private var safariTarget: SafariTarget?

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            if entry.tier == 2 {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.headline)
                                    .accessibilityLabel("Top pick")
                            } else if entry.tier == 1 {
                                Image(systemName: "star")
                                    .foregroundStyle(.yellow)
                                    .font(.headline)
                                    .accessibilityLabel("Starred")
                            }
                            Text(entry.name)
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                        }

                        if !entry.description.isEmpty {
                            Text(entry.description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        if !entry.tags.isEmpty {
                            Text(entry.tags.joined(separator: " · "))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if !entry.headingPath.isEmpty {
                            Label(entry.headingPath, systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if entry.isBase64 {
                            Label("Link was hidden in base64 on the wiki", systemImage: "lock.shield")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)

                    Button {
                        if let target = SafariTarget(urlString: entry.url) {
                            safariTarget = target
                        }
                    } label: {
                        Label("Open site", systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(SafariTarget(urlString: entry.url) == nil)
                    .padding(.vertical, 2)
                }

                SwiftUI.Section {
                    Button {
                        UIPasteboard.general.string = entry.url
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                    }

                    if let url = URL(string: entry.url) {
                        ShareLink(item: url) {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button {
                        bookmarks.toggle(entry.id)
                    } label: {
                        let isSaved = bookmarks.isSaved(entry.id)
                        Label(
                            isSaved ? "Remove from Saved" : "Save bookmark",
                            systemImage: isSaved ? "bookmark.slash" : "bookmark"
                        )
                    }
                }

                if !entry.mirrors.isEmpty {
                    SwiftUI.Section("Mirrors") {
                        ForEach(entry.mirrors.indices, id: \.self) { index in
                            let mirror = entry.mirrors[index]
                            Button {
                                if let target = SafariTarget(urlString: mirror.url) {
                                    safariTarget = target
                                }
                            } label: {
                                HStack {
                                    Text(mirror.label)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(mirror.url.hostOnly)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "safari")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(SafariTarget(urlString: mirror.url) == nil)
                        }
                    }
                }

                if !entry.extraLinks.isEmpty {
                    SwiftUI.Section("More links") {
                        ForEach(entry.extraLinks.indices, id: \.self) { index in
                            let extra = entry.extraLinks[index]
                            Button {
                                if let target = SafariTarget(urlString: extra.url) {
                                    safariTarget = target
                                }
                            } label: {
                                HStack {
                                    Text(extra.label)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(extra.url.hostOnly)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "safari")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(SafariTarget(urlString: extra.url) == nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .fullScreenCover(item: $safariTarget) { target in
            SafariView(url: target.url)
                .ignoresSafeArea()
        }
    }
}

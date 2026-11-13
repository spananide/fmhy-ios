import SwiftUI

struct NoteSheet: View {
    let note: Note
    @EnvironmentObject var hub: BrowserHub
    @Environment(\.dismiss) private var dismiss

    nonisolated static func gitHubURL(for sectionId: String) -> URL? {
        let trimmed = sectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return URL(string: "https://github.com/fmhy/edit/blob/main/docs/\(trimmed).md")
    }

    private var gitHubURL: URL? {
        Self.gitHubURL(for: note.sectionId)
    }

    private var markdownContent: some View {
        Group {
            if let attr = try? AttributedString(markdown: note.text) {
                Text(attr)
                    .font(.body)
                    .foregroundStyle(.primary)
            } else {
                Text(note.text)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerView
                    Divider()
                    markdownContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                    gitHubButtonSection
                }
                .padding(20)
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title2)
                .foregroundStyle(fmhyPurple)

            Text("Section Note")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    @ViewBuilder
    private var gitHubButtonSection: some View {
        if let url = gitHubURL {
            VStack(spacing: 8) {
                Divider()
                    .padding(.vertical, 8)

                Button {
                    dismiss()
                    hub.open(url)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

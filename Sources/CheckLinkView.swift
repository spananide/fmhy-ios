import SwiftUI

struct CheckLinkView: View {
    @EnvironmentObject var store: WikiStore
    @State private var urlInput = ""
    @State private var currentVerdict: Verdict?
    @State private var selectedEntry: Entry?

    private func performCheck() {
        let text = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let safeGuard = store.safeGuard else { return }
        currentVerdict = safeGuard.check(text)
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    HStack {
                        TextField("Enter URL or domain (e.g. example.com)", text: $urlInput)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                performCheck()
                            }

                        if !urlInput.isEmpty {
                            Button {
                                urlInput = ""
                                currentVerdict = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear input")
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            if let paste = UIPasteboard.general.string {
                                urlInput = paste
                                performCheck()
                            }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Button {
                            performCheck()
                        } label: {
                            Label("Check", systemImage: "checkmark.shield")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let verdict = currentVerdict {
                    SwiftUI.Section {
                        VStack(spacing: 12) {
                            Image(systemName: verdict.status.symbolName)
                                .font(.system(size: 48))
                                .foregroundStyle(verdict.status.color)
                                .padding(.top, 8)

                            Text(verdict.status.title)
                                .font(.title2.bold())
                                .foregroundStyle(verdict.status.color)
                                .multilineTextAlignment(.center)

                            if let host = verdict.host, !host.isEmpty {
                                Text(host)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }

                            if let reason = verdict.reason, !reason.isEmpty {
                                Text(reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    }

                    if !verdict.matches.isEmpty {
                        SwiftUI.Section("Matched FMHY Sites") {
                            ForEach(verdict.matches) { entry in
                                EntryRow(entry: entry) { selected in
                                    selectedEntry = selected
                                }
                            }
                        }
                    }

                    if !verdict.lookalikes.isEmpty {
                        SwiftUI.Section("Possible clones of") {
                            ForEach(verdict.lookalikes) { entry in
                                EntryRow(entry: entry) { selected in
                                    selectedEntry = selected
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Check Link")
            .sheet(item: $selectedEntry) { entry in
                EntryDetailSheet(entry: entry)
            }
        }
    }
}

private extension SafetyStatus {
    var title: String {
        switch self {
        case .starred:
            return "Starred on FMHY"
        case .fmhySite, .listed, .domainListed:
            return "Listed on FMHY"
        case .potentiallyUnsafe:
            return "Potentially unsafe"
        case .unsafe:
            return "Unsafe \u{2014} on the FMHY unsafe list"
        case .searchEngine:
            return "Search engine"
        case .noData:
            return "Not on FMHY \u{2014} no data"
        case .invalid:
            return "That doesn't look like a link"
        }
    }

    var color: Color {
        switch self {
        case .fmhySite, .starred, .listed, .domainListed:
            return .green
        case .potentiallyUnsafe:
            return .orange
        case .unsafe:
            return .red
        case .searchEngine, .noData, .invalid:
            return .gray
        }
    }

    var symbolName: String {
        switch self {
        case .starred:
            return "star.circle.fill"
        case .fmhySite, .listed, .domainListed:
            return "checkmark.shield.fill"
        case .potentiallyUnsafe:
            return "exclamationmark.triangle.fill"
        case .unsafe:
            return "xmark.shield.fill"
        case .searchEngine:
            return "magnifyingglass.circle.fill"
        case .noData:
            return "questionmark.circle.fill"
        case .invalid:
            return "exclamationmark.circle.fill"
        }
    }
}

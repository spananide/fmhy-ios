import SwiftUI

// MARK: - Download Offer Sheet

public struct DownloadOfferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var checks: DownloadChecks
    @EnvironmentObject private var checkPrefs: CheckPrefs

    @State private var urlString: String
    @State private var isCheckingLink = false
    @State private var linkScanResult: ScanResult?
    @State private var showingResultSheet = false
    @State private var showKeyPrompt = false
    @State private var showExplainDialog = false
    @State private var pendingService: ScanService?

    public var onDownload: (URL) -> Void

    public init(initialURL: String = "", onDownload: @escaping (URL) -> Void) {
        _urlString = State(initialValue: initialURL)
        self.onDownload = onDownload
    }

    private var parsedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private var fileNameGuess: String {
        guard let url = parsedURL else {
            return "download"
        }
        let last = url.lastPathComponent
        return last.isEmpty ? "download" : last
    }

    private var hostGuess: String {
        parsedURL?.host?.lowercased() ?? ""
    }

    private var isRisky: Bool {
        CheckPolicy.isAutoCheckType(fileNameGuess) || CheckPolicy.isRiskyExtension(fileNameGuess)
    }

    private var isDangerous: Bool {
        linkScanResult?.verdict == .dangerous
    }

    private var chipList: [CheckChipData] {
        guard let res = linkScanResult else { return [] }
        return CheckChips.build(
            result: res,
            readyServices: checkPrefs.readyServices,
            fileSize: 0
        )
    }

    public var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    TextField("https://example.com/file.zip", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: urlString) { _, _ in
                            linkScanResult = nil
                        }
                } header: {
                    Text("Download URL")
                }
                .fmhyRowBackground()

                if parsedURL != nil {
                    SwiftUI.Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "doc")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                Text(fileNameGuess)
                                    .font(.headline)
                                    .lineLimit(2)
                            }

                            if !hostGuess.isEmpty {
                                Text(hostGuess)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        if isRisky {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text("This file can install software")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                                Text(CheckPolicy.warningMessage(host: hostGuess.isEmpty ? "this site" : hostGuess))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("File Details")
                    }
                    .fmhyRowBackground()

                    SwiftUI.Section {
                        if isCheckingLink {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Checking link…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else if let res = linkScanResult {
                            VStack(alignment: .leading, spacing: 8) {
                                CheckChipRow(chips: chipList) { chip in
                                    showingResultSheet = true
                                }

                                if isDangerous {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.shield.fill")
                                            .foregroundStyle(.red)
                                        Text(CheckUiText.linkVerdictTitle(res.verdict))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            Button {
                                checkLink()
                            } label: {
                                HStack {
                                    Image(systemName: "shield.checkerboard")
                                    Text("Check link first")
                                        .fontWeight(isRisky ? .semibold : .regular)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .modifier(CheckButtonProminence(prominent: isRisky))
                            .tint(isRisky ? fmhyPurple : .primary)
                        }
                    } header: {
                        Text("Safety Check")
                    } footer: {
                        if !checkPrefs.readyServices.isEmpty {
                            Text(CheckUiText.sendNote(checkPrefs.readyServices))
                        }
                    }
                    .fmhyRowBackground()
                }

                SwiftUI.Section {
                    if isDangerous {
                        Button(role: .destructive) {
                            startDownload()
                        } label: {
                            Text("Download anyway")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    } else {
                        Button {
                            startDownload()
                        } label: {
                            Text("Download")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                        .disabled(parsedURL == nil)
                        .tint(fmhyPurple)
                    }

                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
                .fmhyRowBackground()
            }
            .listStyle(.insetGrouped)
            .fmhyListStyle()
            .navigationTitle("Add Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingResultSheet) {
                if let res = linkScanResult {
                    ScanResultSheet(result: res, isLink: true)
                }
            }
            .alert("Check risky files automatically?", isPresented: $showKeyPrompt) {
                Button("Set up a key") {
                    dismiss()
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("Automatic checks need a free VirusTotal or Hybrid Analysis key. Until you add one, nothing is sent.")
            }
        }
    }

    private func checkLink() {
        guard let url = parsedURL else { return }
        let services = checkPrefs.readyServices
        guard !services.isEmpty else {
            showKeyPrompt = true
            return
        }

        isCheckingLink = true
        Task {
            let res = await checks.checkLink(url: url.absoluteString, services: services)
            await MainActor.run {
                self.linkScanResult = res
                self.isCheckingLink = false
            }
        }
    }

    private func startDownload() {
        guard let url = parsedURL else { return }
        onDownload(url)
        dismiss()
    }
}

private struct CheckButtonProminence: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

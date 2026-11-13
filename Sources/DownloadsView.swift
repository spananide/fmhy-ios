import SwiftUI
import QuickLook
import UIKit
import UniformTypeIdentifiers

struct DownloadsView: View {
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var checks: DownloadChecks
    @EnvironmentObject var checkPrefs: CheckPrefs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("downloads.warnRisky") private var warnRiskyFiles: Bool = true

    @State private var showDownloadOffer = false
    @State private var showFileImporter = false
    @State private var fileImporterProgress = false
    @State private var showingScanResult: ScanResult?
    @State private var pendingUpload: PendingUploadTarget?
    @State private var pendingUploadTooBigService: ScanService?
    @State private var pendingCheckChooserItem: DownloadItem?
    @State private var pendingDangerousKeepItem: DownloadItem?
    @State private var pendingDangerousOpenItem: DownloadItem?
    @State private var showSetUpChecksDialog = false
    @State private var itemToConfirm: DownloadItem?
    @State private var showRiskyAlert = false
    @State private var activeSheet: ActiveSheet?

    private struct PendingUploadTarget {
        let item: DownloadItem
        let service: ScanService
    }

    private enum ActiveSheet: Identifiable {
        case quickLook(URL)
        case share(URL)

        var id: String {
            switch self {
            case .quickLook(let url): return "ql-\(url.absoluteString)"
            case .share(let url): return "share-\(url.absoluteString)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            layerFive
        }
    }

    private var listContent: some View {
        Group {
            if downloads.items.isEmpty {
                ContentUnavailableView("No downloads", systemImage: "arrow.down.circle")
            } else {
                List {
                    ForEach(downloads.items) { item in
                        downloadRow(item)
                    }
                }
                .listStyle(.insetGrouped)
                .fmhyListStyle()
            }
        }
    }

    private var layerOne: some View {
        listContent
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showDownloadOffer = true
                        } label: {
                            Label("Add download URL…", systemImage: "plus")
                        }

                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Check a file…", systemImage: "shield.checkerboard")
                        }

                        Divider()

                        Button(role: .destructive) {
                            downloads.clearFinished()
                        } label: {
                            Label("Clear finished", systemImage: "trash")
                        }
                        .disabled(!downloads.items.contains {
                            $0.state == .completed || $0.state == .failed || $0.state == .cancelled
                        })
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                    Button {
                        showDownloadOffer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add URL")
                }
            }
            .overlay {
                if fileImporterProgress {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.3)
                            Text("Checking file…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(24)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
    }

    private var layerTwo: some View {
        layerOne
            .sheet(isPresented: $showDownloadOffer) {
                DownloadOfferSheet { url in
                    downloads.start(url: url)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let fileURL = urls.first else { return }
                    handlePickedFile(fileURL)
                case .failure:
                    break
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .quickLook(let url):
                    QuickLookPreviewView(url: url)
                case .share(let url):
                    ShareSheetView(activityItems: [url])
                }
            }
            .sheet(isPresented: Binding(
                get: { showingScanResult != nil },
                set: { if !$0 { showingScanResult = nil } }
            )) {
                if let res = showingScanResult {
                    ScanResultSheet(result: res, isLink: res.kind == .link)
                }
            }
    }

    private var layerThree: some View {
        layerTwo
            .alert("Risky file", isPresented: $showRiskyAlert, presenting: itemToConfirm) { item in
                Button("Open anyway") {
                    downloads.confirmRisky(item.id)
                    if let fileURL = downloads.fileURL(for: item) {
                        openFile(fileURL)
                    }
                }
                Button("Cancel", role: .cancel) {
                    itemToConfirm = nil
                }
            } message: { _ in
                Text("This file type can run code. Only open it if you trust the source.")
            }
            .alert(
                "Open a dangerous file?",
                isPresented: Binding(
                    get: { pendingDangerousOpenItem != nil },
                    set: { if !$0 { pendingDangerousOpenItem = nil } }
                ),
                presenting: pendingDangerousOpenItem
            ) { item in
                Button("Open anyway", role: .destructive) {
                    if let fileURL = downloads.fileURL(for: item) {
                        openFile(fileURL)
                    }
                    pendingDangerousOpenItem = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDangerousOpenItem = nil
                }
            } message: { _ in
                Text("This file was flagged as dangerous. Opening it can harm your phone.")
            }
            .alert(
                "Keep a dangerous file?",
                isPresented: Binding(
                    get: { pendingDangerousKeepItem != nil },
                    set: { if !$0 { pendingDangerousKeepItem = nil } }
                ),
                presenting: pendingDangerousKeepItem
            ) { item in
                Button("Keep anyway", role: .destructive) {
                    downloads.keepAfterCheck(item.id)
                    pendingDangerousKeepItem = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDangerousKeepItem = nil
                }
            } message: { _ in
                Text("This file was flagged as dangerous. It will be moved to your download folder.")
            }
    }

    private var layerFour: some View {
        layerThree
            .alert(
                "Upload for analysis?",
                isPresented: Binding(
                    get: { pendingUpload != nil },
                    set: { if !$0 { pendingUpload = nil } }
                ),
                presenting: pendingUpload
            ) { pair in
                Button("Upload") {
                    downloads.uploadItem(pair.item.id, service: pair.service)
                    pendingUpload = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUpload = nil
                }
            } message: { pair in
                Text("\(pair.service.label) doesn't know this file yet. Uploading sends the whole file. Uploaded files may be shared with the service's security partners and researchers, so don't upload private files. New analyses can take a few minutes; you'll get a notification when it's done.")
            }
            .alert(
                "File too big",
                isPresented: Binding(
                    get: { pendingUploadTooBigService != nil },
                    set: { if !$0 { pendingUploadTooBigService = nil } }
                ),
                presenting: pendingUploadTooBigService
            ) { service in
                Button("Open website") {
                    if let url = URL(string: ScanLinks.uploadPage(service: service)) {
                        openURL(url)
                    }
                    pendingUploadTooBigService = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUploadTooBigService = nil
                }
            } message: { service in
                Text(ScanText.error(service: service, e: .tooBig))
            }
            .alert("Set up file checks", isPresented: $showSetUpChecksDialog) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Turn on VirusTotal or Hybrid Analysis and add a free key in settings to check files.")
            }
    }

    private var layerFive: some View {
        layerFour
            .alert(
                "Check risky files automatically?",
                isPresented: Binding(
                    get: { downloads.keyPromptItem != nil },
                    set: { if !$0 { downloads.keyPromptItem = nil } }
                )
            ) {
                Button("Set up a key") {
                    checkPrefs.keyPromptShown = true
                    downloads.keyPromptItem = nil
                }
                Button("Not now", role: .cancel) {
                    checkPrefs.keyPromptShown = true
                    downloads.keyPromptItem = nil
                }
            } message: {
                Text("Automatic checks need a free VirusTotal or Hybrid Analysis key. Until you add one, nothing is sent.")
            }
            .confirmationDialog(
                "Check with",
                isPresented: Binding(
                    get: { pendingCheckChooserItem != nil },
                    set: { if !$0 { pendingCheckChooserItem = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingCheckChooserItem
            ) { item in
                Button("VirusTotal") {
                    downloads.checkItem(item.id, services: [.virusTotal])
                    pendingCheckChooserItem = nil
                }
                Button("Hybrid Analysis") {
                    downloads.checkItem(item.id, services: [.hybridAnalysis])
                    pendingCheckChooserItem = nil
                }
                Button("Both") {
                    downloads.checkItem(item.id, services: [.virusTotal, .hybridAnalysis])
                    pendingCheckChooserItem = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingCheckChooserItem = nil
                }
            }
    }

    // MARK: - Row View

    @ViewBuilder
    private func downloadRow(_ item: DownloadItem) -> some View {
        Button {
            handleTapItem(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: item.fileName))
                    .font(.system(size: 26))
                    .foregroundStyle(iconColor(for: item))
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(statusLine(for: item))
                        .font(.footnote)
                        .foregroundStyle(statusColor(for: item))
                        .lineLimit(1)

                    if item.state == .downloading {
                        if item.bytesTotal > 0 {
                            ProgressView(value: Double(item.bytesReceived), total: Double(item.bytesTotal))
                                .progressViewStyle(.linear)
                                .tint(fmhyPurple)
                        } else {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(fmhyPurple)
                        }
                    }

                    if item.isRisky {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("⚠︎ Can run code")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                    }

                    if let check = item.check {
                        let fileSize = item.bytesTotal > 0 ? item.bytesTotal : item.bytesReceived
                        let chips = CheckChips.build(
                            result: check,
                            readyServices: checkPrefs.readyServices,
                            fileSize: fileSize
                        )
                        CheckChipRow(chips: chips) { chip in
                            handleChipTap(chip, for: item)
                        }
                        .padding(.top, 2)
                    }

                    if item.state == .awaitingDecision {
                        let isDangerous = item.check?.verdict == .dangerous
                        HStack(spacing: 8) {
                            if isDangerous {
                                Button(role: .destructive) {
                                    downloads.delete(item)
                                } label: {
                                    Text("Delete")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)

                                Button {
                                    pendingDangerousKeepItem = item
                                } label: {
                                    Text("Keep")
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button {
                                    downloads.keepAfterCheck(item.id)
                                } label: {
                                    Text("Keep")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(fmhyPurple)

                                Button(role: .destructive) {
                                    downloads.delete(item)
                                } label: {
                                    Text("Delete")
                                }
                                .buttonStyle(.bordered)
                            }

                            if item.check == nil {
                                Button {
                                    handleCheckFile(item)
                                } label: {
                                    Text("Check")
                                }
                                .buttonStyle(.bordered)
                            } else if let unknownService = checkPrefs.readyServices.first(where: { ready in
                                let sr = item.check?.services.first(where: { $0.service == ready })
                                return sr?.verdict == .unknown && sr?.error == nil
                            }) {
                                Button {
                                    pendingUpload = PendingUploadTarget(item: item, service: unknownService)
                                } label: {
                                    Text("Upload")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.top, 4)
                    } else if item.state == .completed && (item.isRisky || item.check == nil) {
                        Button {
                            handleCheckFile(item)
                        } label: {
                            Label(item.check == nil ? "Check file" : "Check again", systemImage: "shield.checkerboard")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(fmhyPurple)
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fmhyRowBackground()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                downloads.delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if item.state == .downloading {
                Button {
                    downloads.pause(item)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .tint(.orange)
            } else if item.state == .paused {
                Button {
                    downloads.resume(item)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(.blue)
            } else if item.state == .failed {
                Button {
                    downloads.retry(item)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(.green)
            }
        }
        .contextMenu {
            if item.state == .completed,
               let fileURL = downloads.fileURL(for: item),
               FileManager.default.fileExists(atPath: fileURL.path) {
                ShareLink(item: fileURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            if !item.sourceURL.isEmpty {
                Button {
                    UIPasteboard.general.string = item.sourceURL
                } label: {
                    Label("Copy source link", systemImage: "doc.on.doc")
                }
            }

            if item.state == .completed {
                Button {
                    handleCheckFile(item)
                } label: {
                    Label(item.check == nil ? "Check file" : "Check again", systemImage: "shield.checkerboard")
                }
            }

            Button(role: .destructive) {
                downloads.delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions & Helpers

    private func handleTapItem(_ item: DownloadItem) {
        guard item.state == .completed else { return }
        guard let fileURL = downloads.fileURL(for: item),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        if CheckPolicy.needsExtraConfirm(item.check) {
            pendingDangerousOpenItem = item
        } else if warnRiskyFiles && item.isRisky && !item.riskyConfirmed {
            itemToConfirm = item
            showRiskyAlert = true
        } else {
            openFile(fileURL)
        }
    }

    private func handleChipTap(_ chip: CheckChipData, for item: DownloadItem) {
        switch chip.action {
        case .showResult:
            if let check = item.check {
                showingScanResult = check
            }
        case .upload:
            pendingUpload = PendingUploadTarget(item: item, service: chip.service)
        case .tooBig:
            pendingUploadTooBigService = chip.service
        case .retry:
            downloads.checkItem(item.id, services: [chip.service])
        }
    }

    private func handleCheckFile(_ item: DownloadItem) {
        let ready = checkPrefs.readyServices
        if ready.count == 2 {
            pendingCheckChooserItem = item
        } else if ready.count == 1 {
            downloads.checkItem(item.id, services: ready)
        } else {
            showSetUpChecksDialog = true
        }
    }

    private func handlePickedFile(_ sourceURL: URL) {
        guard sourceURL.startAccessingSecurityScopedResource() else { return }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("picked-\(UUID().uuidString)-\(sourceURL.lastPathComponent)")
        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        } catch {
            return
        }

        fileImporterProgress = true

        Task {
            let sha: String
            do {
                sha = try await checks.fingerprint(fileURL: tempURL)
            } catch {
                await MainActor.run { fileImporterProgress = false }
                return
            }

            let ready = checkPrefs.readyServices
            if ready.isEmpty {
                await MainActor.run {
                    fileImporterProgress = false
                    showSetUpChecksDialog = true
                }
                return
            }

            let res = await checks.checkFile(sha256: sha, services: ready)
            await MainActor.run {
                self.fileImporterProgress = false
                self.showingScanResult = res
            }
        }
    }

    private func openFile(_ url: URL) {
        if QLPreviewController.canPreview(url as NSURL) {
            activeSheet = .quickLook(url)
        } else {
            activeSheet = .share(url)
        }
    }

    private func iconName(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return "archivebox"
        case "jpg", "jpeg", "png", "gif", "webp", "svg", "heic":
            return "photo"
        case "mp4", "mkv", "mov", "avi", "webm":
            return "film"
        case "mp3", "flac", "wav", "aac", "m4a", "ogg":
            return "music.note"
        case "pdf", "doc", "docx", "txt", "rtf", "md":
            return "doc.richtext"
        default:
            return "doc"
        }
    }

    private func iconColor(for item: DownloadItem) -> Color {
        switch item.state {
        case .completed:
            return item.isRisky ? .orange : .green
        case .checking:
            return .blue
        case .awaitingDecision:
            return .orange
        case .failed:
            return .red
        case .downloading:
            return fmhyPurple
        case .paused:
            return .orange
        case .queued, .cancelled:
            return .secondary
        }
    }

    private func statusLine(for item: DownloadItem) -> String {
        switch item.state {
        case .queued:
            return "Queued"
        case .downloading:
            let receivedStr = ByteCountFormatter.string(fromByteCount: item.bytesReceived, countStyle: .file)
            if item.bytesTotal > 0 {
                let totalStr = ByteCountFormatter.string(fromByteCount: item.bytesTotal, countStyle: .file)
                let percent = Int(Double(item.bytesReceived) / Double(item.bytesTotal) * 100)
                return "\(receivedStr) of \(totalStr) · \(percent)%"
            } else {
                return "\(receivedStr) · downloading"
            }
        case .checking:
            return "Being checked"
        case .awaitingDecision:
            return "Waiting for your decision"
        case .paused:
            return "Paused"
        case .completed:
            if item.bytesReceived > 0 {
                let sizeStr = ByteCountFormatter.string(fromByteCount: item.bytesReceived, countStyle: .file)
                return "Completed · \(sizeStr)"
            } else {
                return "Completed"
            }
        case .failed:
            return "Failed: \(item.errorMessage ?? "Unknown error")"
        case .cancelled:
            return "Cancelled"
        }
    }

    private func statusColor(for item: DownloadItem) -> Color {
        switch item.state {
        case .failed:
            return .red
        case .checking:
            return .blue
        case .awaitingDecision:
            return .orange
        case .completed:
            return .secondary
        case .downloading:
            return .primary
        default:
            return .secondary
        }
    }
}

// MARK: - QuickLook & Share Sheet Wrappers

struct QuickLookPreviewView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

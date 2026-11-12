import SwiftUI
import QuickLook
import UIKit

struct DownloadsView: View {
    @EnvironmentObject var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("downloads.warnRisky") private var warnRiskyFiles: Bool = true

    @State private var showAddURLAlert = false
    @State private var newURLInput = ""
    @State private var activeSheet: ActiveSheet?
    @State private var itemToConfirm: DownloadItem?
    @State private var showRiskyAlert = false

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
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        newURLInput = ""
                        showAddURLAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add URL")

                    Button("Clear finished") {
                        downloads.clearFinished()
                    }
                    .disabled(!downloads.items.contains {
                        $0.state == .completed || $0.state == .failed || $0.state == .cancelled
                    })
                }
            }
            .alert("Add download URL", isPresented: $showAddURLAlert) {
                TextField("https://example.com/file.zip", text: $newURLInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Download") {
                    let trimmed = newURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = URL(string: trimmed),
                       let scheme = url.scheme?.lowercased(),
                       scheme == "http" || scheme == "https" {
                        downloads.start(url: url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter an HTTP or HTTPS link to start downloading.")
            }
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
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .quickLook(let url):
                    QuickLookPreviewView(url: url)
                case .share(let url):
                    ShareSheetView(activityItems: [url])
                }
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

                    if let vt = item.vt {
                        HStack(spacing: 4) {
                            Image(systemName: vt.malicious > 0 ? "xmark.shield.fill" : (vt.suspicious > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill"))
                            Text(vt.verdictText)
                        }
                        .font(.caption2)
                        .foregroundStyle(vt.malicious > 0 ? .red : (vt.suspicious > 0 ? .orange : .green))
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

            if item.state == .completed && KeychainStore.get("vt.apiKey") != nil {
                Button {
                    Task {
                        await downloads.checkVirusTotal(item.id)
                    }
                } label: {
                    Label("Check on VirusTotal", systemImage: "shield.checkerboard")
                }
            }

            if let permalink = item.vt?.permalink, let url = URL(string: permalink) {
                SwiftUI.Link(destination: url) {
                    Label("View on VirusTotal", systemImage: "arrow.up.right.square")
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

        let needsConfirmation = warnRiskyFiles && item.isRisky && !item.riskyConfirmed
        if needsConfirmation {
            itemToConfirm = item
            showRiskyAlert = true
        } else {
            openFile(fileURL)
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

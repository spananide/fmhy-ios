import SwiftUI
import SafariServices

struct SafariTarget: Identifiable {
    let id = UUID()
    let url: URL

    init?(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        self.url = url
    }

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        self.url = url
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            dismiss()
        }
    }
}

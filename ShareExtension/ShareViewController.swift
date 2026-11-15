import UIKit
import UniformTypeIdentifiers

private struct AttachmentCandidate {
    let provider: NSItemProvider
    let typeIdentifier: String
}

private enum ShareUrlExtractor {
    private static let urlPattern = #"https?://[^\s<>"{}|\\^`]+"#
    private static let trailingPunctuation: Set<Character> = [".", ",", ";", "!", "?", ")", "]", "}", "'", "\""]

    nonisolated static func extractHttpURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if (lower.hasPrefix("http://") || lower.hasPrefix("https://")) && !trimmed.contains(" ") && !trimmed.contains("\n") {
            var cleaned = trimmed
            while let last = cleaned.last, trailingPunctuation.contains(last) {
                cleaned.removeLast()
            }
            if let url = URL(string: cleaned), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return cleaned
            }
        }

        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) else {
            return nil
        }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var matchedString = ns.substring(with: match.range)
        while let last = matchedString.last, trailingPunctuation.contains(last) {
            matchedString.removeLast()
        }
        guard !matchedString.isEmpty else { return nil }
        guard let url = URL(string: matchedString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return matchedString
    }

    nonisolated static func buildCheckURL(for rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
            return nil
        }

        let prefixLength = lower.hasPrefix("https://") ? 8 : 7
        let afterPrefix = trimmed.dropFirst(prefixLength)
        guard !afterPrefix.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "fmhy"
        components.host = "check"
        components.queryItems = [URLQueryItem(name: "url", value: trimmed)]
        return components.url
    }
}

class ShareViewController: UIViewController {
    private let spinner = UIActivityIndicatorView(style: .large)
    private let containerStack = UIStackView()
    private let iconView = UIImageView()
    private let messageLabel = UILabel()
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        spinner.startAnimating()
        processShareItems()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.axis = .vertical
        containerStack.spacing = 16
        containerStack.alignment = .center
        containerStack.isHidden = true
        view.addSubview(containerStack)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "checkmark.shield.fill")
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .label

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "Done"
        buttonConfig.cornerStyle = .capsule
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 24, bottom: 10, trailing: 24)
        doneButton.configuration = buttonConfig
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(handleDoneTapped), for: .touchUpInside)

        containerStack.addArrangedSubview(iconView)
        containerStack.addArrangedSubview(messageLabel)
        containerStack.addArrangedSubview(doneButton)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            containerStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            containerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24)
        ])
    }

    private func findAttachment() -> AttachmentCandidate? {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }

        // Check for URL attachments first
        for item in extensionItems {
            if let attachments = item.attachments {
                for provider in attachments {
                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        return AttachmentCandidate(provider: provider, typeIdentifier: UTType.url.identifier)
                    }
                }
            }
        }

        // Fall back to plain text attachments
        for item in extensionItems {
            if let attachments = item.attachments {
                for provider in attachments {
                    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        return AttachmentCandidate(provider: provider, typeIdentifier: UTType.plainText.identifier)
                    }
                }
            }
        }

        return nil
    }

    private func processShareItems() {
        guard let candidate = findAttachment() else {
            showFallbackUI(message: "No link found to check in FMHY.")
            return
        }

        candidate.provider.loadItem(forTypeIdentifier: candidate.typeIdentifier, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if error != nil {
                    self.showFallbackUI(message: "No link found to check in FMHY.")
                    return
                }
                self.handleLoadedItem(item, typeIdentifier: candidate.typeIdentifier)
            }
        }
    }

    private func handleLoadedItem(_ item: NSSecureCoding?, typeIdentifier: String) {
        var rawString: String?

        if let url = item as? URL {
            rawString = url.absoluteString
        } else if let nsUrl = item as? NSURL {
            rawString = nsUrl.absoluteString
        } else if let text = item as? String {
            rawString = text
        } else if let nsText = item as? NSString {
            rawString = String(nsText)
        } else if let data = item as? Data {
            rawString = String(data: data, encoding: .utf8)
        }

        guard let content = rawString,
              let extractedURL = ShareUrlExtractor.extractHttpURL(from: content) else {
            showFallbackUI(message: "No link found to check in FMHY.")
            return
        }

        UIPasteboard.general.string = extractedURL

        guard let deepLink = ShareUrlExtractor.buildCheckURL(for: extractedURL) else {
            showFallbackUI(message: "Link copied. Open FMHY, tap Check link, then Paste.")
            return
        }

        openHostApp(url: deepLink) { [weak self] success in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                } else {
                    self.showFallbackUI(message: "Link copied. Open FMHY, tap Check link, then Paste.")
                }
            }
        }
    }

    private func findApplicationResponder() -> UIResponder? {
        let selectors = [
            NSSelectorFromString("open:options:completionHandler:"),
            NSSelectorFromString("openURL:options:completionHandler:"),
            NSSelectorFromString("openURL:")
        ]

        var responder: UIResponder? = self
        while let current = responder {
            for sel in selectors {
                if current.responds(to: sel) {
                    return current
                }
            }
            responder = current.next
        }

        if isViewLoaded {
            var viewResponder: UIResponder? = view
            while let current = viewResponder {
                for sel in selectors {
                    if current.responds(to: sel) {
                        return current
                    }
                }
                viewResponder = current.next
            }
        }

        return nil
    }

    private func openHostApp(url: URL, completion: @escaping (Bool) -> Void) {
        guard let target = findApplicationResponder() as? NSObject else {
            completion(false)
            return
        }

        let selectors = [
            NSSelectorFromString("open:options:completionHandler:"),
            NSSelectorFromString("openURL:options:completionHandler:")
        ]

        for sel in selectors {
            if target.responds(to: sel), let methodIMP = target.method(for: sel) {
                typealias OpenMethod = @convention(c) (
                    NSObject,
                    Selector,
                    NSURL,
                    NSDictionary,
                    (@convention(block) (Bool) -> Void)?
                ) -> Void

                let callable = unsafeBitCast(methodIMP, to: OpenMethod.self)
                let options = NSDictionary()
                callable(target, sel, url as NSURL, options) { success in
                    completion(success)
                }
                return
            }
        }

        let legacySelector = NSSelectorFromString("openURL:")
        if target.responds(to: legacySelector), let methodIMP = target.method(for: legacySelector) {
            typealias LegacyOpenMethod = @convention(c) (
                NSObject,
                Selector,
                NSURL
            ) -> Bool

            let callable = unsafeBitCast(methodIMP, to: LegacyOpenMethod.self)
            let success = callable(target, legacySelector, url as NSURL)
            completion(success)
            return
        }

        completion(false)
    }

    private func showFallbackUI(message: String) {
        spinner.stopAnimating()
        messageLabel.text = message
        containerStack.isHidden = false
    }

    @objc private func handleDoneTapped() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

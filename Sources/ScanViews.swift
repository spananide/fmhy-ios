import SwiftUI

// MARK: - Chip Enums & Data

public enum CheckChipTone: String, Sendable, Equatable {
    case ok
    case warn
    case danger
    case neutral
    case running
}

public enum CheckChipIcon: String, Sendable, Equatable {
    case shieldCheck
    case warning
    case shieldX
    case shieldUnknown
    case cloudOff
    case spinner
}

public enum CheckChipAction: String, Sendable, Equatable {
    case showResult
    case upload
    case tooBig
    case retry
}

public struct CheckChipData: Identifiable, Equatable, Sendable {
    public var id: String { service.rawValue }
    public let service: ScanService
    public let icon: CheckChipIcon
    public let tone: CheckChipTone
    public let text: String
    public let action: CheckChipAction

    public init(
        service: ScanService,
        icon: CheckChipIcon,
        tone: CheckChipTone,
        text: String,
        action: CheckChipAction
    ) {
        self.service = service
        self.icon = icon
        self.tone = tone
        self.text = text
        self.action = action
    }
}

// MARK: - CheckChips Builder

public enum CheckChips {
    public nonisolated static func build(
        result: ScanResult,
        readyServices: [ScanService],
        fileSize: Int64,
        maxUploadBytes: (ScanService) -> Int64 = { service in
            service == .virusTotal ? 650 * 1024 * 1024 : 100 * 1024 * 1024
        }
    ) -> [CheckChipData] {
        var chips: [CheckChipData] = []
        var handledServices = Set<ScanService>()

        for s in result.services {
            if handledServices.insert(s.service).inserted {
                chips.append(buildChip(
                    service: s.service,
                    serviceResult: s,
                    result: result,
                    readyServices: readyServices,
                    fileSize: fileSize,
                    maxUploadBytes: maxUploadBytes
                ))
            }
        }

        for p in result.pending {
            if handledServices.insert(p.service).inserted {
                chips.append(buildChip(
                    service: p.service,
                    serviceResult: nil,
                    result: result,
                    readyServices: readyServices,
                    fileSize: fileSize,
                    maxUploadBytes: maxUploadBytes
                ))
            }
        }

        return chips
    }

    private nonisolated static func buildChip(
        service: ScanService,
        serviceResult: ServiceResult?,
        result: ScanResult,
        readyServices: [ScanService],
        fileSize: Int64,
        maxUploadBytes: (ScanService) -> Int64
    ) -> CheckChipData {
        // 1. Pending analysis running
        if result.pending.contains(where: { $0.service == service }) {
            return CheckChipData(
                service: service,
                icon: .spinner,
                tone: .running,
                text: "Analysis running",
                action: .showResult
            )
        }

        // 2. Error
        if let error = serviceResult?.error {
            switch error {
            case .offline, .other:
                return CheckChipData(
                    service: service,
                    icon: .cloudOff,
                    tone: .neutral,
                    text: "Retry",
                    action: .retry
                )
            case .badKey:
                return CheckChipData(
                    service: service,
                    icon: .cloudOff,
                    tone: .neutral,
                    text: "Key problem",
                    action: .showResult
                )
            case .limit:
                return CheckChipData(
                    service: service,
                    icon: .cloudOff,
                    tone: .neutral,
                    text: "Limit reached",
                    action: .showResult
                )
            case .tooBig:
                return CheckChipData(
                    service: service,
                    icon: .cloudOff,
                    tone: .neutral,
                    text: "Too big",
                    action: .showResult
                )
            }
        }

        // 3. Verdict NO_FLAGS, SUSPICIOUS, DANGEROUS
        let verdict = serviceResult?.verdict ?? .unknown
        switch verdict {
        case .noFlags, .suspicious, .dangerous:
            let icon: CheckChipIcon
            let tone: CheckChipTone
            switch verdict {
            case .noFlags:
                icon = .shieldCheck
                tone = .ok
            case .suspicious:
                icon = .warning
                tone = .warn
            case .dangerous:
                icon = .shieldX
                tone = .danger
            case .unknown:
                icon = .shieldUnknown
                tone = .neutral
            }

            let text: String
            if let flagged = serviceResult?.flagged, let engines = serviceResult?.engines, engines > 0 {
                text = "\(flagged)/\(engines)"
            } else {
                text = verdict.label
            }

            return CheckChipData(
                service: service,
                icon: icon,
                tone: tone,
                text: text,
                action: .showResult
            )

        case .unknown:
            let isReady = readyServices.contains(service)
            if isReady && fileSize > 0 && fileSize > maxUploadBytes(service) {
                return CheckChipData(
                    service: service,
                    icon: .shieldUnknown,
                    tone: .neutral,
                    text: "Unknown · too big",
                    action: .tooBig
                )
            } else if isReady {
                return CheckChipData(
                    service: service,
                    icon: .shieldUnknown,
                    tone: .neutral,
                    text: "Unknown · Upload",
                    action: .upload
                )
            } else {
                return CheckChipData(
                    service: service,
                    icon: .shieldUnknown,
                    tone: .neutral,
                    text: "Unknown",
                    action: .showResult
                )
            }
        }
    }
}

// MARK: - Color Hex Extension

private extension Color {
    init(hexVal: UInt32) {
        let r = Double((hexVal >> 16) & 0xFF) / 255.0
        let g = Double((hexVal >> 8) & 0xFF) / 255.0
        let b = Double(hexVal & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

// MARK: - Check Chip View

public struct CheckChip: View {
    public let chip: CheckChipData
    public var onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(chip: CheckChipData, onTap: @escaping () -> Void = {}) {
        self.chip = chip
        self.onTap = onTap
    }

    private var colors: (bg: Color, fg: Color) {
        let isDark = colorScheme == .dark
        switch chip.tone {
        case .ok:
            return isDark
                ? (Color(hexVal: 0x1D3B26), Color(hexVal: 0x9BE0AC))
                : (Color(hexVal: 0xDDF3E0), Color(hexVal: 0x14532D))
        case .warn:
            return isDark
                ? (Color(hexVal: 0x46330C), Color(hexVal: 0xFFD27A))
                : (Color(hexVal: 0xFFFFEFCC), Color(hexVal: 0x6B4300))
        case .danger:
            return isDark
                ? (Color(hexVal: 0x5A1E1A), Color(hexVal: 0xFFB4AB))
                : (Color(hexVal: 0xFCDEDB), Color(hexVal: 0x8C1A12))
        case .running:
            return isDark
                ? (Color(hexVal: 0x1B3556), Color(hexVal: 0xA9CCFF))
                : (Color(hexVal: 0xDBEAFE), Color(hexVal: 0x0B4A8F))
        case .neutral:
            return isDark
                ? (Color(white: 0.22), Color(white: 0.85))
                : (Color(white: 0.92), Color(white: 0.25))
        }
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                switch chip.icon {
                case .shieldCheck:
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 13, weight: .semibold))
                case .warning:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                case .shieldX:
                    Image(systemName: "xmark.shield.fill")
                        .font(.system(size: 13, weight: .semibold))
                case .shieldUnknown:
                    Image(systemName: "questionmark.shield")
                        .font(.system(size: 13, weight: .semibold))
                case .cloudOff:
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 13, weight: .semibold))
                case .spinner:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                }

                Text("\(chip.service.label) · \(chip.text)")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(colors.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(colors.bg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout for Chips

public struct FlowLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var totalH: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowH: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxW, currentX > 0 {
                currentX = 0
                currentY += rowH + spacing
                rowH = 0
            }
            currentX += size.width + spacing
            rowH = max(rowH, size.height)
            totalH = max(totalH, currentY + rowH)
        }
        return CGSize(width: maxW, height: totalH)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowH: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowH + spacing
                rowH = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

public struct CheckChipRow: View {
    public let chips: [CheckChipData]
    public var onTap: (CheckChipData) -> Void

    public init(chips: [CheckChipData], onTap: @escaping (CheckChipData) -> Void) {
        self.chips = chips
        self.onTap = onTap
    }

    public var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(chips) { chip in
                CheckChip(chip: chip) {
                    onTap(chip)
                }
            }
        }
    }
}

// MARK: - Scan Result Sheet

public struct ScanResultSheet: View {
    public let result: ScanResult
    public var isLink: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(result: ScanResult, isLink: Bool = false) {
        self.result = result
        self.isLink = isLink
    }

    private var titleText: String {
        isLink ? CheckUiText.linkVerdictTitle(result.verdict) : CheckUiText.verdictTitle(result.verdict)
    }

    private var titleDetails: (icon: String, color: Color) {
        switch result.verdict {
        case .dangerous:
            return ("exclamationmark.triangle.fill", .red)
        case .suspicious:
            return ("exclamationmark.triangle.fill", .orange)
        case .noFlags:
            return ("checkmark.circle.fill", .green)
        case .unknown:
            return ("questionmark.circle.fill", .secondary)
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    HStack(spacing: 12) {
                        Image(systemName: titleDetails.icon)
                            .font(.title2)
                            .foregroundStyle(titleDetails.color)

                        Text(titleText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(titleDetails.color)
                    }
                    .padding(.vertical, 4)

                    if result.isRunning {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView()
                                .progressViewStyle(.linear)
                            Text("Analysis running. This can take a few minutes. You'll get a notification when it's done.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .fmhyRowBackground()

                ForEach(Array(result.services.enumerated()), id: \.offset) { entry in
                    let serviceResult: ServiceResult = entry.element
                    SwiftUI.Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(serviceResult.service.label)
                                .font(.headline)

                            Text(CheckUiText.serviceLine(serviceResult))
                                .font(.body)

                            if let scannedAt = serviceResult.scannedAt {
                                let formatter = DateFormatter()
                                formatter.locale = Locale(identifier: "en_US_POSIX")
                                formatter.dateFormat = "d MMM yyyy"
                                Text("Scanned \(formatter.string(from: scannedAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let reportUrl = serviceResult.reportUrl, let url = URL(string: reportUrl) {
                                SwiftUI.Link("Full report", destination: url)
                                    .font(.subheadline.weight(.semibold))
                                    .tint(fmhyPurple)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .fmhyRowBackground()
                }

                SwiftUI.Section {
                    Text(ScanText.REMINDER)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .fmhyRowBackground()
            }
            .listStyle(.insetGrouped)
            .fmhyListStyle()
            .navigationTitle("Scan Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

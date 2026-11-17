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

// MARK: - Check Chip View

public struct CheckChip: View {
    public let chip: CheckChipData
    public var onTap: () -> Void

    public init(chip: CheckChipData, onTap: @escaping () -> Void = {}) {
        self.chip = chip
        self.onTap = onTap
    }

    private var toneColor: Color {
        switch chip.tone {
        case .ok:
            return .green
        case .warn:
            return .orange
        case .danger:
            return .red
        case .running:
            return Color.accentColor
        case .neutral:
            return .secondary
        }
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                switch chip.icon {
                case .shieldCheck:
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(toneColor)
                case .warning:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(toneColor)
                case .shieldX:
                    Image(systemName: "xmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(toneColor)
                case .shieldUnknown:
                    Image(systemName: "questionmark.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(toneColor)
                case .cloudOff:
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(toneColor)
                case .spinner:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                }

                Text("\(chip.service.label) · \(chip.text)")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(toneColor.opacity(0.15), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chip.service.label), \(chip.text)")
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
    @State private var reportTarget: SafariTarget?

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

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func serviceSection(_ serviceResult: ServiceResult) -> some View {
        SwiftUI.Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(serviceResult.service.label)
                    .font(.headline)

                Text(CheckUiText.serviceLine(serviceResult))
                    .font(.body)

                if let scannedAt = serviceResult.scannedAt {
                    Text("Scanned \(Self.dateText(scannedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let reportUrl = serviceResult.reportUrl, let url = URL(string: reportUrl),
                   serviceResult.verdict != .unknown || serviceResult.error != nil {
                    Button("Full report") {
                        reportTarget = SafariTarget(url: url)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .fmhyRowBackground()
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

                ForEach(0..<result.services.count, id: \.self) { index in
                    serviceSection(result.services[index])
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $reportTarget) { target in
                SafariView(url: target.url)
                    .ignoresSafeArea()
            }
        }
    }
}

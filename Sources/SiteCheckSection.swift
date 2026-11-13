import SwiftUI

// MARK: - SiteCheckSection

struct SiteCheckSection: View {
    let host: String
    let verdict: Verdict?
    let isPrivate: Bool

    @EnvironmentObject var downloadChecks: DownloadChecks
    @EnvironmentObject var vtSiteChecks: VtSiteChecks

    @State private var isRunning = false
    @State private var isSubmitting = false
    @State private var localResult: ScanResult?
    @State private var showSubmitConfirm = false
    @State private var showingSheet = false

    private var isHidden: Bool {
        guard !host.isEmpty else { return true }
        guard let v = verdict else { return false }
        switch v.status {
        case .fmhySite, .starred, .listed, .domainListed, .unsafe:
            return true
        case .potentiallyUnsafe, .searchEngine, .noData, .invalid:
            return false
        }
    }

    private var isVtReady: Bool {
        downloadChecks.prefs.isEnabled(for: .virusTotal) &&
        !downloadChecks.prefs.maskedKey(for: .virusTotal).isEmpty
    }

    private var vtMark: VtMark? {
        vtSiteChecks.markFor(host: host)
    }

    private var vtServiceResult: ServiceResult? {
        localResult?.services.first(where: { $0.service == .virusTotal })
    }

    private var activeSheetResult: ScanResult? {
        if let local = localResult {
            return local
        }
        if let mark = vtMark {
            return ScanResult(
                kind: .link,
                services: [
                    ServiceResult(
                        service: .virusTotal,
                        verdict: .noFlags,
                        flagged: mark.flagged,
                        engines: mark.engines,
                        scannedAt: mark.checkedAt
                    )
                ],
                checkedAt: mark.checkedAt
            )
        }
        return nil
    }

    private var runningText: String {
        isSubmitting ? "Scanning with VirusTotal…" : "Checking with VirusTotal…"
    }

    private var runningChipData: CheckChipData {
        CheckChipData(
            service: .virusTotal,
            icon: .spinner,
            tone: .running,
            text: isSubmitting ? "Scanning…" : "Checking…",
            action: .showResult
        )
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private static func flagsText(label: String, flagged: Int?, engines: Int?) -> String {
        if let engines = engines, engines > 0 {
            return "\(label) · \(flagged ?? 0)/\(engines)"
        }
        return label
    }

    private func chipData(for vt: ServiceResult) -> CheckChipData {
        let tone: CheckChipTone
        let icon: CheckChipIcon
        let text: String

        switch vt.verdict {
        case .noFlags:
            tone = .ok
            icon = .shieldCheck
            text = Self.flagsText(label: "No flags", flagged: vt.flagged, engines: vt.engines)
        case .suspicious:
            tone = .warn
            icon = .warning
            text = Self.flagsText(label: "Suspicious", flagged: vt.flagged, engines: vt.engines)
        case .dangerous:
            tone = .danger
            icon = .shieldX
            text = Self.flagsText(label: "Dangerous", flagged: vt.flagged, engines: vt.engines)
        case .unknown:
            tone = .neutral
            icon = .shieldUnknown
            text = "Not known to VirusTotal yet"
        }

        return CheckChipData(
            service: .virusTotal,
            icon: icon,
            tone: tone,
            text: text,
            action: .showResult
        )
    }

    private func markChipData(for mark: VtMark) -> CheckChipData {
        CheckChipData(
            service: .virusTotal,
            icon: .shieldCheck,
            tone: .ok,
            text: Self.flagsText(label: "No flags", flagged: mark.flagged, engines: mark.engines),
            action: .showResult
        )
    }

    private var noFlagsNote: String {
        if isPrivate {
            return "Checked with VirusTotal just now (not remembered in private tabs)"
        }
        let dateStr = Self.dateText(localResult?.checkedAt ?? Date())
        return "Checked with VirusTotal on \(dateStr)"
    }

    private func markNote(_ mark: VtMark) -> String {
        let dateStr = Self.dateText(mark.checkedAt)
        return "Checked \(dateStr): no flags"
    }

    private func runCheck() {
        isRunning = true
        isSubmitting = false
        let target = "https://\(host)/"
        Task {
            let res = await downloadChecks.checkLink(url: target, services: [.virusTotal])
            await MainActor.run {
                self.localResult = res
                self.isRunning = false
                if let vt = res.services.first(where: { $0.service == .virusTotal }),
                   vt.error == nil,
                   VtSiteChecks.shouldRemember(vt.verdict),
                   !isPrivate {
                    vtSiteChecks.remember(host: host, flagged: vt.flagged, engines: vt.engines)
                }
            }
        }
    }

    private func runSubmit() {
        isRunning = true
        isSubmitting = true
        let target = "https://\(host)/"
        Task {
            let res = await downloadChecks.submitLink(url: target, service: .virusTotal)
            await MainActor.run {
                self.localResult = res
                self.isRunning = false
                if let vt = res.services.first(where: { $0.service == .virusTotal }),
                   vt.error == nil,
                   VtSiteChecks.shouldRemember(vt.verdict),
                   !isPrivate {
                    vtSiteChecks.remember(host: host, flagged: vt.flagged, engines: vt.engines)
                }
            }
        }
    }

    // MARK: - Subviews

    private var runningView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
            Text(runningText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ vt: ServiceResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ScanText.error(service: .virusTotal, e: vt.error ?? .other))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Try again") {
                runCheck()
            }
            .font(.subheadline.bold())
        }
    }

    private func vtResultView(_ vt: ServiceResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CheckChip(chip: chipData(for: vt)) {
                showingSheet = true
            }

            switch vt.verdict {
            case .noFlags:
                Text(noFlagsNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .suspicious, .dangerous:
                Text("Not remembered as safe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .unknown:
                Text("Not remembered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Submit for scan") {
                    showSubmitConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func markView(_ mark: VtMark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CheckChip(chip: markChipData(for: mark)) {
                showingSheet = true
            }
            Text(markNote(mark))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var readyIdleView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                runCheck()
            } label: {
                Label("Check with VirusTotal", systemImage: "shield.checkerboard")
            }
            .buttonStyle(.bordered)

            Text("Sends only the site's domain to VirusTotal.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hintView: some View {
        Text("Add a free key in Settings to check with VirusTotal.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    // MARK: - Layered Body

    private var layerOne: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRunning {
                runningView
            } else if let vt = vtServiceResult, vt.error != nil {
                errorView(vt)
            } else if let vt = vtServiceResult {
                vtResultView(vt)
            } else if let mark = vtMark {
                markView(mark)
            } else if isVtReady {
                readyIdleView
            } else {
                hintView
            }
        }
    }

    private var layerTwo: some View {
        layerOne
            .sheet(isPresented: $showingSheet) {
                if let res = activeSheetResult {
                    ScanResultSheet(result: res, isLink: true)
                }
            }
            .confirmationDialog(
                "Submit for scan?",
                isPresented: $showSubmitConfirm,
                titleVisibility: .visible
            ) {
                Button("Submit") {
                    runSubmit()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(CheckUiText.sendNote([.virusTotal]))
            }
    }

    var body: some View {
        if !isHidden {
            layerTwo
        }
    }
}

import SwiftUI
import UIKit

struct ReportSheet: View {
    var defaultArea: ReportArea = .other
    var pageUrl: String? = nil

    @EnvironmentObject var store: WikiStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedArea: ReportArea = .other
    @State private var whatWentWrong: String = ""
    @State private var includeTechnical: Bool = true
    @State private var includePageUrl: Bool = false
    @State private var copiedNotice: Bool = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var osVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    private var deviceModel: String {
        UIDevice.current.model
    }

    private var wikiLastUpdatedString: String {
        if let date = store.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return "Bundled wiki"
    }

    private var technicalInfo: TechnicalInfo {
        TechnicalInfo(
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: deviceModel,
            wikiLastUpdated: wikiLastUpdatedString
        )
    }

    private var draft: ReportDraft {
        ReportDraft(
            area: selectedArea,
            whatWentWrong: whatWentWrong,
            includeTechnical: includeTechnical,
            includePageUrl: includePageUrl,
            pageUrl: pageUrl,
            technical: technicalInfo
        )
    }

    private var previewText: String {
        IssueUrlBuilder.buildBody(draft: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                areaSection
                whatWentWrongSection
                optionsSection
                previewSection
                actionsSection
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedArea = defaultArea
                if pageUrl != nil {
                    includePageUrl = true
                }
            }
        }
    }

    // MARK: - Sections

    private var areaSection: some View {
        SwiftUI.Section("Problem Area") {
            Picker("Area", selection: $selectedArea) {
                ForEach(ReportArea.allCases) { area in
                    Text(area.label).tag(area)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var whatWentWrongSection: some View {
        SwiftUI.Section {
            TextEditor(text: $whatWentWrong)
                .frame(minHeight: 90)
        } header: {
            Text("What went wrong?")
        } footer: {
            Text("\(whatWentWrong.count)/1000")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var optionsSection: some View {
        SwiftUI.Section("Details") {
            Toggle("Include technical details", isOn: $includeTechnical)

            if pageUrl != nil {
                Toggle("Include web address", isOn: $includePageUrl)
            }
        }
    }

    private var previewSection: some View {
        SwiftUI.Section("Preview") {
            Text(previewText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var actionsSection: some View {
        SwiftUI.Section {
            Button {
                handleOpenGitHub()
            } label: {
                Label("Open GitHub issue", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                handleCopy()
            } label: {
                Label(copiedNotice ? "Copied to clipboard!" : "Copy report", systemImage: copiedNotice ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func handleOpenGitHub() {
        let issueLink = IssueUrlBuilder.build(draft: draft)
        if issueLink.truncated {
            UIPasteboard.general.string = previewText
        }
        if let url = URL(string: issueLink.url) {
            UIApplication.shared.open(url)
        }
        dismiss()
    }

    private func handleCopy() {
        UIPasteboard.general.string = previewText
        copiedNotice = true
    }
}

import SwiftUI

struct EditHomeView: View {
    @EnvironmentObject var layoutStore: HomeLayoutStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var isDefault: Bool {
        layoutStore.layout == HomeLayout.default
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    Text("Drag the handle to reorder. Toggle to show or hide a block.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fmhyRowBackground()

                    ForEach(layoutStore.layout.entries, id: \.block) { entry in
                        EditHomeRow(
                            entry: entry,
                            onToggle: { enabled in
                                layoutStore.set(layoutStore.layout.withEnabled(entry.block, on: enabled))
                            }
                        )
                        .fmhyRowBackground()
                    }
                    .onMove { indices, newOffset in
                        layoutStore.set(layoutStore.layout.move(fromOffsets: indices, toOffset: newOffset))
                    }
                }

                SwiftUI.Section {
                    Button("Reset to default") {
                        layoutStore.set(layoutStore.layout.reset())
                    }
                    .foregroundStyle(isDefault ? Color.secondary : settings.accent.color)
                    .disabled(isDefault)
                    .fmhyRowBackground()
                }
            }
            .listStyle(.insetGrouped)
            .fmhyListStyle()
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
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

struct EditHomeRow: View {
    let entry: HomeLayoutEntry
    let onToggle: (Bool) -> Void
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.block.symbol)
                .font(.title3)
                .foregroundStyle(entry.enabled ? settings.accent.color : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.block.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(entry.enabled ? Color.primary : Color.secondary)
                Text(entry.block.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

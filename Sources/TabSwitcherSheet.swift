import SwiftUI

struct TabSwitcherSheet: View {
    @EnvironmentObject var tabs: TabManager
    @Environment(\.dismiss) private var dismiss
    @State private var showCloseAllConfirm = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if tabs.tabs.isEmpty {
                    ContentUnavailableView(
                        "No Open Tabs",
                        systemImage: "square.on.square",
                        description: Text("Tap '+' to open a new tab")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tabs.tabs) { tab in
                            tabCard(tab)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tabs (\(tabs.tabs.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        showCloseAllConfirm = true
                    } label: {
                        Text("Close All")
                    }
                    .disabled(tabs.tabs.isEmpty)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            _ = tabs.newTab(isPrivate: true, select: true)
                            dismiss()
                        } label: {
                            Label("New private tab", systemImage: "shield")
                        }
                        .accessibilityLabel("New private tab")

                        Button {
                            _ = tabs.newTab(isPrivate: false, select: true)
                            dismiss()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New tab")

                        Button("Done") {
                            dismiss()
                        }
                        .font(.headline)
                    }
                }
            }
            .confirmationDialog("Close all tabs?", isPresented: $showCloseAllConfirm, titleVisibility: .visible) {
                Button("Close All Tabs", role: .destructive) {
                    for tab in tabs.tabs {
                        tabs.close(tab)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func tabCard(_ tab: BrowserTab) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                tabs.select(tab)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if tab.isPrivate {
                            Text("Private")
                                .font(.caption2.bold())
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }

                    Text(tab.title.isEmpty ? (tab.url?.hostOnly ?? "New Tab") : tab.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(tab.url?.hostOnly ?? "Blank page")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            tab.id == tabs.selectedId ? fmhyPurple : Color(.separator).opacity(0.4),
                            lineWidth: tab.id == tabs.selectedId ? 2 : 1
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                tabs.close(tab)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Close tab")
        }
    }
}

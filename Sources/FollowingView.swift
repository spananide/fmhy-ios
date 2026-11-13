import SwiftUI
import UIKit

struct FollowedSectionItem: Identifiable {
    let id: String
    let title: String
    let emoji: String
    let siteCount: Int
    let newCount: Int
    let section: WikiSection?
}

struct FollowingView: View {
    @EnvironmentObject var follows: Follows
    @EnvironmentObject var store: WikiStore
    @EnvironmentObject var changes: ChangesStore
    @EnvironmentObject var settings: AppSettings

    private var items: [FollowedSectionItem] {
        let sectionMap = Dictionary(store.sections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return follows.sectionIds.sorted().map { id in
            let sec = sectionMap[id]
            let title = sec?.title ?? id.capitalized
            let count = store.sectionCounts[id] ?? 0
            let newCnt = changes.newCount(followed: [id])
            return FollowedSectionItem(
                id: id,
                title: title,
                emoji: sectionEmoji(id),
                siteCount: count,
                newCount: newCnt,
                section: sec
            )
        }
    }

    private var hasFollowedSections: Bool {
        !items.isEmpty
    }

    private var headerCountText: String {
        let count = items.count
        return count == 1 ? "1 category" : "\(count) categories"
    }

    var body: some View {
        Group {
            if hasFollowedSections {
                populatedList
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Following")
    }

    private var populatedList: some View {
        List {
            SwiftUI.Section {
                ForEach(items) { item in
                    row(for: item)
                }
                .onDelete { indexSet in
                    deleteItems(at: indexSet)
                }
            } header: {
                Text(headerCountText)
            }

            notificationSettingsSection
        }
        .listStyle(.insetGrouped)
        .fmhyListStyle()
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(settings.accent.color)

            Text("No followed categories")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text("Tap the bell icon at the top of any category to follow it and receive notifications when new sites are added.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                openNotificationSettings()
            } label: {
                Label("Notification settings", systemImage: "gearshape")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .fmhyListStyle()
    }

    @ViewBuilder
    private func row(for item: FollowedSectionItem) -> some View {
        if let section = item.section {
            NavigationLink(destination: SectionView(section: section)) {
                rowContent(for: item)
            }
            .fmhyRowBackground()
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    unfollow(item.id)
                } label: {
                    Label("Unfollow", systemImage: "bell.slash")
                }
            }
        } else {
            rowContent(for: item)
                .fmhyRowBackground()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        unfollow(item.id)
                    } label: {
                        Label("Unfollow", systemImage: "bell.slash")
                    }
                }
        }
    }

    private func rowContent(for item: FollowedSectionItem) -> some View {
        HStack(spacing: 12) {
            Text(item.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(siteCountString(item.siteCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.newCount > 0 {
                Text("+\(item.newCount) new")
                    .font(.caption2.bold())
                    .foregroundStyle(fmhyPurple)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(fmhyPurple.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private var notificationSettingsSection: some View {
        SwiftUI.Section {
            Button {
                openNotificationSettings()
            } label: {
                HStack {
                    Label("Notification settings", systemImage: "gearshape")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .fmhyRowBackground()
        } footer: {
            Text("Followed categories are checked for new entries during background refresh.")
        }
    }

    private func siteCountString(_ count: Int) -> String {
        count == 1 ? "1 site" : "\(count) sites"
    }

    private func unfollow(_ id: String) {
        if follows.isFollowing(id) {
            follows.toggle(id)
        }
    }

    private func deleteItems(at indexSet: IndexSet) {
        for index in indexSet {
            let item = items[index]
            unfollow(item.id)
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

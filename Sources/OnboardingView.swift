import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var currentPage = 0

    private struct PageInfo {
        let symbol: String
        let title: String
        let description: String
    }

    private let pages: [PageInfo] = [
        PageInfo(
            symbol: "books.vertical",
            title: "The whole FMHY wiki, offline",
            description: "Explore the entire community-curated wiki with thousands of verified free media links anytime, without needing an internet connection."
        ),
        PageInfo(
            symbol: "magnifyingglass",
            title: "Search that forgives typos",
            description: "Fast offline search that tolerates typos. Narrow down sites easily with power filters like in:video, is:starred, or site:github.com."
        ),
        PageInfo(
            symbol: "shield.checkerboard",
            title: "Browse with a shield",
            description: "Browse safely with built-in ad and cookie blocking, desktop view switching, and real-time FMHY trust badges on every website."
        ),
        PageInfo(
            symbol: "checkmark.shield",
            title: "Check before you click",
            description: "Inspect unknown domains against the community unsafe list, and follow your favorite categories to get alerts when new sites are added."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header with Skip button
            HStack {
                Spacer()
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        settings.completeOnboarding()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(settings.accent.color)
                    .padding()
                } else {
                    Button("Skip") {}
                        .font(.subheadline.weight(.semibold))
                        .hidden()
                        .padding()
                }
            }

            // Tab view of pages
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    ScrollView {
                        VStack(spacing: 24) {
                            Spacer(minLength: 40)

                            Image(systemName: page.symbol)
                                .font(.system(size: 76))
                                .foregroundStyle(settings.accent.color)
                                .padding(.bottom, 8)

                            Text(page.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)

                            Text(page.description)
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 28)

                            Spacer(minLength: 40)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            // Footer controls
            VStack(spacing: 12) {
                if currentPage < pages.count - 1 {
                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        Text("Next")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(settings.accent.color)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Button {
                        settings.completeOnboarding()
                    } label: {
                        Text("Get started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(settings.accent.color)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .padding(.top, 12)
        }
        .background(settings.theme == .black ? Color.black : Color(.systemBackground))
        .preferredColorScheme(settings.theme.colorScheme)
        .tint(settings.accent.color)
        .dynamicTypeSize(settings.textSize.dynamicTypeSize)
    }
}

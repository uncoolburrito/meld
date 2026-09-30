import SwiftUI

// MARK: - SpotifyNavigationItem

/// Navigation destinations within the Spotify experience.
enum SpotifyNavigationItem: String, CaseIterable, Identifiable, Sendable {
    case nowPlaying = "now_playing"
    case diagnostics

    var id: String {
        self.rawValue
    }

    var displayName: String {
        switch self {
        case .nowPlaying:
            String(localized: "Now Playing")
        case .diagnostics:
            String(localized: "Diagnostics")
        }
    }

    var icon: String {
        switch self {
        case .nowPlaying:
            "play.circle.fill"
        case .diagnostics:
            "wrench.and.screwdriver"
        }
    }
}

// MARK: - SpotifySidebar

/// Sidebar navigation for the Spotify experience.
struct SpotifySidebar: View {
    @Binding var selection: SpotifyNavigationItem?
    var onReselect: ((SpotifyNavigationItem) -> Void)?
    @Environment(SourceManager.self) private var sourceManager: SourceManager?

    var body: some View {
        List {
            Section {
                self.row(for: .nowPlaying)
                self.row(for: .diagnostics)
            }
        }
        .listStyle(.sidebar)
        .compatTranslucentSidebar()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooterView()
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    }

    private func row(for item: SpotifyNavigationItem) -> some View {
        KasetSidebarRow(
            title: item.displayName,
            systemImage: item.icon,
            isSelected: self.selection == item
        ) {
            self.select(item)
        }
    }

    private func select(_ item: SpotifyNavigationItem) {
        if self.selection == item {
            self.onReselect?(item)
            HapticService.navigation()
            return
        }
        self.selection = item
        HapticService.navigation()
    }
}

import SwiftUI

// MARK: - SourceToggleView

/// A two-segment glass capsule that flips the whole app between the
/// YouTube Music and Spotify experiences.
///
/// Lives at the bottom of both sidebars, just above the profile section.
struct SourceToggleView: View {
    @Environment(\.usesLegacyMacOS15UI) private var usesLegacyMacOS15UI
    @Environment(\.appTint) private var tint
    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @Environment(SourceManager.self) private var sourceManager: SourceManager?
    @State private var settings = SettingsManager.shared

    /// Namespace for the sliding selection highlight.
    @Namespace private var segmentNamespace

    var body: some View {
        Group {
            if !self.usesLegacyMacOS15UI, #available(macOS 26.0, *) {
                self.segments
                    .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                self.segments
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
        .accessibilityIdentifier(AccessibilityID.SourceToggle.container)
        .accessibilityElement(children: .contain)
        .alert(
            String(localized: "Playback Transition Failed"),
            isPresented: Binding(
                get: { self.sourceManager?.transitionAlert != nil },
                set: {
                    if !$0 {
                        self.sourceManager?.clearTransitionAlert()
                    }
                }
            ),
            actions: {
                Button(String(localized: "OK"), role: .cancel) {
                    self.sourceManager?.clearTransitionAlert()
                }
            },
            message: {
                if let message = self.sourceManager?.transitionAlert {
                    Text(message)
                }
            }
        )
    }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(AppSource.visibleCases) { source in
                self.segment(for: source)
            }
        }
        .padding(3)
    }

    private func segment(for source: AppSource) -> some View {
        let isSelected = (self.sourceManager?.selectedTab ?? self.settings.appSource) == source
        let isSpotifyPlayingExternally = source == .spotify && (self.sourceManager?.spotifyPlayingExternallyCue ?? false)

        return Button {
            self.select(source)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: source.icon)
                    .font(.system(size: 10, weight: .semibold))

                Text(source.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                if isSpotifyPlayingExternally {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                        .shadow(color: .green.opacity(0.6), radius: 2)
                        .help(String(localized: "Spotify is playing in the background"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        .background {
            if isSelected {
                Capsule()
                    .fill(self.tint)
                    .matchedGeometryEffect(id: "selectedSegment", in: self.segmentNamespace)
            }
        }
        .accessibilityIdentifier(AccessibilityID.SourceToggle.segment(for: source))
        .accessibilityLabel(source.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(source.displayName)
    }

    private func select(_ source: AppSource) {
        if let sourceManager = self.sourceManager {
            guard sourceManager.selectedTab != source else { return }
            Task {
                let success = await sourceManager.requestTransition(to: source)
                if success {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.settings.appSource = source
                    }
                    HapticService.navigation()
                    DiagnosticsLogger.ui.info("Source toggled to \(source.rawValue)")
                }
            }
        } else {
            guard self.settings.appSource != source else { return }
            if source == .music {
                self.youtubePlayer.prepareForSourceSwitch()
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.settings.appSource = source
            }
            HapticService.navigation()
            DiagnosticsLogger.ui.info("Source toggled to \(source.rawValue)")
        }
    }
}

// MARK: - AccessibilityID.SourceToggle

extension AccessibilityID {
    enum SourceToggle {
        static let container = "sidebar.sourceToggle"

        static func segment(for source: AppSource) -> String {
            "sidebar.sourceToggle.\(source.rawValue)"
        }
    }
}

// MARK: - Preview

#Preview {
    SourceToggleView()
        .frame(width: 220)
        .padding()
}

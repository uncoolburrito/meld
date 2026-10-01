import SwiftUI

// MARK: - SpotifyContentView

/// Main content container for the Spotify experience in Meld.
struct SpotifyContentView: View {
    let selection: SpotifyNavigationItem?
    @Environment(SourceManager.self) private var sourceManager: SourceManager?
    @Environment(\.appTint) private var tint

    var body: some View {
        Group {
            if let spotify = self.sourceManager?.spotifySource, !spotify.isInstalled {
                self.notInstalledView
            } else {
                switch self.selection ?? .nowPlaying {
                case .nowPlaying:
                    self.nowPlayingView
                #if DEBUG
                    case .diagnostics:
                        if let spotify = self.sourceManager?.spotifySource {
                            SpotifyDebugView(spotifySource: spotify)
                        } else {
                            ContentUnavailableView(
                                String(localized: "Spotify Unavailable"),
                                systemImage: "waveform",
                                description: Text(String(localized: "Spotify source is not initialized."))
                            )
                        }
                #endif
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notInstalledView: some View {
        ContentUnavailableView {
            Label(String(localized: "Spotify Not Installed"), systemImage: "arrow.down.app")
        } description: {
            Text(String(localized: "Meld controls Spotify via AppleScript, but Spotify.app was not found in your Applications folder."))
        } actions: {
            if let url = URL(string: "https://www.spotify.com/download") {
                Link(String(localized: "Download Spotify"), destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var nowPlayingView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 28) {
                    if let track = self.sourceManager?.spotifySource.currentTrack {
                        VStack(spacing: 20) {
                            if let artworkURL = track.artworkURL {
                                AsyncImage(url: artworkURL) { image in
                                    image
                                        .resizable()
                                        .scaledToFit()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.quaternary)
                                        .overlay {
                                            Image(systemName: "music.note")
                                                .font(.system(size: 48))
                                                .foregroundStyle(.secondary)
                                        }
                                }
                                .frame(width: 280, height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.quaternary)
                                    .frame(width: 280, height: 280)
                                    .overlay {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 48))
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            VStack(spacing: 6) {
                                Text(track.title)
                                    .font(.title2.weight(.bold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)

                                Text(track.artist)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if let album = track.album, !album.isEmpty {
                                    Text(album)
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.top, 40)
                    } else {
                        ContentUnavailableView(
                            String(localized: "No Track Playing"),
                            systemImage: "music.note",
                            description: Text(String(localized: "Start playback in Spotify or use the controls below."))
                        )
                        .padding(.top, 80)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 100)
            }

            PlayerBar()
        }
    }
}

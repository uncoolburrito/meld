import Foundation
import Observation

// MARK: - PlaybackArbiter

/// Ensures exactly one audio source plays at a time and coordinates
/// transitions between internal playback (YouTube Music, YouTube Video)
/// and external desktop playback (Spotify).
///
/// Manages both `audioSource` (which engine is producing sound) and `selectedTab`
/// (which surface is visible in the UI), supporting Path A (passive external detection)
/// and Path B (explicit user toggle transitions with asymmetric timeout).
@MainActor
@Observable
final class PlaybackArbiter {
    /// The source actively producing audio.
    private(set) var audioSource: AppSource = .music

    /// The surface currently displayed in the main window.
    private(set) var selectedTab: AppSource = SettingsManager.shared.appSource

    /// Backwards-compatible alias for the active audio source.
    var activeSource: AppSource {
        self.audioSource
    }

    /// Whether Spotify is playing audio externally while the user is viewing another tab.
    var spotifyPlayingExternallyCue: Bool {
        self.audioSource == .spotify && self.selectedTab != .spotify
    }

    /// True while an asynchronous source transition is executing.
    private(set) var isTransitioning = false

    /// User-facing message if a source transition was aborted.
    var transitionAlert: String?

    private let playerService: PlayerService
    private let youtubePlayerService: YouTubePlayerService
    private weak var spotifySource: SpotifySource?
    private let logger = DiagnosticsLogger.player

    init(
        playerService: PlayerService,
        youtubePlayerService: YouTubePlayerService,
        spotifySource: SpotifySource? = nil
    ) {
        self.playerService = playerService
        self.youtubePlayerService = youtubePlayerService
        self.spotifySource = spotifySource

        youtubePlayerService.playbackWillStart = { [weak self] in
            self?.videoWillStartPlaying()
        }

        if let spotifySource {
            self.attachSpotifySource(spotifySource)
        }
    }

    /// Attaches the Spotify playback engine and listens for external playback events.
    func attachSpotifySource(_ spotifySource: SpotifySource) {
        self.spotifySource = spotifySource
        spotifySource.onPlaybackStarted = { [weak self] in
            self?.handleExternalSpotifyPlaybackDetected()
        }
    }

    /// Clears any presented transition error alert.
    func clearTransitionAlert() {
        self.transitionAlert = nil
    }

    /// Updates the selected tab without altering playback state.
    func setSelectedTab(_ tab: AppSource) {
        self.selectedTab = tab
        SettingsManager.shared.appSource = tab
    }

    // MARK: - Path A: External Playback Detection

    /// Called when Spotify begins playing externally without user interaction in Meld.
    ///
    /// Hands over audio ownership, suppresses WebKit dual sessions, releases Now Playing,
    /// and gates AI features without disrupting the user's current navigation tab.
    func handleExternalSpotifyPlaybackDetected() {
        guard self.audioSource != .spotify else { return }
        self.logger.info("Arbiter (Path A): external Spotify playback detected; pausing internal audio")

        self.audioSource = .spotify
        self.syncFoundationModelsAudioSource(.spotify)

        // Pause internal players
        Task {
            await self.playerService.pause()
        }
        SingletonPlayerWebView.shared.suppressPlayback()
        self.youtubePlayerService.pause()

        // Release system Now Playing ownership so Spotify native app handles media keys
        NowPlayingManager.shared.handleAudioSourceChanged(to: .spotify)
    }

    // MARK: - Path B: Toggle-Driven Transition (Asymmetric Timeout)

    /// Requests a transition to the target source.
    ///
    /// Implements asymmetric timeout:
    /// - Outgoing YTM/Video: pauses cooperatively, then force-pauses via WebKit suppression if needed.
    /// - Outgoing Spotify: requests pause via AppleScript; if Spotify fails to pause after retry and timeout,
    ///   aborts transition and alerts the user rather than allowing dual-audio chaos.
    func requestTransition(to targetSource: AppSource) async -> Bool {
        guard !self.isTransitioning else { return false }
        self.isTransitioning = true
        defer { self.isTransitioning = false }
        self.transitionAlert = nil

        if targetSource == self.audioSource {
            self.setSelectedTab(targetSource)
            return true
        }

        switch targetSource {
        case .spotify:
            return await self.transitionToSpotify()
        case .music:
            return await self.transitionToMusic()
        case .video:
            return await self.transitionToVideo()
        }
    }

    private func transitionToSpotify() async -> Bool {
        self.logger.info("Arbiter (Path B): transitioning to Spotify")

        // 1. Cooperative pause of internal engines
        await self.playerService.pause()
        self.youtubePlayerService.pause()

        // 2. Wait up to 300ms for confirmation; retry once if still playing
        if self.playerService.isPlaying {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if self.playerService.isPlaying {
                await self.playerService.pause()
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        // 3. Asymmetric fallback: force-pause WebKit to suppress dual-session card
        SingletonPlayerWebView.shared.suppressPlayback()

        // 4. Now Playing handoff and Terms v10 AI gate
        NowPlayingManager.shared.handleAudioSourceChanged(to: .spotify)
        self.syncFoundationModelsAudioSource(.spotify)

        self.audioSource = .spotify
        self.setSelectedTab(.spotify)
        return true
    }

    private func transitionToMusic() async -> Bool {
        self.logger.info("Arbiter (Path B): transitioning to Music")

        // 1. If currently on Spotify, pause Spotify with bounded timeout
        if self.audioSource == .spotify, let spotify = self.spotifySource {
            do {
                try await spotify.pause()
            } catch {
                self.logger.warning("Arbiter: error requesting Spotify pause: \(error.localizedDescription)")
            }

            // Bounded wait (up to 500ms)
            var spotifyPaused = spotify.transportState != .playing
            if !spotifyPaused {
                try? await Task.sleep(nanoseconds: 200_000_000)
                spotifyPaused = spotify.transportState != .playing
                if !spotifyPaused {
                    try? await spotify.pause()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    spotifyPaused = spotify.transportState != .playing
                }
            }

            // Asymmetric rule: abort if Spotify failed to pause!
            if !spotifyPaused {
                self.logger.error("Arbiter (Path B): Spotify pause timed out; aborting transition to Music")
                self.transitionAlert = String(localized: "Could not pause Spotify. Please pause Spotify manually to switch sources.")
                return false
            }
        }

        // 2. Spotify paused successfully — lift WebKit suppression and reclaim Now Playing
        SingletonPlayerWebView.shared.unsuppressPlayback()
        NowPlayingManager.shared.handleAudioSourceChanged(to: .music)
        self.syncFoundationModelsAudioSource(.music)

        self.audioSource = .music
        self.setSelectedTab(.music)
        return true
    }

    private func transitionToVideo() async -> Bool {
        self.logger.info("Arbiter (Path B): transitioning to Video")

        if self.audioSource == .spotify, let spotify = self.spotifySource {
            do {
                try await spotify.pause()
            } catch {
                self.logger.warning("Arbiter: error requesting Spotify pause: \(error.localizedDescription)")
            }

            var spotifyPaused = spotify.transportState != .playing
            if !spotifyPaused {
                try? await Task.sleep(nanoseconds: 200_000_000)
                spotifyPaused = spotify.transportState != .playing
                if !spotifyPaused {
                    try? await spotify.pause()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    spotifyPaused = spotify.transportState != .playing
                }
            }

            if !spotifyPaused {
                self.logger.error("Arbiter (Path B): Spotify pause timed out; aborting transition to Video")
                self.transitionAlert = String(localized: "Could not pause Spotify. Please pause Spotify manually to switch sources.")
                return false
            }
        } else {
            await self.playerService.pause()
            SingletonPlayerWebView.shared.suppressPlayback()
        }

        NowPlayingManager.shared.handleAudioSourceChanged(to: .video)
        self.syncFoundationModelsAudioSource(.video)

        self.audioSource = .video
        self.setSelectedTab(.video)
        return true
    }

    // MARK: - Internal Player Notifications

    /// Video playback is about to start — pause music and Spotify.
    func videoWillStartPlaying() {
        self.audioSource = .video
        self.syncFoundationModelsAudioSource(.video)
        NowPlayingManager.shared.handleAudioSourceChanged(to: .video)

        let intent = self.playerService.beginMusicPlaybackIntent()
        let hasActiveOrPendingMusic = self.playerService.isPlaying
            || self.playerService.state == .loading
            || self.playerService.isAwaitingPlaybackConfirmation
            || self.playerService.pendingPlayVideoId != nil
        if hasActiveOrPendingMusic {
            self.logger.info("Arbiter: pausing music for video playback")
            Task {
                await self.playerService.pause(intent: intent)
            }
        }

        if let spotify = self.spotifySource, spotify.transportState == .playing {
            Task {
                try? await spotify.pause()
            }
        }
    }

    /// Music playback started — pause video and Spotify.
    func musicDidStartPlaying() {
        guard self.audioSource != .music else { return }
        self.audioSource = .music
        self.syncFoundationModelsAudioSource(.music)
        NowPlayingManager.shared.handleAudioSourceChanged(to: .music)

        if self.youtubePlayerService.isPlaying {
            self.logger.info("Arbiter: pausing video for music playback")
            self.youtubePlayerService.pause()
        }

        if let spotify = self.spotifySource, spotify.transportState == .playing {
            self.logger.info("Arbiter: pausing Spotify for music playback")
            Task {
                try? await spotify.pause()
            }
        }
    }

    /// Whether media keys should currently control the YouTube video player.
    var routesMediaKeysToVideo: Bool {
        self.audioSource == .video && self.youtubePlayerService.currentVideo != nil
    }

    private func syncFoundationModelsAudioSource(_ source: AppSource) {
        if #available(macOS 26.0, *) {
            FoundationModelsService.shared.currentAudioSource = source
        }
    }
}

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
    var selectedTab: AppSource {
        SettingsManager.shared.appSource
    }

    /// Backwards-compatible alias for the active audio source.
    var activeSource: AppSource {
        self.audioSource
    }

    /// Whether a source is actively playing while not being the currently selected tab.
    func isPlayingInBackground(_ source: AppSource) -> Bool {
        self.selectedTab != source && self.isSourcePlaying(source)
    }

    /// Whether Spotify is playing audio externally while the user is viewing another tab.
    var spotifyPlayingExternallyCue: Bool {
        self.isPlayingInBackground(.spotify)
    }

    /// True while an asynchronous source transition is executing.
    private(set) var isTransitioning = false

    /// User-facing message if a source transition was aborted.
    var transitionAlert: String?

    /// Tracks sources that were actively playing when interrupted by a user toggle (in-memory only).
    private var interruptedByToggleSources: Set<AppSource> = []

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

        playerService.onPlaybackStarted = { [weak self] in
            self?.handlePlaybackStarted(on: .music)
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

    /// Clears all interrupted-by-toggle marks (e.g. on settings change).
    func clearInterruptedMarks() {
        self.interruptedByToggleSources.removeAll()
    }

    /// Clears the interrupted-by-toggle mark for a specific source (e.g. on manual play/pause/track change).
    func clearInterruptedMark(for source: AppSource) {
        self.interruptedByToggleSources.remove(source)
    }

    /// Whether a source was playing when last interrupted by a toggle switch.
    func isInterruptedByToggle(_ source: AppSource) -> Bool {
        self.interruptedByToggleSources.contains(source)
    }

    /// Tests whether a source is currently actively producing audio.
    func isSourcePlaying(_ source: AppSource) -> Bool {
        switch source {
        case .music:
            self.playerService.isPlaying
        case .spotify:
            self.spotifySource?.transportState == .playing
        case .video:
            self.youtubePlayerService.isPlaying
        }
    }

    /// Updates the selected tab without altering playback state.
    func setSelectedTab(_ tab: AppSource) {
        SettingsManager.shared.appSource = tab
    }

    // MARK: - Playback Handoff (Audible Ownership)

    /// Unified handoff called whenever any audio source begins producing playback.
    ///
    /// Hands over audio ownership, coordinates pause of outgoing audio, updates Now Playing,
    /// and updates AI/EQ gates without modifying the user's selected tab.
    func handlePlaybackStarted(on source: AppSource) {
        guard self.audioSource != source else { return }
        self.logger.info("Arbiter: playback started on \(source.rawValue); handing over audio ownership")

        let outgoingSource = self.audioSource
        self.audioSource = source
        self.syncFoundationModelsAudioSource(source)

        switch source {
        case .spotify:
            NowPlayingManager.shared.handleAudioSourceChanged(to: .spotify)
            Task {
                await self.playerService.pause()
            }
            SingletonPlayerWebView.shared.suppressPlayback()
            self.youtubePlayerService.pause()

        case .music:
            SingletonPlayerWebView.shared.unsuppressPlayback()
            NowPlayingManager.shared.handleAudioSourceChanged(to: .music)
            if outgoingSource == .spotify, let spotify = self.spotifySource {
                Task {
                    do {
                        try await spotify.pause()
                    } catch {
                        self.logger.warning("Arbiter: error requesting Spotify pause on handoff: \(error.localizedDescription)")
                    }
                    var paused = await spotify.confirmPaused()
                    if !paused {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        paused = await spotify.confirmPaused()
                        if !paused {
                            try? await spotify.pause()
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            paused = await spotify.confirmPaused()
                        }
                    }
                    if !paused {
                        self.logger.warning("Arbiter: Spotify pause timed out; presenting non-blocking alert")
                        self.transitionAlert = String(localized: "Could not pause Spotify. Please pause Spotify manually to switch sources.")
                    }
                }
            }
            self.youtubePlayerService.pause()

        case .video:
            NowPlayingManager.shared.handleAudioSourceChanged(to: .video)
            Task {
                await self.playerService.pause()
            }
            SingletonPlayerWebView.shared.suppressPlayback()
            if outgoingSource == .spotify, let spotify = self.spotifySource {
                Task {
                    try? await spotify.pause()
                }
            }
        }
    }

    /// Backwards compatibility for Path A external Spotify playback detection.
    func handleExternalSpotifyPlaybackDetected() {
        self.handlePlaybackStarted(on: .spotify)
    }

    // MARK: - Path B: Toggle-Driven Transition (Asymmetric Timeout)

    /// Duration of each step in the crossfade animation (5 steps total ≈ 250ms).
    var fadeStepDuration: TimeInterval = 0.050

    /// Requests a transition to the target source.
    func requestTransition(to targetSource: AppSource) async -> Bool {
        // If leaving a docked video, pause it in place
        if self.selectedTab == .video || self.audioSource == .video, targetSource != .video {
            self.youtubePlayerService.prepareForSourceSwitch()
        }

        // Keep playing mode (default): instant view switch without pausing or fading audio
        if SettingsManager.shared.sourceSwitchBehavior == .keepPlaying {
            self.setSelectedTab(targetSource)
            return true
        }

        guard !self.isTransitioning else { return false }
        self.isTransitioning = true
        defer { self.isTransitioning = false }
        self.transitionAlert = nil

        if targetSource == self.audioSource {
            self.setSelectedTab(targetSource)
            return true
        }

        let outgoingSource = self.audioSource
        let outgoingWasPlaying = self.isSourcePlaying(outgoingSource)
        let outgoingOriginalVolume = self.originalVolume(for: outgoingSource)

        // 1. If outgoing source was playing, fade out to 0 over ~250ms
        if outgoingWasPlaying {
            await self.fadeOutSource(outgoingSource, originalVolume: outgoingOriginalVolume)
        }

        let success = await self.performTransition(to: targetSource)

        // 2. Immediately restore outgoing source's original volume (so next resume is not silent)
        await self.restoreOriginalVolume(outgoingOriginalVolume, for: outgoingSource)

        guard success else { return false }

        // 3. Resume mode: auto-resume if target was previously interrupted by a toggle
        await self.handleResumePostTransition(
            targetSource: targetSource,
            outgoingSource: outgoingSource,
            outgoingWasPlaying: outgoingWasPlaying
        )

        return true
    }

    private func originalVolume(for source: AppSource) -> Double {
        switch source {
        case .music:
            self.playerService.volume
        case .spotify:
            self.spotifySource?.beginVolumeFade() ?? 1.0
        case .video:
            self.youtubePlayerService.volume
        }
    }

    private func performTransition(to targetSource: AppSource) async -> Bool {
        switch targetSource {
        case .spotify:
            await self.transitionToSpotify()
        case .music:
            await self.transitionToMusic()
        case .video:
            await self.transitionToVideo()
        }
    }

    private func handleResumePostTransition(
        targetSource: AppSource,
        outgoingSource: AppSource,
        outgoingWasPlaying: Bool
    ) async {
        guard SettingsManager.shared.sourceSwitchBehavior == .resume else { return }

        if outgoingWasPlaying {
            self.interruptedByToggleSources.insert(outgoingSource)
            self.logger.info("Arbiter: marked \(outgoingSource.rawValue) as interrupted by toggle")
        }
        if self.interruptedByToggleSources.remove(targetSource) != nil {
            self.logger.info("Arbiter: resuming \(targetSource.rawValue) interrupted by earlier toggle")
            let incomingTargetVolume = self.originalVolume(for: targetSource)

            // Start incoming at 0 volume, resume, and fade in over ~250ms
            await self.applyTransientVolume(0.0, for: targetSource)
            await self.resumeSource(targetSource)
            await self.fadeInSource(targetSource, targetVolume: incomingTargetVolume)

            if targetSource == .spotify {
                await self.spotifySource?.endVolumeFade(restoring: incomingTargetVolume)
            }
        }
    }

    private func fadeOutSource(_ source: AppSource, originalVolume: Double) async {
        guard originalVolume > 0 else { return }
        let steps = 5
        let stepSeconds = self.fadeStepDuration
        for step in (0 ..< steps).reversed() {
            let volume = (Double(step) / Double(steps)) * originalVolume
            await self.applyTransientVolume(volume, for: source)
            try? await Task.sleep(nanoseconds: UInt64(stepSeconds * 1_000_000_000))
        }
        await self.applyTransientVolume(0.0, for: source)
    }

    private func fadeInSource(_ source: AppSource, targetVolume: Double) async {
        guard targetVolume > 0 else { return }
        let steps = 5
        let stepSeconds = self.fadeStepDuration
        await self.applyTransientVolume(0.0, for: source)
        for step in 1 ... steps {
            try? await Task.sleep(nanoseconds: UInt64(stepSeconds * 1_000_000_000))
            let volume = (Double(step) / Double(steps)) * targetVolume
            await self.applyTransientVolume(volume, for: source)
        }
        await self.applyTransientVolume(targetVolume, for: source)
    }

    private func applyTransientVolume(_ volume: Double, for source: AppSource) async {
        switch source {
        case .music:
            SingletonPlayerWebView.shared.setVolume(volume)
        case .spotify:
            if let spotify = self.spotifySource {
                await spotify.stepFadeVolume(volume)
            }
        case .video:
            self.youtubePlayerService.volume = volume
        }
    }

    private func restoreOriginalVolume(_ volume: Double, for source: AppSource) async {
        switch source {
        case .music:
            SingletonPlayerWebView.shared.setVolume(volume)
        case .spotify:
            if let spotify = self.spotifySource {
                await spotify.endVolumeFade(restoring: volume)
            }
        case .video:
            self.youtubePlayerService.volume = volume
        }
    }

    private func resumeSource(_ source: AppSource) async {
        switch source {
        case .music:
            await self.playerService.resume()
        case .spotify:
            if let spotify = self.spotifySource {
                do {
                    try await spotify.play()
                } catch {
                    self.logger.warning("Arbiter: error resuming Spotify: \(error.localizedDescription)")
                }
            }
        case .video:
            self.youtubePlayerService.resume()
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

            // Bounded wait (up to 500ms) confirming pause via fetchPlaybackSnapshot
            var spotifyPaused = await spotify.confirmPaused()
            if !spotifyPaused {
                try? await Task.sleep(nanoseconds: 200_000_000)
                spotifyPaused = await spotify.confirmPaused()
                if !spotifyPaused {
                    try? await spotify.pause()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    spotifyPaused = await spotify.confirmPaused()
                }
            }

            // Non-blocking alert rule: notify if Spotify failed to pause, without aborting user playback
            if !spotifyPaused {
                self.logger.warning("Arbiter (Path B): Spotify pause timed out; presenting non-blocking alert")
                self.transitionAlert = String(localized: "Could not pause Spotify. Please pause Spotify manually to switch sources.")
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

            var spotifyPaused = await spotify.confirmPaused()
            if !spotifyPaused {
                try? await Task.sleep(nanoseconds: 200_000_000)
                spotifyPaused = await spotify.confirmPaused()
                if !spotifyPaused {
                    try? await spotify.pause()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    spotifyPaused = await spotify.confirmPaused()
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

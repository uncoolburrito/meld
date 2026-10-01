import Foundation
import Observation

// MARK: - SourceManager

/// Central state container and view coordinator for audio sources in Meld.
///
/// Unifies `YouTubeMusicSource` and `SpotifySource` behind the `MusicSourceProtocol`
/// contract, coordinates with `PlaybackArbiter` for mutual-exclusion transitions,
/// and publishes the unified playback state consumed by `PlayerBar` and `Sidebar`.
@MainActor
@Observable
final class SourceManager {
    let youtubeMusicSource: YouTubeMusicSource
    let spotifySource: SpotifySource
    let playbackArbiter: PlaybackArbiter

    init(
        youtubeMusicSource: YouTubeMusicSource,
        spotifySource: SpotifySource,
        playbackArbiter: PlaybackArbiter
    ) {
        self.youtubeMusicSource = youtubeMusicSource
        self.spotifySource = spotifySource
        self.playbackArbiter = playbackArbiter

        // Ensure arbiter is attached to Spotify
        playbackArbiter.attachSpotifySource(spotifySource)
    }

    // MARK: - Source State Inspection

    /// The source currently producing audio.
    var audioSource: AppSource {
        self.playbackArbiter.audioSource
    }

    /// The surface currently displayed in the main window.
    var selectedTab: AppSource {
        self.playbackArbiter.selectedTab
    }

    /// Whether Spotify is playing audio externally while the user views another tab.
    var spotifyPlayingExternallyCue: Bool {
        self.playbackArbiter.spotifyPlayingExternallyCue
    }

    /// True while an asynchronous source transition is executing.
    var isTransitioning: Bool {
        self.playbackArbiter.isTransitioning
    }

    /// User-facing message if a source transition was aborted.
    var transitionAlert: String? {
        self.playbackArbiter.transitionAlert
    }

    func clearTransitionAlert() {
        self.playbackArbiter.clearTransitionAlert()
    }

    /// The engine currently driving audio output.
    var activeSource: any MusicSourceProtocol {
        if self.audioSource == .spotify {
            self.spotifySource
        } else {
            self.youtubeMusicSource
        }
    }

    // MARK: - Normalized Playback State

    var currentTrack: UnifiedTrack? {
        self.activeSource.currentTrack
    }

    var transportState: PlaybackTransportState {
        self.activeSource.transportState
    }

    var isPlaying: Bool {
        self.transportState == .playing
    }

    var playbackPosition: TimeInterval {
        self.activeSource.playbackPosition
    }

    var playbackDuration: TimeInterval {
        self.activeSource.playbackDuration
    }

    var volume: Double {
        self.activeSource.volume
    }

    // MARK: - Transport Commands

    func play() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audioSource)
        try await self.activeSource.play()
    }

    func pause() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audioSource)
        try await self.activeSource.pause()
    }

    func toggle() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audioSource)
        try await self.activeSource.toggle()
    }

    func next() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audioSource)
        try await self.activeSource.next()
    }

    func previous() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audioSource)
        try await self.activeSource.previous()
    }

    func seek(to position: TimeInterval) async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audioSource)
        try await self.activeSource.seek(to: position)
    }

    func setVolume(_ volume: Double) async throws {
        let clampedVolume = max(0.0, min(1.0, volume))
        try await self.activeSource.setVolume(clampedVolume)
    }

    // MARK: - Transitions

    /// Requests switching the UI and audio engine to the target source.
    func requestTransition(to targetSource: AppSource) async -> Bool {
        await self.playbackArbiter.requestTransition(to: targetSource)
    }
}

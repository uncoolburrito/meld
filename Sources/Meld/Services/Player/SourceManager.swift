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

    /// The source currently producing audible output (governs media keys, AI/EQ gates, and Now Playing).
    var audibleSource: AppSource {
        self.playbackArbiter.audioSource
    }

    /// Backwards compatibility alias for audibleSource.
    var audioSource: AppSource {
        self.audibleSource
    }

    /// The surface currently displayed in the main window (governs PlayerBar and tab view).
    var selectedTab: AppSource {
        self.playbackArbiter.selectedTab
    }

    /// The type of source corresponding to the currently selected tab.
    var selectedSourceType: AppSource {
        self.selectedTab
    }

    /// Whether a source is actively playing while not being the selected tab.
    func isPlayingInBackground(_ source: AppSource) -> Bool {
        self.playbackArbiter.isPlayingInBackground(source)
    }

    /// Whether Spotify is playing audio externally while the user views another tab.
    var spotifyPlayingExternallyCue: Bool {
        self.isPlayingInBackground(.spotify)
    }

    /// Tests whether a source is currently actively producing audio.
    func isSourcePlaying(_ source: AppSource) -> Bool {
        self.playbackArbiter.isSourcePlaying(source)
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
        self.audibleEngine
    }

    /// The engine currently driving audio output.
    var audibleEngine: any MusicSourceProtocol {
        if self.audibleSource == .spotify {
            self.spotifySource
        } else {
            self.youtubeMusicSource
        }
    }

    /// The engine corresponding to the selected tab (drives PlayerBar).
    var selectedSource: any MusicSourceProtocol {
        if self.selectedSourceType == .spotify {
            self.spotifySource
        } else {
            self.youtubeMusicSource
        }
    }

    // MARK: - Selected Tab Playback State (Consumed by PlayerBar)

    var selectedTrack: UnifiedTrack? {
        self.selectedSource.currentTrack
    }

    var selectedTransportState: PlaybackTransportState {
        self.selectedSource.transportState
    }

    var isSelectedPlaying: Bool {
        self.selectedTransportState == .playing
    }

    var selectedPosition: TimeInterval {
        self.selectedSource.playbackPosition
    }

    var selectedDuration: TimeInterval {
        self.selectedSource.playbackDuration
    }

    var selectedVolume: Double {
        self.selectedSource.volume
    }

    // MARK: - Selected Tab Transport Commands (Consumed by PlayerBar)

    func playSelected() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.selectedSourceType)
        try await self.selectedSource.play()
    }

    func pauseSelected() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.selectedSourceType)
        try await self.selectedSource.pause()
    }

    func toggleSelected() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.selectedSourceType)
        try await self.selectedSource.toggle()
    }

    func nextSelected() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.selectedSourceType)
        try await self.selectedSource.next()
    }

    func previousSelected() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.selectedSourceType)
        try await self.selectedSource.previous()
    }

    func seekSelected(to position: TimeInterval) async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.selectedSourceType)
        try await self.selectedSource.seek(to: position)
    }

    func setSelectedVolume(_ volume: Double) async throws {
        let clampedVolume = max(0.0, min(1.0, volume))
        try await self.selectedSource.setVolume(clampedVolume)
    }

    // MARK: - Normalized Audible Playback State

    var currentTrack: UnifiedTrack? {
        self.audibleEngine.currentTrack
    }

    var transportState: PlaybackTransportState {
        self.audibleEngine.transportState
    }

    var isPlaying: Bool {
        self.transportState == .playing
    }

    var playbackPosition: TimeInterval {
        self.audibleEngine.playbackPosition
    }

    var playbackDuration: TimeInterval {
        self.audibleEngine.playbackDuration
    }

    var volume: Double {
        self.audibleEngine.volume
    }

    // MARK: - Audible Transport Commands

    func play() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audibleSource)
        try await self.audibleEngine.play()
    }

    func pause() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audibleSource)
        try await self.audibleEngine.pause()
    }

    func toggle() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audibleSource)
        try await self.audibleEngine.toggle()
    }

    func next() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audibleSource)
        try await self.audibleEngine.next()
    }

    func previous() async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audibleSource)
        try await self.audibleEngine.previous()
    }

    func seek(to position: TimeInterval) async throws {
        self.playbackArbiter.clearInterruptedMark(for: self.audibleSource)
        try await self.audibleEngine.seek(to: position)
    }

    func setVolume(_ volume: Double) async throws {
        let clampedVolume = max(0.0, min(1.0, volume))
        try await self.audibleEngine.setVolume(clampedVolume)
    }

    // MARK: - Transitions

    /// Requests switching the UI and audio engine to the target source.
    func requestTransition(to targetSource: AppSource) async -> Bool {
        await self.playbackArbiter.requestTransition(to: targetSource)
    }
}

import Foundation

// MARK: - PlaybackTransportState

/// Transport and playback state representation for any audio source.
enum PlaybackTransportState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case error(String)
}

// MARK: - MusicSourceProtocol

/// Unified contract implemented by all audio playback engines in Meld.
///
/// Conforming types provide asynchronous transport control, state inspection,
/// and track metadata publishing under `@MainActor` isolation.
@MainActor
protocol MusicSourceProtocol: AnyObject {
    /// The unique source identity.
    var source: AppSource { get }

    /// The currently loaded or playing track, normalized across sources.
    var currentTrack: UnifiedTrack? { get }

    /// Current playback position in seconds.
    var playbackPosition: TimeInterval { get }

    /// Total duration of the current item in seconds.
    var playbackDuration: TimeInterval { get }

    /// Current transport state (playing, paused, loading, idle).
    var transportState: PlaybackTransportState { get }

    /// Current output volume from 0.0 to 1.0.
    var volume: Double { get }

    /// Starts or resumes playback.
    func play() async throws

    /// Pauses playback.
    func pause() async throws

    /// Toggles between play and pause.
    func toggle() async throws

    /// Advances to the next track.
    func next() async throws

    /// Returns to the previous track or restarts the current track.
    func previous() async throws

    /// Seeks to an explicit position in seconds.
    func seek(to position: TimeInterval) async throws

    /// Sets playback volume (0.0 to 1.0).
    func setVolume(_ volume: Double) async throws
}

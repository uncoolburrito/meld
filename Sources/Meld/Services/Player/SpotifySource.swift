import Foundation

/// Compiling stub conformance for Spotify playback.
///
/// Full AppleScript execution, notification monitoring, and state sync
/// will be implemented in Phase 2.
@MainActor
final class SpotifySource: MusicSourceProtocol {
    let source: AppSource = .spotify

    var currentTrack: UnifiedTrack? {
        nil
    }

    var playbackPosition: TimeInterval {
        0.0
    }

    var playbackDuration: TimeInterval {
        0.0
    }

    var transportState: PlaybackTransportState {
        .idle
    }

    var volume: Double {
        1.0
    }

    func play() async throws {
        // Implemented in Phase 2
    }

    func pause() async throws {
        // Implemented in Phase 2
    }

    func toggle() async throws {
        // Implemented in Phase 2
    }

    func next() async throws {
        // Implemented in Phase 2
    }

    func previous() async throws {
        // Implemented in Phase 2
    }

    func seek(to _: TimeInterval) async throws {
        // Implemented in Phase 2
    }

    func setVolume(_: Double) async throws {
        // Implemented in Phase 2
    }
}

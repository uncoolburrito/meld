import Foundation

// MARK: - SpotifySourceError

/// Errors thrown by the Spotify playback engine.
enum SpotifySourceError: LocalizedError, Equatable {
    case unimplemented

    var errorDescription: String? {
        switch self {
        case .unimplemented:
            "Spotify playback is unimplemented in this build (stub)."
        }
    }
}

// MARK: - SpotifySource

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
        throw SpotifySourceError.unimplemented
    }

    func pause() async throws {
        throw SpotifySourceError.unimplemented
    }

    func toggle() async throws {
        throw SpotifySourceError.unimplemented
    }

    func next() async throws {
        throw SpotifySourceError.unimplemented
    }

    func previous() async throws {
        throw SpotifySourceError.unimplemented
    }

    func seek(to _: TimeInterval) async throws {
        throw SpotifySourceError.unimplemented
    }

    func setVolume(_: Double) async throws {
        throw SpotifySourceError.unimplemented
    }
}

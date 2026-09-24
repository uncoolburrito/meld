import Foundation

// MARK: - SpotifyPlayerState

/// Playback state reported by the Spotify application.
enum SpotifyPlayerState: String, Sendable, Equatable {
    case playing
    case paused
    case stopped
    case unknown

    init(rawString: String) {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "kPSP" {
            self = .playing
        } else if trimmed == "kPSp" {
            self = .paused
        } else if trimmed == "kPSS" {
            self = .stopped
        } else {
            switch trimmed.lowercased() {
            case "playing":
                self = .playing
            case "paused":
                self = .paused
            case "stopped":
                self = .stopped
            default:
                if trimmed.lowercased().contains("playing") {
                    self = .playing
                } else if trimmed.lowercased().contains("paused") {
                    self = .paused
                } else if trimmed.lowercased().contains("stopped") {
                    self = .stopped
                } else {
                    self = .unknown
                }
            }
        }
    }

    var transportState: PlaybackTransportState {
        switch self {
        case .playing:
            .playing
        case .paused:
            .paused
        case .stopped:
            .idle
        case .unknown:
            .idle
        }
    }
}

// MARK: - SpotifyPlaybackSnapshot

/// Point-in-time state of Spotify playback.
struct SpotifyPlaybackSnapshot: Sendable, Equatable {
    let playerState: SpotifyPlayerState
    let position: TimeInterval
    let duration: TimeInterval
    let volume: Double
    let track: UnifiedTrack?

    static let idle = SpotifyPlaybackSnapshot(
        playerState: .stopped,
        position: 0.0,
        duration: 0.0,
        volume: 1.0,
        track: nil
    )
}

// MARK: - SpotifySourceError

/// Errors thrown by the Spotify playback engine and script controller.
enum SpotifySourceError: LocalizedError, Equatable {
    case applicationNotFound
    case applicationNotRunning
    case scriptExecutionFailed(String)
    case commandTimeout
    case invalidPayload
    case unimplemented

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            String(localized: "Spotify is not installed on this Mac.")
        case .applicationNotRunning:
            String(localized: "Spotify is not running.")
        case let .scriptExecutionFailed(message):
            String(localized: "Spotify AppleScript error: \(message)")
        case .commandTimeout:
            String(localized: "Spotify command timed out.")
        case .invalidPayload:
            String(localized: "Received invalid notification payload from Spotify.")
        case .unimplemented:
            String(localized: "Spotify functionality is unimplemented.")
        }
    }
}

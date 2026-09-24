import Foundation

/// Adapts Meld's existing `PlayerService` into the `MusicSourceProtocol` interface.
@MainActor
final class YouTubeMusicSource: MusicSourceProtocol {
    let source: AppSource = .music

    private let playerService: PlayerService

    init(playerService: PlayerService) {
        self.playerService = playerService
    }

    var currentTrack: UnifiedTrack? {
        guard let song = self.playerService.currentTrack else { return nil }
        return UnifiedTrack(from: song)
    }

    var playbackPosition: TimeInterval {
        self.playerService.progress
    }

    var playbackDuration: TimeInterval {
        self.playerService.duration
    }

    var transportState: PlaybackTransportState {
        if self.playerService.isPlaying {
            .playing
        } else if self.playerService.state == .loading {
            .loading
        } else if self.playerService.currentTrack != nil {
            .paused
        } else {
            .idle
        }
    }

    var volume: Double {
        self.playerService.volume
    }

    func play() async throws {
        await self.playerService.resume()
    }

    func pause() async throws {
        await self.playerService.pause()
    }

    func toggle() async throws {
        await self.playerService.playPause()
    }

    func next() async throws {
        await self.playerService.next()
    }

    func previous() async throws {
        await self.playerService.previous()
    }

    func seek(to position: TimeInterval) async throws {
        await self.playerService.seek(to: position)
    }

    func setVolume(_ volume: Double) async throws {
        await self.playerService.setVolume(volume)
    }
}

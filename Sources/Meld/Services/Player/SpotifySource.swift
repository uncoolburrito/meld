import Foundation
import Observation

// MARK: - SpotifySource

/// Native Spotify audio playback engine for Meld.
///
/// Implements `MusicSourceProtocol` using AppleScript transport controls and
/// macOS DistributedNotificationCenter observation with echo suppression.
@MainActor
@Observable
final class SpotifySource: MusicSourceProtocol {
    let source: AppSource = .spotify

    private(set) var currentTrack: UnifiedTrack?
    private(set) var playbackPosition: TimeInterval = 0.0
    private(set) var playbackDuration: TimeInterval = 0.0
    private(set) var transportState: PlaybackTransportState = .idle
    private(set) var volume: Double = 1.0

    @ObservationIgnored
    private let scriptController: any SpotifyScriptControlling

    @ObservationIgnored
    private let notificationMonitor: any SpotifyNotificationMonitoring

    init(
        scriptController: any SpotifyScriptControlling = SpotifyScriptController.shared,
        notificationMonitor: any SpotifyNotificationMonitoring = SpotifyNotificationMonitor(),
        autoRefresh: Bool = true
    ) {
        self.scriptController = scriptController
        self.notificationMonitor = notificationMonitor

        self.setupNotificationObservation()

        if autoRefresh {
            Task { [weak self] in
                await self?.refreshState()
            }
        }
    }

    var isInstalled: Bool {
        self.scriptController.isInstalled
    }

    var isRunning: Bool {
        self.scriptController.isRunning
    }

    // MARK: - MusicSourceProtocol Verbs

    func play() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }

        if !self.isRunning {
            try await self.launchHidden()
            // Allow process initialization before sending playback command
            try await Task.sleep(nanoseconds: 300_000_000)
        }

        self.notificationMonitor.markCommandDispatched()
        try await self.scriptController.play()
        self.transportState = .playing
    }

    func pause() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }
        guard self.isRunning else { return }

        self.notificationMonitor.markCommandDispatched()
        try await self.scriptController.pause()
        self.transportState = .paused
    }

    func toggle() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }

        if !self.isRunning {
            try await self.play()
            return
        }

        self.notificationMonitor.markCommandDispatched()
        try await self.scriptController.togglePlayPause()

        if self.transportState == .playing {
            self.transportState = .paused
        } else {
            self.transportState = .playing
        }
    }

    func next() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }
        guard self.isRunning else {
            throw SpotifySourceError.applicationNotRunning
        }

        self.notificationMonitor.markCommandDispatched()
        try await self.scriptController.nextTrack()
    }

    func previous() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }
        guard self.isRunning else {
            throw SpotifySourceError.applicationNotRunning
        }

        self.notificationMonitor.markCommandDispatched()
        try await self.scriptController.previousTrack()
    }

    func seek(to position: TimeInterval) async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }
        guard self.isRunning else {
            throw SpotifySourceError.applicationNotRunning
        }

        self.notificationMonitor.markCommandDispatched()
        try await self.scriptController.seek(to: position)
        self.playbackPosition = position
    }

    func setVolume(_ volume: Double) async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }

        let clamped = max(0.0, min(1.0, volume))
        if self.isRunning {
            try await self.scriptController.setVolume(clamped)
        }
        self.volume = clamped
    }

    func launchHidden() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }

        try await self.scriptController.launchHidden()
    }

    func refreshState() async {
        guard self.isInstalled, self.isRunning else {
            if !self.isInstalled || !self.isRunning {
                self.transportState = .idle
                self.currentTrack = nil
            }
            return
        }

        do {
            let snapshot = try await self.scriptController.fetchPlaybackSnapshot()
            self.apply(snapshot: snapshot)
        } catch {
            // Non-fatal background refresh error
        }
    }

    // MARK: - Private State Synchronization

    private func setupNotificationObservation() {
        self.notificationMonitor.startObserving { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.apply(snapshot: snapshot)

                // If notification didn't carry artwork URL, enrich from script snapshot if track exists
                if let track = self.currentTrack, track.artworkURL == nil {
                    await self.enrichTrackArtwork()
                }
            }
        }
    }

    private func apply(snapshot: SpotifyPlaybackSnapshot) {
        self.transportState = snapshot.playerState.transportState
        self.playbackPosition = snapshot.position
        self.playbackDuration = snapshot.duration
        self.volume = snapshot.volume

        if let newTrack = snapshot.track {
            // Retain existing artwork URL if the new notification omitted it for the same track
            if let existing = self.currentTrack,
               existing.sourceID == newTrack.sourceID,
               newTrack.artworkURL == nil,
               let existingArtwork = existing.artworkURL
            {
                self.currentTrack = UnifiedTrack(
                    id: existing.id,
                    title: newTrack.title,
                    artist: newTrack.artist,
                    album: newTrack.album,
                    duration: newTrack.duration,
                    artworkURL: existingArtwork,
                    artistImageURL: existing.artistImageURL,
                    source: .spotify,
                    sourceID: newTrack.sourceID
                )
            } else {
                self.currentTrack = newTrack
            }
        } else if snapshot.playerState == .stopped {
            self.currentTrack = nil
        }
    }

    private func enrichTrackArtwork() async {
        guard self.isInstalled, self.isRunning else { return }
        guard let current = self.currentTrack else { return }

        do {
            let snapshot = try await self.scriptController.fetchPlaybackSnapshot()
            if let enriched = snapshot.track, enriched.sourceID == current.sourceID, enriched.artworkURL != nil {
                self.currentTrack = enriched
            }
        } catch {
            // Non-fatal artwork enrichment failure
        }
    }
}

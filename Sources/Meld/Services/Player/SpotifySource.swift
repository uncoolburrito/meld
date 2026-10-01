import AppKit
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

    /// Callback invoked when Spotify starts or resumes playing (for Arbiter Path A detection).
    var onPlaybackStarted: (@MainActor () -> Void)?

    init(
        scriptController: any SpotifyScriptControlling = SpotifyScriptController.shared,
        notificationMonitor: any SpotifyNotificationMonitoring = SpotifyNotificationMonitor(),
        autoRefresh: Bool = true
    ) {
        self.scriptController = scriptController
        self.notificationMonitor = notificationMonitor

        self.setupNotificationObservation()
        self.setupTerminationObservation()

        if autoRefresh {
            Task { [weak self] in
                await self?.refreshState()
            }
        }
    }

    @ObservationIgnored
    private var capturedFadeVolume: Double?

    /// True while Spotify volume is actively being faded during a source transition.
    var isFadingVolume: Bool {
        self.capturedFadeVolume != nil
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

        self.notificationMonitor.markCommandDispatched(expectedState: .playing)
        try await self.scriptController.play()
        self.transportState = .playing
    }

    func pause() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }
        guard self.isRunning else { return }

        self.notificationMonitor.markCommandDispatched(expectedState: .paused)
        try await self.scriptController.pause()
        if let snapshot = try? await self.scriptController.fetchPlaybackSnapshot() {
            self.apply(snapshot: snapshot)
        }
    }

    /// Confirms with Spotify whether playback is currently paused or stopped by querying a fresh snapshot.
    func confirmPaused() async -> Bool {
        guard self.isInstalled, self.isRunning else { return true }
        do {
            let snapshot = try await self.scriptController.fetchPlaybackSnapshot()
            self.apply(snapshot: snapshot)
            return snapshot.playerState != .playing
        } catch {
            return false
        }
    }

    func toggle() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }

        if !self.isRunning {
            try await self.play()
            return
        }

        let nextState: SpotifyPlayerState = self.transportState == .playing ? .paused : .playing
        self.notificationMonitor.markCommandDispatched(expectedState: nextState)
        try await self.scriptController.togglePlayPause()

        if self.transportState == .playing {
            self.transportState = .paused
        } else {
            self.transportState = .playing
        }
    }

    @ObservationIgnored
    var trackTransitionFallbackDuration: TimeInterval = 0.500

    @ObservationIgnored
    private var trackTransitionFallbackTask: Task<Void, Never>?

    func next() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }
        guard self.isRunning else {
            throw SpotifySourceError.applicationNotRunning
        }

        try await self.scriptController.nextTrack()
        self.scheduleTrackTransitionFallback()
    }

    func previous() async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }
        guard self.isRunning else {
            throw SpotifySourceError.applicationNotRunning
        }

        try await self.scriptController.previousTrack()
        self.scheduleTrackTransitionFallback()
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

    // MARK: - Crossfade Support

    /// Prepares Spotify for a volume crossfade by capturing its current volume.
    @discardableResult
    func beginVolumeFade() -> Double {
        let original = self.volume
        self.capturedFadeVolume = original
        return original
    }

    /// Sets Spotify sound volume during a crossfade step without tripping the echo guard or mutating self.volume.
    func stepFadeVolume(_ volume: Double) async {
        guard self.isInstalled, self.isRunning else { return }
        let clamped = max(0.0, min(1.0, volume))
        try? await self.scriptController.setVolume(clamped)
    }

    /// Restores Spotify sound volume after a fade sequence or on transition abort/error.
    func endVolumeFade(restoring volume: Double? = nil) async {
        let volumeToRestore = volume ?? self.capturedFadeVolume ?? self.volume
        self.capturedFadeVolume = nil
        guard self.isInstalled, self.isRunning else { return }
        try? await self.scriptController.setVolume(volumeToRestore)
    }

    /// Synchronous restore executed on NSApplication.willTerminateNotification.
    func emergencyRestoreVolume() {
        guard let volumeToRestore = self.capturedFadeVolume else { return }
        self.capturedFadeVolume = nil
        let clamped = max(0, min(100, Int(volumeToRestore * 100)))
        let script = "tell application id \"com.spotify.client\" to set sound volume to \(clamped)"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    private func setupTerminationObservation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.emergencyRestoreVolume()
            }
        }
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

    private func scheduleTrackTransitionFallback() {
        self.trackTransitionFallbackTask?.cancel()
        let duration = self.trackTransitionFallbackDuration
        self.trackTransitionFallbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.refreshState()
            } catch {
                // Cancelled when notification arrived before fallback deadline
            }
        }
    }

    private func apply(snapshot: SpotifyPlaybackSnapshot) {
        // Notification arrived: cancel any pending track transition reconcile fallback
        self.trackTransitionFallbackTask?.cancel()
        self.trackTransitionFallbackTask = nil

        self.transportState = snapshot.playerState.transportState
        self.playbackPosition = snapshot.position
        self.playbackDuration = snapshot.duration
        if !self.isFadingVolume {
            self.volume = snapshot.volume
        }

        if snapshot.playerState == .playing {
            self.onPlaybackStarted?()
        }

        if let newTrack = snapshot.track {
            if self.currentTrack?.sourceID != newTrack.sourceID {
                NowPlayingManager.shared.playbackArbiter?.clearInterruptedMark(for: .spotify)
            }
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

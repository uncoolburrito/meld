import Foundation
import Testing
@testable import Meld

// MARK: - MockSpotifyScriptController

final class MockSpotifyScriptController: SpotifyScriptControlling, @unchecked Sendable {
    var isInstalled: Bool = true
    var isRunning: Bool = true

    var launchHiddenCalled = false
    var playCalled = false
    var pauseCalled = false
    var toggleCalled = false
    var nextCalled = false
    var previousCalled = false
    var seekPosition: TimeInterval?
    var volumeSet: Double?

    var snapshotToReturn = SpotifyPlaybackSnapshot(
        playerState: .playing,
        position: 45.0,
        duration: 210.0,
        volume: 0.8,
        track: UnifiedTrack(
            title: "Test Track",
            artist: "Test Artist",
            album: "Test Album",
            duration: 210.0,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            source: .spotify,
            sourceID: "spotify:track:test123"
        )
    )

    func launchHidden() async throws {
        self.launchHiddenCalled = true
        self.isRunning = true
    }

    func play() async throws {
        guard self.isInstalled else { throw SpotifySourceError.applicationNotFound }
        guard self.isRunning else { throw SpotifySourceError.applicationNotRunning }
        self.playCalled = true
    }

    func pause() async throws {
        guard self.isInstalled else { throw SpotifySourceError.applicationNotFound }
        guard self.isRunning else { throw SpotifySourceError.applicationNotRunning }
        self.pauseCalled = true
    }

    func togglePlayPause() async throws {
        guard self.isInstalled else { throw SpotifySourceError.applicationNotFound }
        guard self.isRunning else { throw SpotifySourceError.applicationNotRunning }
        self.toggleCalled = true
    }

    func nextTrack() async throws {
        guard self.isInstalled else { throw SpotifySourceError.applicationNotFound }
        guard self.isRunning else { throw SpotifySourceError.applicationNotRunning }
        self.nextCalled = true
    }

    func previousTrack() async throws {
        guard self.isInstalled else { throw SpotifySourceError.applicationNotFound }
        guard self.isRunning else { throw SpotifySourceError.applicationNotRunning }
        self.previousCalled = true
    }

    func seek(to position: TimeInterval) async throws {
        guard self.isInstalled else { throw SpotifySourceError.applicationNotFound }
        guard self.isRunning else { throw SpotifySourceError.applicationNotRunning }
        self.seekPosition = position
    }

    func setVolume(_ volume: Double) async throws {
        guard self.isInstalled else { throw SpotifySourceError.applicationNotFound }
        self.volumeSet = volume
    }

    func fetchPlaybackSnapshot() async throws -> SpotifyPlaybackSnapshot {
        guard self.isInstalled else { throw SpotifySourceError.applicationNotFound }
        guard self.isRunning else { return .idle }
        return self.snapshotToReturn
    }
}

// MARK: - MockSpotifyNotificationMonitor

final class MockSpotifyNotificationMonitor: SpotifyNotificationMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    var updateHandler: (@Sendable (SpotifyPlaybackSnapshot) -> Void)?
    var commandDispatchedCalled = false
    private var lastDispatchedTime: Date = .distantPast

    var isEchoSuppressionActive: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return Date().timeIntervalSince(self.lastDispatchedTime) < 0.200
    }

    func startObserving(onUpdate: @escaping @Sendable (SpotifyPlaybackSnapshot) -> Void) {
        self.lock.lock()
        self.updateHandler = onUpdate
        self.lock.unlock()
    }

    func stopObserving() {
        self.lock.lock()
        self.updateHandler = nil
        self.lock.unlock()
    }

    func markCommandDispatched() {
        self.lock.lock()
        self.commandDispatchedCalled = true
        self.lastDispatchedTime = Date()
        self.lock.unlock()
    }

    func simulateNotification(snapshot: SpotifyPlaybackSnapshot) {
        self.lock.lock()
        let handler = self.updateHandler
        self.lock.unlock()
        handler?(snapshot)
    }
}

// MARK: - SpotifyIntegrationTests

@Suite("Spotify Integration (Phase 2)")
struct SpotifyIntegrationTests {
    // MARK: - State & Parser Tests

    @Test("SpotifyPlayerState correctly parses AppleScript and notification strings")
    func playerStateParsing() {
        #expect(SpotifyPlayerState(rawString: "playing") == .playing)
        #expect(SpotifyPlayerState(rawString: "Playing") == .playing)
        #expect(SpotifyPlayerState(rawString: "kPSP") == .playing)
        #expect(SpotifyPlayerState(rawString: "paused") == .paused)
        #expect(SpotifyPlayerState(rawString: "Paused") == .paused)
        #expect(SpotifyPlayerState(rawString: "kPSp") == .paused)
        #expect(SpotifyPlayerState(rawString: "stopped") == .stopped)
        #expect(SpotifyPlayerState(rawString: "Stopped") == .stopped)
        #expect(SpotifyPlayerState(rawString: "kPSS") == .stopped)
        #expect(SpotifyPlayerState(rawString: "something_unexpected") == .unknown)

        #expect(SpotifyPlayerState.playing.transportState == .playing)
        #expect(SpotifyPlayerState.paused.transportState == .paused)
        #expect(SpotifyPlayerState.stopped.transportState == .idle)
        #expect(SpotifyPlayerState.unknown.transportState == .idle)
    }

    @Test("SpotifyScriptController accurately parses compound output")
    func compoundOutputParsing() {
        let controller = SpotifyScriptController()
        let raw = "paused|||15.52|||80|||spotify:track:4cOdK2wGLETKBW3PvgPWqT|||Never Gonna Give You Up|||Rick Astley|||Whenever You Need Somebody|||213573|||https://i.scdn.co/image/abc"

        let snapshot = controller.parseSnapshot(rawOutput: raw)

        #expect(snapshot.playerState == .paused)
        #expect(abs(snapshot.position - 15.52) < 0.001)
        #expect(abs(snapshot.volume - 0.80) < 0.001)
        #expect(snapshot.track != nil)
        #expect(snapshot.track?.title == "Never Gonna Give You Up")
        #expect(snapshot.track?.artist == "Rick Astley")
        #expect(snapshot.track?.album == "Whenever You Need Somebody")
        #expect(abs((snapshot.track?.duration ?? 0.0) - 213.573) < 0.001)
        #expect(snapshot.track?.artworkURL == URL(string: "https://i.scdn.co/image/abc"))
        #expect(snapshot.track?.source == .spotify)
        #expect(snapshot.track?.sourceID == "spotify:track:4cOdK2wGLETKBW3PvgPWqT")
    }

    @Test("SpotifyScriptController handles stopped and empty compound states")
    func stoppedOutputParsing() {
        let controller = SpotifyScriptController()

        let stoppedRaw = "stopped|||0.0|||100|||STOPPED"
        let stoppedSnapshot = controller.parseSnapshot(rawOutput: stoppedRaw)
        #expect(stoppedSnapshot.playerState == .stopped)
        #expect(stoppedSnapshot.track == nil)

        let noTrackRaw = "paused|||0.0|||50|||NO_TRACK"
        let noTrackSnapshot = controller.parseSnapshot(rawOutput: noTrackRaw)
        #expect(noTrackSnapshot.playerState == .paused)
        #expect(noTrackSnapshot.track == nil)
    }

    @Test("SpotifyNotificationMonitor parses userInfo and converts duration from ms to seconds")
    func notificationUserInfoParsing() {
        let userInfo: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Playback Position": 42.5,
            "Duration": 185_000, // 185,000 ms
            "Track ID": "spotify:track:xyz987",
            "Name": "Blinding Lights",
            "Artist": "The Weeknd",
            "Album": "After Hours",
        ]

        let snapshot = SpotifyNotificationMonitor.parse(userInfo: userInfo)

        #expect(snapshot.playerState == .playing)
        #expect(snapshot.position == 42.5)
        #expect(snapshot.duration == 185.0)
        #expect(snapshot.track?.title == "Blinding Lights")
        #expect(snapshot.track?.artist == "The Weeknd")
        #expect(snapshot.track?.album == "After Hours")
        #expect(snapshot.track?.sourceID == "spotify:track:xyz987")
    }

    @Test("Echo guard suppresses rapid feedback loop within configured window")
    func echoGuardTiming() async throws {
        let monitor = SpotifyNotificationMonitor(echoSuppressionWindow: 0.100)
        #expect(!monitor.isEchoSuppressionActive)

        monitor.markCommandDispatched()
        #expect(monitor.isEchoSuppressionActive)

        // Wait past suppression window
        try await Task.sleep(nanoseconds: 120_000_000)
        #expect(!monitor.isEchoSuppressionActive)
    }

    // MARK: - Missing App & Source Conformance Tests

    @Test("SpotifySource handles missing application gracefully")
    @MainActor
    func missingAppHandling() async {
        let mockScript = MockSpotifyScriptController()
        mockScript.isInstalled = false
        mockScript.isRunning = false

        let mockMonitor = MockSpotifyNotificationMonitor()
        let source = SpotifySource(scriptController: mockScript, notificationMonitor: mockMonitor)

        #expect(!source.isInstalled)
        #expect(!source.isRunning)
        #expect(source.transportState == .idle)
        #expect(source.currentTrack == nil)

        await #expect(throws: SpotifySourceError.applicationNotFound) {
            try await source.play()
        }
        await #expect(throws: SpotifySourceError.applicationNotFound) {
            try await source.pause()
        }
        await #expect(throws: SpotifySourceError.applicationNotFound) {
            try await source.toggle()
        }
        await #expect(throws: SpotifySourceError.applicationNotFound) {
            try await source.next()
        }
        await #expect(throws: SpotifySourceError.applicationNotFound) {
            try await source.previous()
        }
        await #expect(throws: SpotifySourceError.applicationNotFound) {
            try await source.seek(to: 10.0)
        }
        await #expect(throws: SpotifySourceError.applicationNotFound) {
            try await source.setVolume(0.5)
        }
        await #expect(throws: SpotifySourceError.applicationNotFound) {
            try await source.launchHidden()
        }
    }

    @Test("SpotifySource launches hidden when playing while not running")
    @MainActor
    func launchHiddenWhenPlayCalled() async throws {
        let mockScript = MockSpotifyScriptController()
        mockScript.isInstalled = true
        mockScript.isRunning = false

        let mockMonitor = MockSpotifyNotificationMonitor()
        let source = SpotifySource(scriptController: mockScript, notificationMonitor: mockMonitor)

        try await source.play()

        #expect(mockScript.launchHiddenCalled)
        #expect(mockScript.playCalled)
        #expect(mockMonitor.commandDispatchedCalled)
        #expect(source.transportState == .playing)
    }

    @Test("SpotifySource updates state when notification arrives")
    @MainActor
    func notificationStateUpdate() async throws {
        let mockScript = MockSpotifyScriptController()
        let mockMonitor = MockSpotifyNotificationMonitor()
        let source = SpotifySource(
            scriptController: mockScript,
            notificationMonitor: mockMonitor,
            autoRefresh: false
        )

        let testTrack = UnifiedTrack(
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            duration: 243.0,
            artworkURL: nil,
            source: .spotify,
            sourceID: "spotify:track:m83"
        )

        let snapshot = SpotifyPlaybackSnapshot(
            playerState: .playing,
            position: 12.0,
            duration: 243.0,
            volume: 0.9,
            track: testTrack
        )

        mockMonitor.simulateNotification(snapshot: snapshot)

        // Allow MainActor task execution
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(source.transportState == .playing)
        #expect(source.playbackPosition == 12.0)
        #expect(source.playbackDuration == 243.0)
        #expect(source.currentTrack?.title == "Midnight City")
        #expect(source.currentTrack?.artist == "M83")
    }

    @Test("20-sample latency benchmark computes statistics accurately")
    func benchmarkComputation() {
        let testSamples: [Double] = [
            12.0, 15.0, 14.0, 18.0, 16.0, 13.0, 17.0, 19.0, 15.5, 14.5,
            20.0, 22.0, 21.0, 25.0, 23.0, 24.0, 28.0, 27.0, 26.0, 32.0,
        ]

        let result = SpotifyBenchmarkResult(samples: testSamples)

        #expect(result.minMs == 12.0)
        #expect(result.maxMs == 32.0)
        #expect(result.p50Ms > 15.0 && result.p50Ms < 25.0)
        #expect(result.p99Ms > 25.0)
    }
}

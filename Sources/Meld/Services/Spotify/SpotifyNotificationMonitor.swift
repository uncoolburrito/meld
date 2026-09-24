import Foundation

// MARK: - SpotifyNotificationMonitoring

/// Protocol defining observation of Spotify distributed playback notifications.
protocol SpotifyNotificationMonitoring: AnyObject, Sendable {
    func startObserving(onUpdate: @escaping @Sendable (SpotifyPlaybackSnapshot) -> Void)
    func stopObserving()
    func markCommandDispatched(expectedState: SpotifyPlayerState?)
    var isEchoSuppressionActive: Bool { get }
}

extension SpotifyNotificationMonitoring {
    func markCommandDispatched() {
        self.markCommandDispatched(expectedState: nil)
    }
}

// MARK: - SpotifyNotificationMonitor

/// Listens for `com.spotify.client.PlaybackStateChanged` on macOS DistributedNotificationCenter.
final class SpotifyNotificationMonitor: SpotifyNotificationMonitoring, @unchecked Sendable {
    static let notificationName = NSNotification.Name("com.spotify.client.PlaybackStateChanged")

    private let lock = NSLock()
    private var observerToken: AnyObject?
    private var onUpdate: (@Sendable (SpotifyPlaybackSnapshot) -> Void)?
    private var lastCommandTimestamp: Date = .distantPast
    private var expectedState: SpotifyPlayerState?
    private let echoSuppressionWindow: TimeInterval

    init(echoSuppressionWindow: TimeInterval = 0.250) {
        self.echoSuppressionWindow = echoSuppressionWindow
    }

    deinit {
        self.stopObserving()
    }

    var isEchoSuppressionActive: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return Date().timeIntervalSince(self.lastCommandTimestamp) < self.echoSuppressionWindow
    }

    func markCommandDispatched(expectedState: SpotifyPlayerState? = nil) {
        self.lock.lock()
        self.lastCommandTimestamp = Date()
        self.expectedState = expectedState
        self.lock.unlock()
    }

    func startObserving(onUpdate: @escaping @Sendable (SpotifyPlaybackSnapshot) -> Void) {
        self.lock.lock()
        defer { self.lock.unlock() }

        self.onUpdate = onUpdate
        guard self.observerToken == nil else { return }

        self.observerToken = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleNotification(notification)
        }
    }

    func stopObserving() {
        self.lock.lock()
        defer { self.lock.unlock() }

        if let token = self.observerToken {
            DistributedNotificationCenter.default().removeObserver(token)
            self.observerToken = nil
        }
        self.onUpdate = nil
    }

    // MARK: - Notification Handling

    func handleNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let snapshot = Self.parse(userInfo: userInfo)

        self.lock.lock()
        let isWindowActive = Date().timeIntervalSince(self.lastCommandTimestamp) < self.echoSuppressionWindow
        if isWindowActive {
            if let expected = self.expectedState {
                // If an expected state was specified, only suppress echoes matching that commanded state.
                // A differing state (e.g. user pressed pause in Spotify.app) bypasses suppression.
                if snapshot.playerState == expected {
                    self.lock.unlock()
                    return
                }
            } else {
                // Blanket suppression fallback when no expected state was specified
                self.lock.unlock()
                return
            }
        }
        let handler = self.onUpdate
        self.lock.unlock()

        handler?(snapshot)
    }

    static func parse(userInfo: [AnyHashable: Any]) -> SpotifyPlaybackSnapshot {
        let rawState = (userInfo["Player State"] as? String) ?? "stopped"
        let playerState = SpotifyPlayerState(rawString: rawState)

        let position = (userInfo["Playback Position"] as? Double)
            ?? (userInfo["Playback Position"] as? Int).map { Double($0) }
            ?? 0.0

        let rawDuration = (userInfo["Duration"] as? Double)
            ?? (userInfo["Duration"] as? Int).map { Double($0) }
            ?? 0.0
        // Spotify notification duration is delivered in milliseconds
        let duration = rawDuration > 0 ? rawDuration / 1000.0 : 0.0

        let rawTrackID = userInfo["Track ID"] as? String
        let sourceID = SpotifyPlaybackSnapshot.normalizeTrackID(rawTrackID)
        let name = userInfo["Name"] as? String
        let artist = userInfo["Artist"] as? String
        let album = userInfo["Album"] as? String

        let track: UnifiedTrack? = if let name, !name.isEmpty, let artist, !artist.isEmpty {
            UnifiedTrack(
                title: name,
                artist: artist,
                album: album?.isEmpty == true ? nil : album,
                duration: duration,
                artworkURL: nil, // DistributedNotification does not carry image URL; fetched via script or API if needed
                source: .spotify,
                sourceID: sourceID
            )
        } else {
            nil
        }

        return SpotifyPlaybackSnapshot(
            playerState: playerState,
            position: position,
            duration: duration,
            volume: 1.0, // Notification does not carry sound volume
            track: track
        )
    }
}

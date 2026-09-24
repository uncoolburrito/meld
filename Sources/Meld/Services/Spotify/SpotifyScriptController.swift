import AppKit
import Foundation

// MARK: - SpotifyScriptControlling

/// Protocol defining operations executable against the local Spotify desktop application.
protocol SpotifyScriptControlling: Sendable {
    var isInstalled: Bool { get }
    var isRunning: Bool { get }

    func launchHidden() async throws
    func play() async throws
    func pause() async throws
    func togglePlayPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func seek(to position: TimeInterval) async throws
    func setVolume(_ volume: Double) async throws
    func fetchPlaybackSnapshot() async throws -> SpotifyPlaybackSnapshot
}

// MARK: - SpotifyScriptController

/// Executes verified AppleScript / Apple Events commands against Spotify.app.
final class SpotifyScriptController: SpotifyScriptControlling, @unchecked Sendable {
    static let shared = SpotifyScriptController()

    private let bundleIdentifier = "com.spotify.client"
    private let defaultTimeout: TimeInterval

    init(defaultTimeout: TimeInterval = 0.500) {
        self.defaultTimeout = defaultTimeout
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: self.bundleIdentifier) != nil
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleIdentifier).isEmpty
    }

    func launchHidden() async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: self.bundleIdentifier) else {
            throw SpotifySourceError.applicationNotFound
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true

        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    func play() async throws {
        try await self.execute(command: "play")
    }

    func pause() async throws {
        try await self.execute(command: "pause")
    }

    func togglePlayPause() async throws {
        try await self.execute(command: "playpause")
    }

    func nextTrack() async throws {
        try await self.execute(command: "next track")
    }

    func previousTrack() async throws {
        try await self.execute(command: "previous track")
    }

    func seek(to position: TimeInterval) async throws {
        let clampedPosition = max(0.0, position)
        try await self.execute(command: "set player position to \(clampedPosition)")
    }

    func setVolume(_ volume: Double) async throws {
        let clampedVolume = max(0, min(100, Int(volume * 100)))
        try await self.execute(command: "set sound volume to \(clampedVolume)")
    }

    func fetchPlaybackSnapshot() async throws -> SpotifyPlaybackSnapshot {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }
        guard self.isRunning else {
            return .idle
        }

        let script = """
        tell application id "\(self.bundleIdentifier)"
            set pState to player state as string
            set pPos to player position
            set sVol to sound volume
            if pState is "stopped" then
                return pState & "|||" & pPos & "|||" & sVol & "|||STOPPED"
            end if
            try
                set tId to id of current track
                set tName to name of current track
                set tArt to artist of current track
                set tAlb to album of current track
                set tDur to duration of current track
                set tUrl to artwork url of current track
                return pState & "|||" & pPos & "|||" & sVol & "|||" & tId & "|||" & tName & "|||" & tArt & "|||" & tAlb & "|||" & tDur & "|||" & tUrl
            on error
                return pState & "|||" & pPos & "|||" & sVol & "|||NO_TRACK"
            end try
        end tell
        """

        let rawOutput = try await self.executeAppleScript(script)
        return self.parseSnapshot(rawOutput: rawOutput)
    }

    // MARK: - Private Execution Helpers

    private func execute(command: String) async throws {
        guard self.isInstalled else {
            throw SpotifySourceError.applicationNotFound
        }
        guard self.isRunning else {
            throw SpotifySourceError.applicationNotRunning
        }

        let source = "tell application id \"\(self.bundleIdentifier)\" to \(command)"
        _ = try await self.executeAppleScript(source)
    }

    private func executeAppleScript(_ source: String) async throws -> String {
        let timeout = self.defaultTimeout

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try Task.checkCancellation()
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    throw SpotifySourceError.scriptExecutionFailed("Failed to initialize NSAppleScript")
                }

                let descriptor = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    throw SpotifySourceError.scriptExecutionFailed(message)
                }

                return descriptor.stringValue ?? ""
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SpotifySourceError.commandTimeout
            }

            guard let firstResult = try await group.next() else {
                throw SpotifySourceError.commandTimeout
            }

            group.cancelAll()
            return firstResult
        }
    }

    func parseSnapshot(rawOutput: String) -> SpotifyPlaybackSnapshot {
        let parts = rawOutput.components(separatedBy: "|||")
        guard parts.count >= 3 else {
            return .idle
        }

        let playerState = SpotifyPlayerState(rawString: parts[0])
        let position = Double(parts[1]) ?? 0.0
        let volumeInt = Double(parts[2]) ?? 100.0
        let volume = max(0.0, min(1.0, volumeInt / 100.0))

        if parts.count < 9 || parts[3] == "STOPPED" || parts[3] == "NO_TRACK" {
            return SpotifyPlaybackSnapshot(
                playerState: playerState,
                position: position,
                duration: 0.0,
                volume: volume,
                track: nil
            )
        }

        let rawTrackID = parts[3]
        let sourceID = SpotifyPlaybackSnapshot.normalizeTrackID(rawTrackID)
        let title = parts[4]
        let artist = parts[5]
        let album = parts[6].isEmpty ? nil : parts[6]
        let durationMs = Double(parts[7]) ?? 0.0
        let durationSeconds = durationMs > 0 ? durationMs / 1000.0 : 0.0
        let artworkURL = URL(string: parts[8])

        let track = UnifiedTrack(
            title: title,
            artist: artist,
            album: album,
            duration: durationSeconds,
            artworkURL: artworkURL,
            source: .spotify,
            sourceID: sourceID
        )

        return SpotifyPlaybackSnapshot(
            playerState: playerState,
            position: position,
            duration: durationSeconds,
            volume: volume,
            track: track
        )
    }
}

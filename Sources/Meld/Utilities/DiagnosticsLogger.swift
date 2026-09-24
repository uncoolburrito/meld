import Foundation
import os

/// Centralized logging for the Kaset app.
enum DiagnosticsLogger {
    /// Logger for authentication-related events.
    static let auth = Logger(subsystem: "com.uncoolburrito.meld", category: "Auth")

    /// Logger for API-related events.
    static let api = Logger(subsystem: "com.uncoolburrito.meld", category: "API")

    /// Logger for WebKit-related events.
    static let webKit = Logger(subsystem: "com.uncoolburrito.meld", category: "WebKit")

    /// Logger for player-related events.
    static let player = Logger(subsystem: "com.uncoolburrito.meld", category: "Player")

    /// Logger for UI-related events.
    static let ui = Logger(subsystem: "com.uncoolburrito.meld", category: "UI")

    /// Logger for notification-related events.
    static let notification = Logger(subsystem: "com.uncoolburrito.meld", category: "Notification")

    /// Logger for AI/Foundation Models-related events.
    static let ai = Logger(subsystem: "com.uncoolburrito.meld", category: "AI")

    /// Logger for haptic feedback-related events.
    static let haptic = Logger(subsystem: "com.uncoolburrito.meld", category: "Haptic")

    /// Logger for network connectivity-related events.
    static let network = Logger(subsystem: "com.uncoolburrito.meld", category: "Network")

    /// Logger for updater/general app events.
    static let updater = Logger(subsystem: "com.uncoolburrito.meld", category: "Updater")

    /// Logger for app lifecycle and URL handling events.
    static let app = Logger(subsystem: "com.uncoolburrito.meld", category: "App")

    /// Logger for AppleScript scripting events.
    static let scripting = Logger(subsystem: "com.uncoolburrito.meld", category: "Scripting")

    /// Logger for AirPlay-related events.
    static let airplay = Logger(subsystem: "com.uncoolburrito.meld", category: "AirPlay")

    /// Logger for scrobbling-related events (Last.fm, etc.).
    static let scrobbling = Logger(subsystem: "com.uncoolburrito.meld", category: "Scrobbling")

    /// Logger for web extension management events.
    static let extensions = Logger(subsystem: "com.uncoolburrito.meld", category: "Extensions")

    /// Logger for listening history-related events.
    static let history = Logger(subsystem: "com.uncoolburrito.meld", category: "History")

    /// Logger for the equalizer subsystem (process tap, HAL I/O, DSP).
    static let equalizer = Logger(subsystem: "com.uncoolburrito.meld", category: "Equalizer")
}

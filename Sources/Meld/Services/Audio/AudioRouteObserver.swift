import CoreAudio
import Foundation
import os

// MARK: - AudioRouteObserver

/// Observes macOS CoreAudio default output device changes (e.g. Bluetooth connection/disconnection).
///
/// When a Bluetooth audio route changes while playback is paused, macOS media routing
/// can invalidate or re-request remote command registrations. `AudioRouteObserver`
/// alerts `NowPlayingManager` to re-assert remote command handlers and Now Playing state
/// if the active source is internal (`.music` or `.video`), avoiding media key loss.
@MainActor
final class AudioRouteObserver {
    static let shared = AudioRouteObserver()

    private var isListening = false
    private var onRouteChange: (@MainActor () -> Void)?
    private let logger = DiagnosticsLogger.player

    // Listener block invoked by Core Audio on its own callback queue.
    // Declared nonisolated static so it does not inherit MainActor isolation.
    // We hop to MainActor via Task { @MainActor in ... }.
    // swiftformat:disable:next modifierOrder
    nonisolated private static let defaultOutputDeviceListener:
        @Sendable (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void = { _, _ in
            Task { @MainActor in
                AudioRouteObserver.shared.handleDefaultOutputDeviceChange()
            }
        }

    private init() {}

    /// Installs the default output device property listener on the HAL system object.
    func startObserving(onRouteChange: @escaping @MainActor () -> Void) {
        guard !self.isListening else { return }
        self.onRouteChange = onRouteChange
        self.isListening = true

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            Self.defaultOutputDeviceListener
        )

        if status != noErr {
            self.logger.warning("AudioRouteObserver: failed to register default output device listener: \(status)")
        } else {
            self.logger.info("AudioRouteObserver: listening for default output device changes")
        }
    }

    func handleDefaultOutputDeviceChange() {
        self.logger.info("AudioRouteObserver: default output device changed")
        self.onRouteChange?()
    }
}

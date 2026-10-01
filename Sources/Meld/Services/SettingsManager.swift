import Foundation
import Observation

/// Manages user preferences persisted via UserDefaults.
@MainActor
@Observable
final class SettingsManager {
    static let shared = SettingsManager()
    nonisolated static let defaultAmbientBackdropStyle: AmbientBackdropStyle = .soft

    // MARK: - Settings Keys

    enum Keys {
        static let appSource = "settings.appSource"
        static let showNowPlayingNotifications = "settings.showNowPlayingNotifications"
        static let defaultLaunchPage = "settings.defaultLaunchPage"
        static let hapticFeedbackEnabled = "settings.hapticFeedbackEnabled"
        static let rememberPlaybackSettings = "settings.rememberPlaybackSettings"
        static let lastFMEnabled = "settings.lastFMEnabled"
        static let enabledServices = "settings.enabledServices"
        static let scrobblePercentThreshold = "settings.scrobblePercentThreshold"
        static let scrobbleMinSeconds = "settings.scrobbleMinSeconds"
        static let mediaControlStyle = "settings.mediaControlStyle"
        static let playbackAudioQuality = "settings.playbackAudioQuality"
        static let syncedLyricsEnabled = "settings.syncedLyricsEnabled"
        static let romanizationEnabled = "settings.romanizationEnabled"
        static let contentLanguage = "settings.contentLanguage"
        static let keepMiniPlayerOnTop = "settings.keepMiniPlayerOnTop"
        static let keepYouTubeVideoOnTop = "settings.keepYouTubeVideoOnTop"
        static let smartShuffleEnabled = "settings.smartShuffleEnabled"
        static let smartShuffleSuggestEveryN = "settings.smartShuffleSuggestEveryN"
        static let smartShuffleBurst = "settings.smartShuffleBurst"
        static let smartShuffleSuggestionsAhead = "settings.smartShuffleSuggestionsAhead"
        static let ambientBackdropEnabled = "settings.ambientBackdropEnabled"
        static let ambientBackdropStyle = "settings.ambientBackdropStyle"
        static let popOutVideoOnNavigateAway = "settings.popOutVideoOnNavigateAway"
        static let spotifyVolumeGainOffset = "settings.spotifyVolumeGainOffset"
        static let sourceSwitchBehavior = "settings.sourceSwitchBehavior"
        #if DEBUG
            static let useLegacyMacOS15UI = "settings.debug.useLegacyMacOS15UI"
        #endif
    }

    // MARK: - Source Switch Behavior Options

    /// Available behaviors when switching between music sources.
    enum SourceSwitchBehavior: String, CaseIterable, Identifiable {
        case resume
        case pauseOnly

        var id: String {
            self.rawValue
        }

        var displayName: String {
            switch self {
            case .resume:
                String(localized: "Resume where I left off", comment: "Option to resume previously interrupted playback when switching sources")
            case .pauseOnly:
                String(localized: "Pause only", comment: "Option to only pause outgoing playback without resuming incoming source")
            }
        }
    }

    // MARK: - Launch Page Options

    /// Available pages to launch the app with.
    enum LaunchPage: String, CaseIterable, Identifiable {
        case home
        case explore
        case charts
        case moodsAndGenres
        case newReleases
        case likedMusic
        case playlists
        case lastUsed

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .home: String(localized: "Home")
            case .explore: String(localized: "Explore")
            case .charts: String(localized: "Charts")
            case .moodsAndGenres: String(localized: "Moods & Genres")
            case .newReleases: String(localized: "New Releases")
            case .likedMusic: String(localized: "Liked Music")
            case .playlists: String(localized: "Playlists")
            case .lastUsed: String(localized: "Last Used")
            }
        }

        /// Converts LaunchPage to NavigationItem for navigation.
        var navigationItem: NavigationItem {
            switch self {
            case .home: .home
            case .explore: .explore
            case .charts: .charts
            case .moodsAndGenres: .moodsAndGenres
            case .newReleases: .newReleases
            case .likedMusic: .likedMusic
            case .playlists: .library
            case .lastUsed: .home // Fallback, actual value comes from lastUsedPage
            }
        }
    }

    // MARK: - Content Language

    /// Available language options for app UI localization.
    enum ContentLanguage: String, CaseIterable, Identifiable {
        case system
        case arabic
        case german
        case english
        case spanish
        case french
        case indonesian
        case italian
        case korean
        case dutch
        case polish
        case portuguese
        case russian
        case swedish
        case turkish
        case ukrainian
        case simplifiedChinese
        case traditionalChinese

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .system: String(localized: "System Default")
            case .arabic: "العربية"
            case .dutch: "Nederlands"
            case .english: "English"
            case .french: "Français"
            case .german: "Deutsch"
            case .indonesian: "Bahasa Indonesia"
            case .italian: "Italiano"
            case .korean: "한국어"
            case .polish: "Polski"
            case .portuguese: "Português"
            case .russian: "Русский"
            case .spanish: "Español"
            case .simplifiedChinese: "简体中文"
            case .swedish: "Svenska"
            case .traditionalChinese: "繁體中文"
            case .turkish: "Türkçe"
            case .ukrainian: "Українська"
            }
        }

        /// The language code for bundle lookup, or `nil` for the system default.
        var languageCode: String? {
            switch self {
            case .system: nil
            case .arabic: "ar"
            case .dutch: "nl"
            case .english: "en"
            case .french: "fr"
            case .german: "de"
            case .indonesian: "id"
            case .italian: "it"
            case .korean: "ko"
            case .polish: "pl"
            case .portuguese: "pt"
            case .russian: "ru"
            case .spanish: "es"
            // Chinese is distinguished by script, not region, matching Apple's
            // localization identifiers. Verified against the InnerTube API: these
            // same codes are valid `hl` values and return correctly-scripted
            // responses, so no separate API mapping is needed.
            case .simplifiedChinese: "zh-Hans"
            case .swedish: "sv"
            case .traditionalChinese: "zh-Hant"
            case .turkish: "tr"
            case .ukrainian: "uk"
            }
        }

        /// The language code for YouTube Music API requests (`hl` parameter).
        /// Returns the explicit language code or derives one from the system locale,
        /// falling back to `"en"`.
        var apiLanguageCode: String {
            self.apiLanguageCode(for: Locale.current)
        }

        /// Resolves the API language code against an injectable system locale.
        func apiLanguageCode(for systemLocale: Locale) -> String {
            if let languageCode = self.languageCode {
                return languageCode
            }

            let language = systemLocale.language
            guard let languageCode = language.languageCode?.identifier else {
                return "en"
            }

            return switch (languageCode, language.script?.identifier) {
            case ("zh", "Hans"): "zh-Hans"
            case ("zh", "Hant"): "zh-Hant"
            default: languageCode
            }
        }

        /// The locale matching this language selection.
        var locale: Locale {
            if let code = self.languageCode {
                Locale(identifier: code)
            } else {
                Locale.current
            }
        }
    }

    // MARK: - Media Control Style

    /// Controls which buttons appear in the Now Playing widget (Control Center).
    enum MediaControlStyle: String, CaseIterable, Identifiable {
        case skipForwardBackward
        case nextPreviousTrack

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .skipForwardBackward: "Skip Forward/Backward"
            case .nextPreviousTrack: "Next/Previous Track"
            }
        }
    }

    // MARK: - Playback Audio Quality

    /// Preferred audio quality for playback through the YouTube Music WebView.
    enum PlaybackAudioQuality: String, CaseIterable, Identifiable {
        case auto
        case low
        case normal
        case high

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .auto: "Auto"
            case .low: "Low"
            case .normal: "Normal"
            case .high: "High"
            }
        }
    }

    // MARK: - Settings Properties

    private let defaults: UserDefaults

    /// The active content source (YouTube Music or regular YouTube).
    var appSource: AppSource {
        didSet {
            self.defaults.set(self.appSource.rawValue, forKey: Keys.appSource)
        }
    }

    /// Per-source volume gain offset in decibels for Spotify (default: 0.0 dB).
    var spotifyVolumeGainOffset: Double {
        didSet {
            self.defaults.set(self.spotifyVolumeGainOffset, forKey: Keys.spotifyVolumeGainOffset)
        }
    }

    /// Whether to show system notifications when the track changes.
    var showNowPlayingNotifications: Bool {
        didSet {
            self.defaults.set(self.showNowPlayingNotifications, forKey: Keys.showNowPlayingNotifications)
        }
    }

    /// The default page to show when the app launches.
    var defaultLaunchPage: LaunchPage {
        didSet {
            self.defaults.set(self.defaultLaunchPage.rawValue, forKey: Keys.defaultLaunchPage)
        }
    }

    /// Whether haptic feedback is enabled.
    var hapticFeedbackEnabled: Bool {
        didSet {
            self.defaults.set(self.hapticFeedbackEnabled, forKey: Keys.hapticFeedbackEnabled)
        }
    }

    /// Whether to remember shuffle/repeat settings across app restarts.
    var rememberPlaybackSettings: Bool {
        didSet {
            self.defaults.set(self.rememberPlaybackSettings, forKey: Keys.rememberPlaybackSettings)
            // Clear stale values when setting is disabled to prevent unexpected restoration
            if !self.rememberPlaybackSettings {
                self.defaults.removeObject(forKey: "playerShuffleEnabled")
                self.defaults.removeObject(forKey: "playerShuffleMode")
                self.defaults.removeObject(forKey: "playerRepeatMode")
            }
        }
    }

    /// Behavior when toggling between audio sources (resume interrupted source or pause only).
    var sourceSwitchBehavior: SourceSwitchBehavior {
        didSet {
            self.defaults.set(self.sourceSwitchBehavior.rawValue, forKey: Keys.sourceSwitchBehavior)
            // Changing the setting clears all marks so switching modes mid-session cannot trigger a stale resume
            NowPlayingManager.shared.playbackArbiter?.clearInterruptedMarks()
        }
    }

    /// Which buttons to show in the Now Playing widget: skip forward/backward or next/previous track.
    var mediaControlStyle: MediaControlStyle {
        didSet {
            self.defaults.set(self.mediaControlStyle.rawValue, forKey: Keys.mediaControlStyle)
        }
    }

    /// Preferred audio quality for playback through the YouTube Music WebView.
    var playbackAudioQuality: PlaybackAudioQuality {
        didSet {
            self.defaults.set(self.playbackAudioQuality.rawValue, forKey: Keys.playbackAudioQuality)
        }
    }

    /// Per-service enabled flags stored as a dictionary.
    private var enabledServices: [String: Bool] {
        didSet {
            self.defaults.set(self.enabledServices, forKey: Keys.enabledServices)
        }
    }

    /// Whether a specific scrobbling service is enabled by name.
    func isServiceEnabled(_ serviceName: String) -> Bool {
        self.enabledServices[serviceName] ?? false
    }

    /// Sets the enabled state for a specific scrobbling service by name.
    func setServiceEnabled(_ serviceName: String, _ enabled: Bool) {
        self.enabledServices[serviceName] = enabled
    }

    /// Whether Last.fm scrobbling is enabled (backward-compatible convenience).
    var lastFMEnabled: Bool {
        get { self.isServiceEnabled("Last.fm") }
        set { self.setServiceEnabled("Last.fm", newValue) }
    }

    /// Percentage of track duration required before scrobbling (0.0–1.0).
    var scrobblePercentThreshold: Double {
        didSet {
            self.defaults.set(self.scrobblePercentThreshold, forKey: Keys.scrobblePercentThreshold)
        }
    }

    /// Minimum seconds of play time before scrobbling (overrides percentage for long tracks).
    var scrobbleMinSeconds: TimeInterval {
        didSet {
            self.defaults.set(self.scrobbleMinSeconds, forKey: Keys.scrobbleMinSeconds)
        }
    }

    /// The last page the user was on (for "Last Used" option).
    var lastUsedPage: LaunchPage = .home

    /// Whether synced lyrics are preferred.
    var syncedLyricsEnabled: Bool {
        didSet {
            self.defaults.set(self.syncedLyricsEnabled, forKey: Keys.syncedLyricsEnabled)
        }
    }

    /// Whether romanization of non-Latin lyrics is enabled.
    var romanizationEnabled: Bool {
        didSet {
            self.defaults.set(self.romanizationEnabled, forKey: Keys.romanizationEnabled)
        }
    }

    /// Whether the mini player floats above other windows.
    var keepMiniPlayerOnTop: Bool {
        didSet {
            self.defaults.set(self.keepMiniPlayerOnTop, forKey: Keys.keepMiniPlayerOnTop)
        }
    }

    /// Whether the regular YouTube video window floats above standard windows.
    var keepYouTubeVideoOnTop: Bool {
        didSet {
            self.defaults.set(self.keepYouTubeVideoOnTop, forKey: Keys.keepYouTubeVideoOnTop)
        }
    }

    // MARK: - Smart Shuffle defaults & ranges (single source of truth)

    /// Default cadence: insert a burst of suggestions every N originals.
    static let smartShuffleSuggestEveryNDefault = 3
    /// Valid range for the insert-every-N cadence.
    static let smartShuffleSuggestEveryNRange = 1 ... 6
    /// Default number of suggestions inserted at each slot.
    static let smartShuffleBurstDefault = 1
    /// Valid range for the per-insertion burst.
    static let smartShuffleBurstRange = 1 ... 5
    /// Default number of suggestions to keep queued ahead of the current track.
    static let smartShuffleSuggestionsAheadDefault = 20
    /// Valid range for how many suggestions to keep queued ahead.
    static let smartShuffleSuggestionsAheadRange = 5 ... 100

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Whether Smart Shuffle (the third shuffle state) is available from the shuffle button.
    var smartShuffleEnabled: Bool {
        didSet {
            self.defaults.set(self.smartShuffleEnabled, forKey: Keys.smartShuffleEnabled)
        }
    }

    /// Smart Shuffle interleave cadence: insert a burst of suggestions every N songs (1...6).
    var smartShuffleSuggestEveryN: Int {
        didSet {
            let clamped = Self.clamp(self.smartShuffleSuggestEveryN, to: Self.smartShuffleSuggestEveryNRange)
            if clamped != self.smartShuffleSuggestEveryN {
                self.smartShuffleSuggestEveryN = clamped
            }
            self.defaults.set(clamped, forKey: Keys.smartShuffleSuggestEveryN)
        }
    }

    /// Smart Shuffle burst: how many suggestions to insert at each slot (1...5).
    var smartShuffleBurst: Int {
        didSet {
            let clamped = Self.clamp(self.smartShuffleBurst, to: Self.smartShuffleBurstRange)
            if clamped != self.smartShuffleBurst {
                self.smartShuffleBurst = clamped
            }
            self.defaults.set(clamped, forKey: Keys.smartShuffleBurst)
        }
    }

    /// Smart Shuffle: how many suggestions to keep queued ahead of the current track (5...100).
    var smartShuffleSuggestionsAhead: Int {
        didSet {
            let clamped = Self.clamp(self.smartShuffleSuggestionsAhead, to: Self.smartShuffleSuggestionsAheadRange)
            if clamped != self.smartShuffleSuggestionsAhead {
                self.smartShuffleSuggestionsAhead = clamped
            }
            self.defaults.set(clamped, forKey: Keys.smartShuffleSuggestionsAhead)
        }
    }

    /// Whether the ambient color backdrop is shown on the YouTube watch page.
    /// Applies to regular YouTube videos only, not the Music experience.
    var ambientBackdropEnabled: Bool {
        didSet {
            self.defaults.set(self.ambientBackdropEnabled, forKey: Keys.ambientBackdropEnabled)
        }
    }

    /// The chosen ambient backdrop style when the feature is enabled.
    var ambientBackdropStyle: AmbientBackdropStyle {
        didSet {
            self.defaults.set(self.ambientBackdropStyle.rawValue, forKey: Keys.ambientBackdropStyle)
        }
    }

    /// Whether a playing YouTube video pops out into the floating window when
    /// the user navigates away from the inline watch view. When disabled,
    /// playback stops instead. Applies to regular YouTube videos only, not the
    /// Music experience.
    var popOutVideoOnNavigateAway: Bool {
        didSet {
            self.defaults.set(self.popOutVideoOnNavigateAway, forKey: Keys.popOutVideoOnNavigateAway)
        }
    }

    /// The style the YouTube watch page should request: the chosen style when
    /// enabled, `.off` when the feature is disabled. Runtime energy/accessibility
    /// downgrades are applied inside `AmbientVideoBackdrop`, which observes those
    /// external states directly.
    var resolvedAmbientStyle: AmbientBackdropStyle {
        Self.resolveAmbientStyle(
            enabled: self.ambientBackdropEnabled,
            preferredStyle: self.ambientBackdropStyle
        )
    }

    nonisolated static func resolveAmbientStyle(
        enabled: Bool,
        preferredStyle: AmbientBackdropStyle
    ) -> AmbientBackdropStyle {
        guard enabled, preferredStyle != .off else { return .off }
        return preferredStyle
    }

    /// The language used for the app interface and API content.
    var contentLanguage: ContentLanguage {
        didSet {
            self.defaults.set(self.contentLanguage.rawValue, forKey: Keys.contentLanguage)
            AppLocalization.setLanguage(self.contentLanguage.languageCode)
            APICache.shared.invalidateAll()
        }
    }

    #if DEBUG
        /// Debug-only switch that forces the app to render macOS 15 fallback UI on newer OS versions.
        var useLegacyMacOS15UI: Bool {
            didSet {
                self.defaults.set(self.useLegacyMacOS15UI, forKey: Keys.useLegacyMacOS15UI)
            }
        }
    #else
        /// Release builds always use the native UI for the host OS.
        let useLegacyMacOS15UI = false
    #endif

    // MARK: - Initialization

    static func loadKeepYouTubeVideoOnTop(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Keys.keepYouTubeVideoOnTop) as? Bool ?? false
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load persisted settings or use defaults
        self.showNowPlayingNotifications = defaults.object(forKey: Keys.showNowPlayingNotifications) as? Bool ?? true
        self.hapticFeedbackEnabled = defaults.object(forKey: Keys.hapticFeedbackEnabled) as? Bool ?? true
        self.rememberPlaybackSettings = defaults.object(forKey: Keys.rememberPlaybackSettings) as? Bool ?? false

        // Load per-service enabled flags, migrating from legacy lastFMEnabled if needed
        if let stored = defaults.dictionary(forKey: Keys.enabledServices) as? [String: Bool] {
            self.enabledServices = stored
        } else if let legacyEnabled = defaults.object(forKey: Keys.lastFMEnabled) as? Bool {
            // Migrate from single-service flag to dictionary
            self.enabledServices = ["Last.fm": legacyEnabled]
        } else {
            self.enabledServices = [:]
        }
        self.scrobblePercentThreshold = defaults.object(forKey: Keys.scrobblePercentThreshold) as? Double ?? 0.5
        self.scrobbleMinSeconds = defaults.object(forKey: Keys.scrobbleMinSeconds) as? Double ?? 240
        self.syncedLyricsEnabled = defaults.object(forKey: Keys.syncedLyricsEnabled) as? Bool ?? true
        self.romanizationEnabled = defaults.object(forKey: Keys.romanizationEnabled) as? Bool ?? true
        self.keepMiniPlayerOnTop = defaults.object(forKey: Keys.keepMiniPlayerOnTop) as? Bool ?? false
        self.keepYouTubeVideoOnTop = Self.loadKeepYouTubeVideoOnTop(from: defaults)
        self.smartShuffleEnabled = defaults.object(forKey: Keys.smartShuffleEnabled) as? Bool ?? true
        // Property observers do not fire for assignments in init, so clamp persisted values here too.
        self.smartShuffleSuggestEveryN = Self.clamp(
            defaults.object(forKey: Keys.smartShuffleSuggestEveryN) as? Int ?? Self.smartShuffleSuggestEveryNDefault,
            to: Self.smartShuffleSuggestEveryNRange
        )
        self.smartShuffleBurst = Self.clamp(
            defaults.object(forKey: Keys.smartShuffleBurst) as? Int ?? Self.smartShuffleBurstDefault,
            to: Self.smartShuffleBurstRange
        )
        self.smartShuffleSuggestionsAhead = Self.clamp(
            defaults.object(forKey: Keys.smartShuffleSuggestionsAhead) as? Int ?? Self.smartShuffleSuggestionsAheadDefault,
            to: Self.smartShuffleSuggestionsAheadRange
        )
        self.ambientBackdropEnabled = defaults.object(forKey: Keys.ambientBackdropEnabled) as? Bool ?? true
        self.popOutVideoOnNavigateAway = defaults.object(forKey: Keys.popOutVideoOnNavigateAway) as? Bool ?? true
        #if DEBUG
            self.useLegacyMacOS15UI = defaults.object(forKey: Keys.useLegacyMacOS15UI) as? Bool ?? false
        #endif

        if let rawValue = defaults.string(forKey: Keys.mediaControlStyle),
           let style = MediaControlStyle(rawValue: rawValue)
        {
            self.mediaControlStyle = style
        } else {
            self.mediaControlStyle = .nextPreviousTrack
        }

        if let rawValue = defaults.string(forKey: Keys.playbackAudioQuality),
           let quality = PlaybackAudioQuality(rawValue: rawValue)
        {
            self.playbackAudioQuality = quality
        } else {
            self.playbackAudioQuality = .auto
        }

        if let rawValue = defaults.string(forKey: Keys.ambientBackdropStyle),
           let style = AmbientBackdropStyle(rawValue: rawValue),
           style != .off
        {
            self.ambientBackdropStyle = style
        } else {
            self.ambientBackdropStyle = Self.defaultAmbientBackdropStyle
        }

        if let rawValue = defaults.string(forKey: Keys.defaultLaunchPage),
           let page = LaunchPage(rawValue: rawValue)
        {
            self.defaultLaunchPage = page
        } else {
            self.defaultLaunchPage = .home
        }

        if let rawValue = defaults.string(forKey: Keys.contentLanguage),
           let language = ContentLanguage(rawValue: rawValue)
        {
            self.contentLanguage = language
        } else {
            self.contentLanguage = .system
        }

        if let rawValue = defaults.string(forKey: Keys.sourceSwitchBehavior),
           let behavior = SourceSwitchBehavior(rawValue: rawValue)
        {
            self.sourceSwitchBehavior = behavior
        } else {
            self.sourceSwitchBehavior = .resume
        }

        if let rawValue = defaults.string(forKey: Keys.appSource),
           let source = AppSource(rawValue: rawValue),
           AppSource.visibleCases.contains(source)
        {
            self.appSource = source
        } else {
            self.appSource = .music
        }

        if let gain = defaults.object(forKey: Keys.spotifyVolumeGainOffset) as? Double {
            self.spotifyVolumeGainOffset = gain
        } else {
            self.spotifyVolumeGainOffset = 0.0
        }

        AppLocalization.setLanguage(self.contentLanguage.languageCode)

        // Persist migration from legacy lastFMEnabled key (must run after all properties initialized)
        if defaults.object(forKey: Keys.enabledServices) == nil,
           defaults.object(forKey: Keys.lastFMEnabled) != nil
        {
            defaults.set(self.enabledServices, forKey: Keys.enabledServices)
            defaults.removeObject(forKey: Keys.lastFMEnabled)
        }
    }

    // MARK: - Computed Properties

    /// Returns the page to navigate to on launch based on settings.
    var launchPage: LaunchPage {
        switch self.defaultLaunchPage {
        case .lastUsed:
            self.lastUsedPage
        default:
            self.defaultLaunchPage
        }
    }

    /// Returns the NavigationItem to use on app launch.
    var launchNavigationItem: NavigationItem {
        self.launchPage.navigationItem
    }

    /// Returns the linear volume gain multiplier for the given content source.
    func volumeGainMultiplier(for source: AppSource) -> Double {
        switch source {
        case .spotify:
            pow(10.0, self.spotifyVolumeGainOffset / 20.0)
        case .music, .video:
            1.0
        }
    }
}

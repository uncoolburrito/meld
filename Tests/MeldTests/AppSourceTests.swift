import Foundation
import Testing
@testable import Meld

/// Tests for the AppSource model and its SettingsManager persistence.
@Suite("AppSource", .serialized, .tags(.model))
@MainActor
struct AppSourceTests {
    @Test("Raw values round-trip")
    func rawValueRoundTrip() {
        for source in AppSource.allCases {
            #expect(AppSource(rawValue: source.rawValue) == source)
        }
    }

    @Test("Identifiers are unique")
    func identifiersUnique() {
        let ids = AppSource.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Display names and icons are non-empty")
    func displayNamesAndIcons() {
        for source in AppSource.allCases {
            #expect(!source.displayName.isEmpty)
            #expect(!source.icon.isEmpty)
        }
    }

    @Test("Music is the first segment in the toggle order")
    func musicIsFirst() {
        #expect(AppSource.allCases.first == .music)
    }

    @Test("SettingsManager persists appSource to UserDefaults")
    func settingsManagerPersistsAppSource() {
        let manager = SettingsManager.shared
        let original = manager.appSource
        defer {
            manager.appSource = original
        }

        manager.appSource = .video
        #expect(
            UserDefaults.standard.string(forKey: SettingsManager.Keys.appSource)
                == AppSource.video.rawValue
        )

        manager.appSource = .music
        #expect(
            UserDefaults.standard.string(forKey: SettingsManager.Keys.appSource)
                == AppSource.music.rawValue
        )
    }

    @Test("AppSource restoration falls back to .music for unknown or non-visible sources")
    func appSourceRestorationSafety() throws {
        let suiteName = "test-appSourceRestorationSafety-\(UUID().uuidString)"
        let isolatedDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            isolatedDefaults.removePersistentDomain(forName: suiteName)
        }

        // Unknown raw value fallback
        isolatedDefaults.set("unknown_service", forKey: SettingsManager.Keys.appSource)
        let managerUnknown = SettingsManager(defaults: isolatedDefaults)
        #expect(managerUnknown.appSource == .music)

        // Non-visible source fallback (.video is not in visibleCases)
        isolatedDefaults.set(AppSource.video.rawValue, forKey: SettingsManager.Keys.appSource)
        let managerVideo = SettingsManager(defaults: isolatedDefaults)
        #expect(managerVideo.appSource == .music)

        // Visible source restoration (.spotify is in visibleCases)
        isolatedDefaults.set(AppSource.spotify.rawValue, forKey: SettingsManager.Keys.appSource)
        let managerSpotify = SettingsManager(defaults: isolatedDefaults)
        #expect(managerSpotify.appSource == .spotify)

        // Default when key does not exist
        isolatedDefaults.removeObject(forKey: SettingsManager.Keys.appSource)
        let managerDefault = SettingsManager(defaults: isolatedDefaults)
        #expect(managerDefault.appSource == .music)
    }
}

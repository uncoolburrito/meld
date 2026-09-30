import Foundation
import Testing
@testable import Meld

// MARK: - Phase3ArbiterAndSourceManagerTests

@Suite("Phase 3 Arbiter and SourceManager", .serialized, .tags(.service))
@MainActor
struct Phase3ArbiterAndSourceManagerTests {
    private struct TestHarness {
        let playerService: PlayerService
        let youtubePlayerService: YouTubePlayerService
        let mockScript: MockSpotifyScriptController
        let mockMonitor: MockSpotifyNotificationMonitor
        let spotifySource: SpotifySource
        let arbiter: PlaybackArbiter
        let sourceManager: SourceManager
    }

    private func createHarness() -> TestHarness {
        let player = PlayerService()
        let webKit = WebKitManager.shared
        let youtubePlayer = YouTubePlayerService(webKitManager: webKit)
        let mockScript = MockSpotifyScriptController()
        let mockMonitor = MockSpotifyNotificationMonitor()
        let spotify = SpotifySource(
            scriptController: mockScript,
            notificationMonitor: mockMonitor,
            autoRefresh: false
        )
        let arbiter = PlaybackArbiter(
            playerService: player,
            youtubePlayerService: youtubePlayer,
            spotifySource: spotify
        )
        let youtubeMusic = YouTubeMusicSource(playerService: player)
        let sourceMgr = SourceManager(
            youtubeMusicSource: youtubeMusic,
            spotifySource: spotify,
            playbackArbiter: arbiter
        )

        return TestHarness(
            playerService: player,
            youtubePlayerService: youtubePlayer,
            mockScript: mockScript,
            mockMonitor: mockMonitor,
            spotifySource: spotify,
            arbiter: arbiter,
            sourceManager: sourceMgr
        )
    }

    // MARK: - Path A: External Spotify Playback Detection

    @Test("Path A: External Spotify start sets audioSource to .spotify but preserves selectedTab")
    func pathAExternalSpotifyPlaybackPreservesSelectedTab() {
        let harness = self.createHarness()
        defer {
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }

        harness.arbiter.setSelectedTab(.music)
        #expect(harness.arbiter.audioSource == .music)
        #expect(harness.arbiter.selectedTab == .music)
        #expect(harness.arbiter.spotifyPlayingExternallyCue == false)

        // Trigger Path A: external playback detected
        harness.arbiter.handleExternalSpotifyPlaybackDetected()

        #expect(harness.arbiter.audioSource == .spotify)
        #expect(harness.arbiter.selectedTab == .music)
        #expect(harness.arbiter.spotifyPlayingExternallyCue == true)
        #expect(harness.sourceManager.audioSource == .spotify)
        #expect(harness.sourceManager.selectedTab == .music)
        #expect(harness.sourceManager.spotifyPlayingExternallyCue == true)
    }

    // MARK: - Path B: Asymmetric Timeout Transition

    @Test("Path B: Transition to Spotify succeeds and updates both audioSource and selectedTab")
    func pathBTransitionToSpotifySucceeds() async {
        let harness = self.createHarness()
        defer {
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }

        harness.arbiter.setSelectedTab(.music)
        let success = await harness.sourceManager.requestTransition(to: .spotify)

        #expect(success == true)
        #expect(harness.arbiter.audioSource == .spotify)
        #expect(harness.arbiter.selectedTab == .spotify)
        #expect(harness.arbiter.spotifyPlayingExternallyCue == false)
        #expect(harness.arbiter.transitionAlert == nil)
    }

    @Test("Path B: Transition to Music succeeds when Spotify pauses cooperatively")
    func pathBTransitionToMusicSucceedsWhenSpotifyPauses() async {
        let harness = self.createHarness()
        defer {
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }

        _ = await harness.sourceManager.requestTransition(to: .spotify)
        #expect(harness.arbiter.audioSource == .spotify)

        // When Spotify pauses, it will enter paused state
        harness.mockScript.pauseCalled = false

        let success = await harness.sourceManager.requestTransition(to: .music)

        #expect(success == true)
        #expect(harness.mockScript.pauseCalled == true)
        #expect(harness.arbiter.audioSource == .music)
        #expect(harness.arbiter.selectedTab == .music)
        #expect(harness.arbiter.transitionAlert == nil)
    }

    // MARK: - Terms v10 AI Gating

    @Test("Terms v10 AI Gate fails closed when audioSource != .music")
    func termsV10AIGateFailsClosedWhenNotMusic() {
        if #available(macOS 26.0, *) {
            let aiService = FoundationModelsService.shared

            // When .music, gate is open (isAvailable follows normal model checks)
            aiService.currentAudioSource = .music
            #expect(aiService.currentAudioSource == .music)

            // When .spotify, gate fails closed
            aiService.currentAudioSource = .spotify
            #expect(aiService.currentAudioSource == .spotify)
            #expect(aiService.isAvailable == false)

            // When .video, gate fails closed
            aiService.currentAudioSource = .video
            #expect(aiService.currentAudioSource == .video)
            #expect(aiService.isAvailable == false)

            // Restore
            aiService.currentAudioSource = .music
        }
    }

    // MARK: - SourceManager Command Delegation & Volume Gain

    @Test("SourceManager delegates transport verbs to active source")
    func sourceManagerDelegatesToActiveSource() async throws {
        let harness = self.createHarness()
        defer {
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }

        _ = await harness.arbiter.requestTransition(to: .spotify)
        #expect(harness.sourceManager.audioSource == .spotify)

        try await harness.sourceManager.play()
        #expect(harness.mockScript.playCalled == true)

        try await harness.sourceManager.pause()
        #expect(harness.mockScript.pauseCalled == true)

        try await harness.sourceManager.toggle()
        #expect(harness.mockScript.toggleCalled == true)

        try await harness.sourceManager.next()
        #expect(harness.mockScript.nextCalled == true)

        try await harness.sourceManager.previous()
        #expect(harness.mockScript.previousCalled == true)

        try await harness.sourceManager.seek(to: 42.0)
        #expect(harness.mockScript.seekPosition == 42.0)
    }

    @Test("SettingsManager volume gain offset scales volume appropriately")
    func settingsManagerVolumeGainOffset() {
        let settings = SettingsManager.shared
        let originalOffset = settings.spotifyVolumeGainOffset
        defer {
            settings.spotifyVolumeGainOffset = originalOffset
        }

        settings.spotifyVolumeGainOffset = 0.0
        #expect(settings.volumeGainMultiplier(for: .spotify) == 1.0)
        #expect(settings.volumeGainMultiplier(for: .music) == 1.0)

        // +3.0 dB gain -> multiplier > 1.0
        settings.spotifyVolumeGainOffset = 3.0
        let gainMultiplier = settings.volumeGainMultiplier(for: .spotify)
        #expect(gainMultiplier > 1.0)

        // -6.0 dB gain -> multiplier < 1.0
        settings.spotifyVolumeGainOffset = -6.0
        let cutMultiplier = settings.volumeGainMultiplier(for: .spotify)
        #expect(cutMultiplier < 1.0)
    }

    // MARK: - Route Change & Remote Commands

    @Test("NowPlayingManager ignores route changes when audioSource is .spotify")
    func routeChangeIgnoredWhenSpotifyActive() async {
        let harness = self.createHarness()
        defer {
            NowPlayingManager.shared.handleAudioSourceChanged(to: .music)
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        NowPlayingManager.shared.configureArbiter(harness.arbiter)

        NowPlayingManager.shared.handleAudioSourceChanged(to: .spotify)
        #expect(harness.arbiter.audioSource == .music) // arbiter state wasn't changed by handleAudioSourceChanged alone

        _ = await harness.arbiter.requestTransition(to: .spotify)
        #expect(harness.arbiter.audioSource == .spotify)

        // Calling handleAudioSourceChanged for .spotify releases commands and claims
        NowPlayingManager.shared.handleAudioSourceChanged(to: .spotify)
    }
}

import Foundation
import MediaPlayer
import Testing
@testable import Meld

// MARK: - Phase3ArbiterAndSourceManagerTests

extension SingletonPlayerWebViewTestSuite {
    @Suite("Phase 3 Arbiter and SourceManager", .tags(.service))
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
        func pathAExternalSpotifyPlaybackPreservesSelectedTab() async {
            let harness = self.createHarness()
            defer {
                SingletonPlayerWebView.shared.unsuppressPlayback()
            }

            harness.arbiter.setSelectedTab(.music)
            #expect(harness.arbiter.audioSource == .music)
            #expect(harness.arbiter.selectedTab == .music)
            #expect(harness.arbiter.spotifyPlayingExternallyCue == false)

            // Make mock script report playing state
            harness.mockScript.snapshotToReturn = SpotifyPlaybackSnapshot(
                playerState: .playing,
                position: 10.0,
                duration: 180.0,
                volume: 0.8,
                track: nil
            )
            await harness.spotifySource.refreshState()
            #expect(harness.spotifySource.transportState == .playing)

            // Trigger Path A: external playback detected
            harness.arbiter.handleExternalSpotifyPlaybackDetected()

            #expect(harness.arbiter.audioSource == .spotify)
            #expect(harness.arbiter.selectedTab == .music)
            #expect(harness.arbiter.spotifyPlayingExternallyCue == true)
            #expect(harness.sourceManager.audioSource == .spotify)
            #expect(harness.sourceManager.selectedTab == .music)
            #expect(harness.sourceManager.spotifyPlayingExternallyCue == true)

            // When Spotify pauses, cue must clear even if audioSource is still .spotify
            harness.mockScript.snapshotToReturn = SpotifyPlaybackSnapshot(
                playerState: .paused,
                position: 10.0,
                duration: 180.0,
                volume: 0.8,
                track: nil
            )
            await harness.spotifySource.refreshState()
            #expect(harness.spotifySource.transportState == .paused)
            #expect(harness.arbiter.spotifyPlayingExternallyCue == false)
            #expect(harness.sourceManager.spotifyPlayingExternallyCue == false)
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

        @Test("Terms v10 AI Gate fails closed when audioSource == .spotify")
        func termsV10AIGateFailsClosedWhenSpotify() {
            guard #available(macOS 26.0, *) else { return }
            let aiService = FoundationModelsService.shared
            #if DEBUG
                aiService.injectedAvailability = .available
                defer { aiService.injectedAvailability = nil }
            #endif

            // When .music, gate is open
            aiService.currentAudioSource = .music
            #expect(aiService.currentAudioSource == .music)
            #expect(aiService.isTermsV10GateOpen == true)
            #if DEBUG
                #expect(aiService.isAvailable == true)
            #endif

            // When .video, gate is open (video is not Spotify)
            aiService.currentAudioSource = .video
            #expect(aiService.currentAudioSource == .video)
            #expect(aiService.isTermsV10GateOpen == true)
            #if DEBUG
                #expect(aiService.isAvailable == true)
            #endif

            // When .spotify, gate fails closed
            aiService.currentAudioSource = .spotify
            #expect(aiService.currentAudioSource == .spotify)
            #expect(aiService.isTermsV10GateOpen == false)
            #expect(aiService.isAvailable == false)

            // Restore
            aiService.currentAudioSource = .music
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
            NowPlayingManager.shared.configure(playerService: harness.playerService)
            let previousArbiter = NowPlayingManager.shared.playbackArbiter
            defer {
                NowPlayingManager.shared.configureArbiter(previousArbiter)
                NowPlayingManager.shared.handleAudioSourceChanged(to: .music)
                SingletonPlayerWebView.shared.unsuppressPlayback()
            }
            NowPlayingManager.shared.configureArbiter(harness.arbiter)

            _ = await harness.arbiter.requestTransition(to: .spotify)
            #expect(harness.arbiter.audioSource == .spotify)

            let commandCenter = MPRemoteCommandCenter.shared()
            #expect(commandCenter.playCommand.isEnabled == false)
            #expect(commandCenter.pauseCommand.isEnabled == false)

            // Trigger CoreAudio route change while Spotify is active
            AudioRouteObserver.shared.handleDefaultOutputDeviceChange()

            // Remote commands must remain disabled (keeping hands off Spotify)
            #expect(commandCenter.playCommand.isEnabled == false)
            #expect(commandCenter.pauseCommand.isEnabled == false)

            // Transition back to Music
            _ = await harness.arbiter.requestTransition(to: .music)
            #expect(harness.arbiter.audioSource == .music)
            #expect(commandCenter.playCommand.isEnabled == true)

            // If remote commands were disabled and a route change occurs while .music is active,
            // it must re-assert commands
            NowPlayingManager.shared.setRemoteCommandsEnabled(false)
            #expect(commandCenter.playCommand.isEnabled == false)
            AudioRouteObserver.shared.handleDefaultOutputDeviceChange()
            #expect(commandCenter.playCommand.isEnabled == true)
        }
    }
}

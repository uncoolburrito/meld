import Foundation
import MediaPlayer
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

    // MARK: - Keep Playing Mode (Default Behavior)

    @Test("Keep playing mode: toggle switches view only without pausing or changing audioSource")
    func keepPlayingModeToggleSwitchesViewOnly() async {
        let harness = self.createHarness()
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .keepPlaying

        // Start on Music with YTM playing
        harness.arbiter.setSelectedTab(.music)
        harness.playerService.state = .playing
        #expect(harness.arbiter.audioSource == .music)
        #expect(harness.arbiter.selectedTab == .music)
        #expect(harness.sourceManager.selectedSourceType == .music)
        #expect(harness.sourceManager.audibleSource == .music)

        // Toggle to Spotify
        let switched = await harness.sourceManager.requestTransition(to: .spotify)
        #expect(switched == true)

        // selectedTab updated, but audioSource and YTM playback are untouched!
        #expect(harness.arbiter.selectedTab == .spotify)
        #expect(harness.arbiter.audioSource == .music)
        #expect(harness.sourceManager.selectedSourceType == .spotify)
        #expect(harness.sourceManager.audibleSource == .music)
        #expect(harness.playerService.isPlaying == true)

        // PlayerBar follows selected tab (Spotify), while media keys/Now Playing follow audioSource (Music)
        #expect(harness.sourceManager.selectedSource is SpotifySource)
        #expect(harness.sourceManager.audibleEngine is YouTubeMusicSource)

        // Background cue dot appears on Music segment because Music is playing while on Spotify tab
        #expect(harness.arbiter.isPlayingInBackground(.music) == true)
        #expect(harness.arbiter.isPlayingInBackground(.spotify) == false)

        // Starting playback on Spotify triggers handoff
        harness.mockScript.snapshotToReturn = SpotifyPlaybackSnapshot(
            playerState: .playing,
            position: 12.0,
            duration: 210.0,
            volume: 0.85,
            track: nil
        )
        await harness.spotifySource.refreshState()
        harness.arbiter.handlePlaybackStarted(on: .spotify)
        harness.playerService.state = .paused

        // audioSource hands over to Spotify
        #expect(harness.arbiter.audioSource == .spotify)
        #expect(harness.sourceManager.audibleSource == .spotify)
        #expect(harness.arbiter.isPlayingInBackground(.music) == false)
        #expect(harness.arbiter.isPlayingInBackground(.spotify) == false)
    }

    @Test("Keep playing mode: generalized cue dot appears symmetrically")
    func keepPlayingCueDotAppearsSymmetrically() async {
        let harness = self.createHarness()
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .keepPlaying

        // 1. Music playing, on Spotify tab -> Music cue dot visible
        harness.arbiter.setSelectedTab(.spotify)
        harness.playerService.state = .playing
        #expect(harness.sourceManager.isPlayingInBackground(.music) == true)
        #expect(harness.sourceManager.isPlayingInBackground(.spotify) == false)

        // Switching back to Music clears cue dot
        _ = await harness.sourceManager.requestTransition(to: .music)
        #expect(harness.sourceManager.isPlayingInBackground(.music) == false)

        // 2. Spotify playing, on Music tab -> Spotify cue dot visible
        harness.mockScript.snapshotToReturn = SpotifyPlaybackSnapshot(
            playerState: .playing,
            position: 5.0,
            duration: 100.0,
            volume: 0.8,
            track: nil
        )
        await harness.spotifySource.refreshState()
        #expect(harness.sourceManager.isPlayingInBackground(.spotify) == true)
        #expect(harness.sourceManager.isPlayingInBackground(.music) == false)

        // Switching to Spotify tab clears cue dot
        _ = await harness.sourceManager.requestTransition(to: .spotify)
        #expect(harness.sourceManager.isPlayingInBackground(.spotify) == false)
    }

    // MARK: - Path B: Asymmetric Timeout Transition

    @Test("Path B: Transition to Spotify succeeds and updates both audioSource and selectedTab")
    func pathBTransitionToSpotifySucceeds() async {
        let harness = self.createHarness()
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .resume

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
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .resume

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

    // MARK: - Source Switch Behavior & Auto-Resume Tests

    @Test("Resume mode: toggling from playing source marks it and swaps playback")
    func resumeModeTogglingSwapsPlayback() async {
        let harness = self.createHarness()
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .resume

        // Start on Music with YTM playing
        harness.arbiter.setSelectedTab(.music)
        harness.playerService.state = .playing
        #expect(harness.arbiter.isSourcePlaying(.music) == true)

        // 1. Toggle to Spotify: YTM was playing, so it should be marked interrupted
        _ = await harness.arbiter.requestTransition(to: .spotify)
        #expect(harness.arbiter.audioSource == .spotify)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == true)
        #expect(harness.arbiter.isInterruptedByToggle(.spotify) == false)

        // Make Spotify simulate playing
        harness.mockScript.snapshotToReturn = SpotifyPlaybackSnapshot(
            playerState: .playing,
            position: 30.0,
            duration: 200.0,
            volume: 0.8,
            track: nil
        )
        await harness.spotifySource.refreshState()
        #expect(harness.arbiter.isSourcePlaying(.spotify) == true)

        // 2. Toggle back to Music: Spotify was playing, so Spotify should be marked interrupted,
        // and Music was marked interrupted, so Music's mark should be consumed/cleared
        _ = await harness.arbiter.requestTransition(to: .music)
        #expect(harness.arbiter.audioSource == .music)
        #expect(harness.arbiter.isInterruptedByToggle(.spotify) == true)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == false)

        // 3. Toggle back to Spotify again: Music was marked as paused in transition,
        // Spotify's mark is consumed and cleared
        _ = await harness.arbiter.requestTransition(to: .spotify)
        #expect(harness.arbiter.audioSource == .spotify)
        #expect(harness.arbiter.isInterruptedByToggle(.spotify) == false)
    }

    @Test("Pause-only mode: toggling never marks and never auto-resumes")
    func pauseOnlyModeNeverMarksOrAutoResumes() async {
        let harness = self.createHarness()
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .pauseOnly

        // Start on Music with YTM playing
        harness.arbiter.setSelectedTab(.music)
        harness.playerService.state = .playing

        // Toggle to Spotify
        _ = await harness.arbiter.requestTransition(to: .spotify)
        #expect(harness.arbiter.audioSource == .spotify)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == false)

        // Toggle back to Music
        _ = await harness.arbiter.requestTransition(to: .music)
        #expect(harness.arbiter.audioSource == .music)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == false)
        #expect(harness.arbiter.isInterruptedByToggle(.spotify) == false)
    }

    @Test("Toggling to an already-paused source stays silent")
    func alreadyPausedSourceStaysSilent() async {
        let harness = self.createHarness()
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .resume

        // Start with YTM paused (not playing)
        harness.arbiter.setSelectedTab(.music)
        harness.playerService.state = .paused
        #expect(harness.arbiter.isSourcePlaying(.music) == false)

        // Toggle to Spotify: YTM was not playing, so no mark
        _ = await harness.arbiter.requestTransition(to: .spotify)
        #expect(harness.arbiter.audioSource == .spotify)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == false)

        // Toggle back to Music: YTM was not marked, so it stays silent
        _ = await harness.arbiter.requestTransition(to: .music)
        #expect(harness.arbiter.audioSource == .music)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == false)
    }

    @Test("Manual transport commands clear interrupted marks")
    func manualTransportClearsInterruptedMarks() async {
        let harness = self.createHarness()
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .resume

        harness.playerService.state = .playing
        _ = await harness.arbiter.requestTransition(to: .spotify)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == true)

        // Manually clearing / manual pause on Music clears mark
        harness.arbiter.clearInterruptedMark(for: .music)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == false)

        // Transitioning back to Music does not resume it since mark was cleared
        _ = await harness.arbiter.requestTransition(to: .music)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == false)
    }

    @Test("Changing SourceSwitchBehavior setting clears all marks")
    func changingSettingClearsAllMarks() async {
        let harness = self.createHarness()
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        let previousArbiter = NowPlayingManager.shared.playbackArbiter
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            NowPlayingManager.shared.configureArbiter(previousArbiter)
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        NowPlayingManager.shared.configureArbiter(harness.arbiter)
        SettingsManager.shared.sourceSwitchBehavior = .resume

        harness.playerService.state = .playing
        _ = await harness.arbiter.requestTransition(to: .spotify)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == true)

        // Switching setting mid-session must clear all marks
        SettingsManager.shared.sourceSwitchBehavior = .pauseOnly
        #expect(harness.arbiter.isInterruptedByToggle(.music) == false)
    }

    @Test("Path A never marks anything")
    func pathANeverSetsMarks() {
        let harness = self.createHarness()
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .resume

        harness.arbiter.setSelectedTab(.music)
        harness.playerService.state = .playing

        // Trigger Path A
        harness.arbiter.handleExternalSpotifyPlaybackDetected()
        #expect(harness.arbiter.audioSource == .spotify)
        #expect(harness.arbiter.isInterruptedByToggle(.music) == false)
        #expect(harness.arbiter.isInterruptedByToggle(.spotify) == false)
    }

    // MARK: - Smooth Fade Tests

    @Test("Smooth fade: outgoing source fades out and restores original volume after pause")
    func smoothFadeOutgoingSourceRestoresVolume() async {
        let harness = self.createHarness()
        harness.arbiter.fadeStepDuration = 0.001
        defer {
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }

        // Set up Spotify playing at 0.75 volume
        _ = await harness.arbiter.requestTransition(to: .spotify)
        harness.mockScript.snapshotToReturn = SpotifyPlaybackSnapshot(
            playerState: .playing,
            position: 10.0,
            duration: 180.0,
            volume: 0.75,
            track: nil
        )
        await harness.spotifySource.refreshState()
        #expect(harness.spotifySource.volume == 0.75)

        // Transition to Music: Spotify should fade out, pause, and restore volume to 0.75
        let transitioned = await harness.arbiter.requestTransition(to: .music)
        #expect(transitioned == true)
        #expect(harness.mockScript.volumeSet == 0.75)
        #expect(harness.spotifySource.isFadingVolume == false)
    }

    @Test("Smooth fade: Spotify pause timeout presents non-blocking alert and restores volume")
    func pauseTimeoutPresentsNonBlockingAlertAndRestoresVolume() async {
        let harness = self.createHarness()
        harness.arbiter.fadeStepDuration = 0.001
        let previousBehavior = SettingsManager.shared.sourceSwitchBehavior
        defer {
            SettingsManager.shared.sourceSwitchBehavior = previousBehavior
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }
        SettingsManager.shared.sourceSwitchBehavior = .resume

        // Set up Spotify playing
        _ = await harness.arbiter.requestTransition(to: .spotify)
        harness.mockScript.snapshotToReturn = SpotifyPlaybackSnapshot(
            playerState: .playing,
            position: 10.0,
            duration: 180.0,
            volume: 0.65,
            track: nil
        )
        await harness.spotifySource.refreshState()
        #expect(harness.spotifySource.volume == 0.65)

        // Make pause fail/remain playing
        harness.mockScript.pauseKeepsPlaying = true
        harness.mockScript.snapshotToReturn = SpotifyPlaybackSnapshot(
            playerState: .playing,
            position: 10.0,
            duration: 180.0,
            volume: 0.65,
            track: nil
        )

        let transitioned = await harness.arbiter.requestTransition(to: .music)
        #expect(transitioned == true)
        #expect(harness.arbiter.transitionAlert != nil)
        // Volume must be restored even when pause timed out
        #expect(harness.mockScript.volumeSet == 0.65)
        #expect(harness.spotifySource.isFadingVolume == false)
    }

    @Test("Crash safety: pre-fade Spotify volume is persisted and restored on launch")
    func crashSafetyPreFadeVolumePersistedAndRestored() {
        let key = SettingsManager.Keys.spotifyPreFadeVolume
        defer {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // Simulate crash mid-fade by writing pre-fade volume to UserDefaults
        UserDefaults.standard.set(0.72, forKey: key)
        #expect(UserDefaults.standard.double(forKey: key) == 0.72)

        // Instantiate new SpotifySource (simulating app relaunch)
        let mockScript = MockSpotifyScriptController()
        let mockMonitor = MockSpotifyNotificationMonitor()
        let newSource = SpotifySource(
            scriptController: mockScript,
            notificationMonitor: mockMonitor,
            autoRefresh: false
        )

        // The key should have been cleared upon recovery
        #expect(UserDefaults.standard.object(forKey: key) == nil)
        _ = newSource
    }

    @Test("Handoff fade: playback start on Music fades out Spotify with perceptual curve")
    func handoffFadeOutSpotifyPerceptually() async {
        let harness = self.createHarness()
        harness.arbiter.crossfadeDuration = 0.005
        defer {
            SingletonPlayerWebView.shared.unsuppressPlayback()
        }

        // Spotify playing
        harness.arbiter.handlePlaybackStarted(on: .spotify)
        #expect(harness.arbiter.audioSource == .spotify)
        harness.mockScript.snapshotToReturn = SpotifyPlaybackSnapshot(
            playerState: .playing,
            position: 20.0,
            duration: 180.0,
            volume: 0.80,
            track: nil
        )
        await harness.spotifySource.refreshState()

        // Music starts playing
        harness.arbiter.handlePlaybackStarted(on: .music)
        #expect(harness.arbiter.audioSource == .music)

        // Let the background handoff Task finish
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Spotify volume should be restored to original volume after fade out and pause
        #expect(harness.mockScript.volumeSet == 0.80)
        #expect(harness.spotifySource.isFadingVolume == false)
    }
}

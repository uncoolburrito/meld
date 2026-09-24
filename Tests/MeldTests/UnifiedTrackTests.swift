import Foundation
import Testing
@testable import Meld

@Suite("UnifiedTrack model and source abstraction")
struct UnifiedTrackTests {
    @Test("Song initialization maps fields and preferred audio ID")
    func songInitialization() {
        let artist = Artist(id: "art-1", name: "Daft Punk")
        let album = Album(
            id: "alb-1",
            title: "Discovery",
            artists: [artist],
            thumbnailURL: nil,
            year: "2001",
            trackCount: 14
        )
        let song = Song(
            id: "s-1",
            title: "One More Time",
            artists: [artist],
            album: album,
            duration: 320,
            thumbnailURL: URL(string: "https://example.com/art.jpg"),
            videoId: "v-fallback",
            isPlayable: true,
            audioTrackVideoId: "v-audio"
        )

        let track = UnifiedTrack(from: song)

        #expect(track.id == "music:v-audio")
        #expect(track.title == "One More Time")
        #expect(track.artist == "Daft Punk")
        #expect(track.album == "Discovery")
        #expect(track.duration == 320)
        #expect(track.artworkURL == URL(string: "https://example.com/art.jpg"))
        #expect(track.source == .music)
        #expect(track.sourceID == "v-audio")
    }

    @Test("Custom initialization generates deterministic ID")
    func customInitialization() {
        let track = UnifiedTrack(
            title: "Starboy",
            artist: "The Weeknd",
            album: "Starboy",
            duration: 230,
            artworkURL: URL(string: "https://example.com/starboy.jpg"),
            source: .spotify,
            sourceID: "spotify:track:abc123xyz"
        )

        #expect(track.id == "spotify:spotify:track:abc123xyz")
        #expect(track.source == .spotify)
        #expect(track.sourceID == "spotify:track:abc123xyz")
    }

    @Test("Multiple artists format cleanly with comma separation")
    func multipleArtistsFormatting() {
        let artist1 = Artist(id: "art-1", name: "Queen")
        let artist2 = Artist(id: "art-2", name: "David Bowie")
        let song = Song(
            id: "s-2",
            title: "Under Pressure",
            artists: [artist1, artist2],
            album: nil,
            duration: 245,
            thumbnailURL: nil,
            videoId: "v-press",
            isPlayable: true
        )

        let track = UnifiedTrack(from: song)
        #expect(track.artist == "Queen, David Bowie")
        #expect(track.album == nil)
        #expect(track.sourceID == "v-press")
    }
}

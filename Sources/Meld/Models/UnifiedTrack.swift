import Foundation

/// A normalized representation of a playable track across all supported audio sources
/// (YouTube Music, Spotify, and YouTube Video).
///
/// `UnifiedTrack` decouples Meld's player bar, lyrics presentation, now-playing claims,
/// and scrobblers from source-specific data models (such as `Song` or raw AppleScript dictionaries).
struct UnifiedTrack: Identifiable, Hashable, Equatable, Sendable, Codable {
    /// Unique identifier across all sources, formatted as `"<source>:<sourceID>"`.
    let id: String

    /// The title of the track.
    let title: String

    /// The artist or primary performer.
    let artist: String

    /// The album name, if available.
    let album: String?

    /// Total duration in seconds, if known.
    let duration: TimeInterval?

    /// Remote or local URL to album artwork.
    let artworkURL: URL?

    /// Remote or local URL to artist imagery, if resolved.
    let artistImageURL: URL?

    /// The source that owns and plays this track.
    let source: AppSource

    /// The source-specific identifier (e.g., YouTube videoId or Spotify URI/ID).
    let sourceID: String

    init(
        id: String? = nil,
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval? = nil,
        artworkURL: URL? = nil,
        artistImageURL: URL? = nil,
        source: AppSource,
        sourceID: String
    ) {
        self.id = id ?? "\(source.rawValue):\(sourceID)"
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.artistImageURL = artistImageURL
        self.source = source
        self.sourceID = sourceID
    }

    /// Initializes a `UnifiedTrack` from a YouTube Music `Song` model.
    init(from song: Song, artistImageURL: URL? = nil) {
        let artistName = song.artists.map(\.name).joined(separator: ", ")
        self.init(
            title: song.title,
            artist: artistName.isEmpty ? String(localized: "Unknown Artist") : artistName,
            album: song.album?.title,
            duration: song.duration,
            artworkURL: song.thumbnailURL,
            artistImageURL: artistImageURL,
            source: .music,
            sourceID: song.preferredAudioVideoId
        )
    }
}

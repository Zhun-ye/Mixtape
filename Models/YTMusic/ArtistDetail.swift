import Foundation

// MARK: - AlbumSection

/// A section of albums with a localized title (e.g., "专辑", "单曲和迷你专辑").
struct AlbumSection: Sendable, Identifiable {
    let id = UUID()
    let title: String
    let albums: [Album]
    /// Browse endpoint for loading more albums (if available).
    let moreBrowseId: String?
    let moreParams: String?

    /// Whether more albums are available via the browse endpoint.
    var hasMore: Bool {
        moreBrowseId != nil
    }

    init(title: String, albums: [Album], moreBrowseId: String? = nil, moreParams: String? = nil) {
        self.title = title
        self.albums = albums
        self.moreBrowseId = moreBrowseId
        self.moreParams = moreParams
    }
}

// MARK: - ArtistDetail

/// Contains detailed artist information including their songs.
struct ArtistDetail: Sendable {
    let artist: Artist
    let description: String?
    let songs: [Song]
    /// Album sections with localized titles (Albums, Singles & EPs, etc.).
    let albumSections: [AlbumSection]
    /// Featured playlists from the artist page.
    let playlists: [Playlist]
    let thumbnailURL: URL?
    /// The channel ID for subscription operations (e.g., UCxxxxx).
    let channelId: String?
    /// Whether the user is subscribed to this artist.
    var isSubscribed: Bool
    /// Subscriber count text (e.g., "34.6M subscribers").
    let subscriberCount: String?
    /// Whether there are more songs available beyond what's loaded.
    let hasMoreSongs: Bool
    /// Browse ID for loading all songs (e.g., from "More songs" button).
    let songsBrowseId: String?
    /// Params for loading all songs.
    let songsParams: String?

    var id: String { self.artist.id }
    var name: String { self.artist.name }

    init(
        artist: Artist,
        description: String?,
        songs: [Song],
        albumSections: [AlbumSection] = [],
        playlists: [Playlist] = [],
        thumbnailURL: URL?,
        channelId: String? = nil,
        isSubscribed: Bool = false,
        subscriberCount: String? = nil,
        hasMoreSongs: Bool = false,
        songsBrowseId: String? = nil,
        songsParams: String? = nil
    ) {
        self.artist = artist
        self.description = description
        self.songs = songs
        self.albumSections = albumSections
        self.playlists = playlists
        self.thumbnailURL = thumbnailURL
        self.channelId = channelId
        self.isSubscribed = isSubscribed
        self.subscriberCount = subscriberCount
        self.hasMoreSongs = hasMoreSongs
        self.songsBrowseId = songsBrowseId
        self.songsParams = songsParams
    }
}

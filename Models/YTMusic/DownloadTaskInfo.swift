import Foundation

/// Tracks the state of an in-progress or queued download.
struct DownloadTaskInfo: Identifiable, Codable, Sendable {
    /// Unique identifier (videoId).
    let id: String

    /// Song metadata for display.
    let song: Song

    /// Current download state.
    var state: DownloadState

    /// Download progress (0.0–1.0).
    var progress: Double

    /// Error message if the download failed.
    var error: String?

    /// When this download was queued.
    var addedAt: Date

    enum DownloadState: String, Codable, Sendable {
        case pending
        case fetchingURL
        case downloading
        case completed
        case failed
        case paused
    }
}

/// A saved playlist/album associated with downloaded songs.
struct DownloadedPlaylist: Identifiable, Codable, Sendable {
    /// Playlist or album ID.
    let id: String

    /// Display title.
    let title: String

    /// Cover art URL.
    let thumbnailURL: URL?

    /// Author/artist name.
    let author: String?

    /// Whether this is an album (vs. a user playlist).
    let isAlbum: Bool

    /// Ordered song videoIds belonging to this playlist.
    var songIds: [String]

    /// When this playlist was saved for offline.
    let downloadedAt: Date
}

/// Persisted catalog of all downloads and pending tasks.
struct DownloadCatalog: Codable, Sendable {
    var downloads: [DownloadedSong]
    var pendingTasks: [DownloadTaskInfo]
    var playlists: [DownloadedPlaylist]

    static let empty = DownloadCatalog(downloads: [], pendingTasks: [], playlists: [])

    init(downloads: [DownloadedSong], pendingTasks: [DownloadTaskInfo], playlists: [DownloadedPlaylist]) {
        self.downloads = downloads
        self.pendingTasks = pendingTasks
        self.playlists = playlists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloads = try container.decode([DownloadedSong].self, forKey: .downloads)
        pendingTasks = try container.decode([DownloadTaskInfo].self, forKey: .pendingTasks)
        playlists = try container.decodeIfPresent([DownloadedPlaylist].self, forKey: .playlists) ?? []
    }
}

import Foundation

// MARK: - VideoType

/// Represents the type of music video content.
enum VideoType: String, Codable, Sendable {
    /// Audio Track Video - audio-only content with static/visualizer image
    case atv = "MUSIC_VIDEO_TYPE_ATV"
    /// Official Music Video
    case omv = "MUSIC_VIDEO_TYPE_OMV"
    /// User Generated Content
    case ugc = "MUSIC_VIDEO_TYPE_UGC"
}

// MARK: - Song

/// Represents a song/track.
struct Song: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let artists: [Artist]
    let album: Album?
    let duration: TimeInterval?
    let thumbnailURL: URL?
    let videoId: String
    let videoType: VideoType?

    /// Like/dislike status of the song (nil if unknown).
    var likeStatus: LikeStatus?

    /// Whether the song is in the user's library (nil if unknown).
    var isInLibrary: Bool?

    /// Feedback tokens for library add/remove operations.
    var feedbackTokens: FeedbackTokens?

    /// Whether this is a video (OMV or UGC) rather than audio-only (ATV).
    nonisolated var isVideo: Bool {
        guard let videoType else { return false }
        return videoType != .atv
    }

    /// Memberwise initializer with default values for mutable properties.
    init(
        id: String,
        title: String,
        artists: [Artist],
        album: Album? = nil,
        duration: TimeInterval? = nil,
        thumbnailURL: URL? = nil,
        videoId: String,
        videoType: VideoType? = nil,
        likeStatus: LikeStatus? = nil,
        isInLibrary: Bool? = nil,
        feedbackTokens: FeedbackTokens? = nil
    ) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.videoId = videoId
        self.videoType = videoType
        self.likeStatus = likeStatus
        self.isInLibrary = isInLibrary
        self.feedbackTokens = feedbackTokens
    }

    /// Display string for artists (comma-separated).
    nonisolated var artistsDisplay: String {
        self.artists.map(\.name).joined(separator: ", ")
    }

    /// Formatted duration string (e.g., "3:45").
    nonisolated var durationDisplay: String {
        guard let duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension Song {
    /// Creates a Song from API response data.
    init?(from data: [String: Any]) {
        guard let videoId = data["videoId"] as? String else { return nil }

        self.id = videoId
        self.videoId = videoId
        self.title = (data["title"] as? String) ?? "Unknown Title"

        // Parse artists
        if let artistsData = data["artists"] as? [[String: Any]] {
            self.artists = artistsData.compactMap { Artist(from: $0) }
        } else {
            self.artists = []
        }

        // Parse album
        if let albumData = data["album"] as? [String: Any] {
            self.album = Album(from: albumData)
        } else {
            self.album = nil
        }

        // Parse duration (in seconds)
        if let durationSeconds = data["duration_seconds"] as? Double {
            self.duration = durationSeconds
        } else if let durationString = data["duration"] as? String {
            self.duration = Song.parseDuration(durationString)
        } else {
            self.duration = nil
        }

        // Parse thumbnail
        if let thumbnails = data["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let urlString = lastThumbnail["url"] as? String
        {
            self.thumbnailURL = URL(string: urlString)
        } else {
            self.thumbnailURL = nil
        }

        // Parse video type
        if let videoTypeString = data["videoType"] as? String {
            self.videoType = VideoType(rawValue: videoTypeString)
        } else {
            self.videoType = nil
        }
    }

    /// Parses duration string like "3:45" to TimeInterval.
    private static func parseDuration(_ string: String) -> TimeInterval? {
        let components = string.split(separator: ":").compactMap { Int($0) }
        guard components.count >= 2 else { return nil }

        if components.count == 2 {
            return TimeInterval(components[0] * 60 + components[1])
        } else if components.count == 3 {
            return TimeInterval(components[0] * 3600 + components[1] * 60 + components[2])
        }
        return nil
    }
}

// MARK: - Equatable & Hashable

extension Song {
    static func == (lhs: Song, rhs: Song) -> Bool {
        // Compare by video ID for identity equality
        lhs.videoId == rhs.videoId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.videoId)
    }
}

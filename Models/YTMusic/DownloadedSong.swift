import Foundation

/// Metadata for a successfully downloaded song stored for offline playback.
/// The actual audio asset is managed by AVFoundation at a system-provided location.
struct DownloadedSong: Identifiable, Codable, Sendable {
    /// Unique identifier (videoId).
    let id: String

    /// Full song metadata for display and playback.
    let song: Song

    /// Relative path from home directory to the downloaded HLS asset bundle.
    /// Stored as relative path because absolute URLs are not stable across launches.
    let assetLocation: String

    /// Approximate file size in bytes (from contentLength).
    let fileSize: Int64

    /// When the download completed.
    let downloadedAt: Date

    /// Filename for the cached thumbnail (e.g., "{videoId}.jpg"), if available.
    let thumbnailFileName: String?
}

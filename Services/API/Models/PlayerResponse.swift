import Foundation

/// Response from the YouTube player endpoint containing stream URLs and video metadata.
struct PlayerResponse: Codable, Sendable {
    let playabilityStatus: PlayabilityStatus
    let playerConfig: PlayerConfig?
    let streamingData: StreamingData?
    let videoDetails: VideoDetails?
    let playbackTracking: PlaybackTracking?

    /// Whether the video is playable.
    var isPlayable: Bool {
        playabilityStatus.status == "OK"
    }

    /// Gets the best audio-only format (highest bitrate, AVPlayer-compatible).
    var bestAudioFormat: StreamingData.Format? {
        streamingData?.adaptiveFormats
            .filter { $0.isAudio && $0.url != nil && $0.isAVPlayerCompatible && $0.isOriginal }
            .max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
    }

    /// Gets all available audio formats sorted by quality (highest first).
    var audioFormats: [StreamingData.Format] {
        streamingData?.adaptiveFormats
            .filter { $0.isAudio && $0.url != nil }
            .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
            ?? []
    }

    /// Gets the best audio format for high quality playback.
    /// Uses itag-based selection for Premium formats (256kbps AAC).
    /// - Returns: The selected audio format (AAC only, as AVPlayer doesn't support Opus/WebM)
    func bestHighQualityFormat() -> StreamingData.Format? {
        // Filter for formats that have a URL and are original (non-dubbed) audio tracks
        let allFormats = streamingData?.adaptiveFormats
            .filter { $0.isAudio && $0.url != nil && $0.isOriginal }
            ?? []

        guard !allFormats.isEmpty else { return nil }

        // Priority: 141 (AAC 256kbps Premium) > 140 (AAC 128kbps) > highest bitrate
        let preferredItags = [141, 140]

        for itag in preferredItags {
            if let format = allFormats.first(where: { $0.itag == itag && $0.isAVPlayerCompatible }) {
                return format
            }
        }

        // Fallback: filter for AVPlayer compatible and return highest bitrate
        let compatible = allFormats.filter { $0.isAVPlayerCompatible }
        return compatible.max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
    }

    /// Gets the best audio format for VLC playback, preferring Opus for higher quality.
    /// Opus 251 (~160kbps) is perceptually similar to AAC 256kbps.
    func bestVLCFormat() -> StreamingData.Format? {
        let allFormats = streamingData?.adaptiveFormats
            .filter { $0.isAudio && $0.url != nil && $0.isOriginal }
            ?? []

        guard !allFormats.isEmpty else { return nil }

        // Priority: Opus 251 > AAC 141 > Opus 250 > AAC 140 > highest bitrate
        let preferredItags = [251, 141, 250, 140, 249]

        for itag in preferredItags {
            if let format = allFormats.first(where: { $0.itag == itag }) {
                return format
            }
        }

        return allFormats.max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
    }

    /// Gets all available audio formats including non-compatible ones (for debugging).
    var allAudioFormats: [StreamingData.Format] {
        streamingData?.adaptiveFormats
            .filter { $0.isAudio && $0.url != nil }
            .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
            ?? []
    }
}

// MARK: - PlayabilityStatus

extension PlayerResponse {
    struct PlayabilityStatus: Codable, Sendable {
        let status: String
        let reason: String?
        let playableInEmbed: Bool?
        let liveStreamability: LiveStreamability?

        var isLive: Bool {
            liveStreamability != nil
        }

        struct LiveStreamability: Codable, Sendable {
            let liveStreamabilityRenderer: LiveStreamabilityRenderer?

            struct LiveStreamabilityRenderer: Codable, Sendable {
                let videoId: String?
            }
        }
    }
}

// MARK: - PlayerConfig

extension PlayerResponse {
    struct PlayerConfig: Codable, Sendable {
        let audioConfig: AudioConfig?

        struct AudioConfig: Codable, Sendable {
            let loudnessDb: Double?
            let perceptualLoudnessDb: Double?
        }
    }
}

// MARK: - StreamingData

extension PlayerResponse {
    struct StreamingData: Codable, Sendable {
        let formats: [Format]?
        let adaptiveFormats: [Format]
        let expiresInSeconds: String?
        let hlsManifestUrl: String?
        let dashManifestUrl: String?

        /// Expiration time in seconds.
        var expiresIn: Int? {
            expiresInSeconds.flatMap { Int($0) }
        }

        struct Format: Codable, Sendable {
            let itag: Int
            let url: String?
            let mimeType: String
            let bitrate: Int?
            let width: Int?
            let height: Int?
            let contentLength: String?
            let quality: String?
            let fps: Int?
            let qualityLabel: String?
            let averageBitrate: Int?
            let audioQuality: String?
            let approxDurationMs: String?
            let audioSampleRate: String?
            let audioChannels: Int?
            let loudnessDb: Double?
            let lastModified: String?
            let signatureCipher: String?
            let audioTrack: AudioTrack?

            /// Whether this is an audio-only format.
            var isAudio: Bool {
                width == nil && height == nil
            }

            /// Whether this is a video format.
            var isVideo: Bool {
                width != nil && height != nil
            }

            /// Duration in milliseconds.
            var durationMs: Int? {
                approxDurationMs.flatMap { Int($0) }
            }

            /// Duration in seconds.
            var duration: TimeInterval? {
                durationMs.map { TimeInterval($0) / 1000.0 }
            }

            /// Content length in bytes.
            var contentLengthBytes: Int64? {
                contentLength.flatMap { Int64($0) }
            }

            /// Audio sample rate as integer.
            var sampleRate: Int? {
                audioSampleRate.flatMap { Int($0) }
            }

            /// Whether this format is compatible with AVPlayer.
            /// AVPlayer supports AAC (audio/mp4) but not Opus (audio/webm).
            var isAVPlayerCompatible: Bool {
                mimeType.hasPrefix("audio/mp4")
            }

            /// Whether this is an original (non-dubbed) audio track.
            /// YouTube can provide auto-dubbed versions; we prefer the original.
            var isOriginal: Bool {
                audioTrack?.audioIsDefault != false
            }

            struct AudioTrack: Codable, Sendable {
                let displayName: String?
                let id: String?
                let audioIsDefault: Bool?
            }
        }
    }
}

// MARK: - VideoDetails

extension PlayerResponse {
    struct VideoDetails: Codable, Sendable {
        let videoId: String
        let title: String?
        let author: String?
        let channelId: String?
        let lengthSeconds: String?
        let musicVideoType: String?
        let viewCount: String?
        let thumbnail: Thumbnails?
        let shortDescription: String?
        let isLiveContent: Bool?
        let isOwnerViewing: Bool?
        let isPrivate: Bool?

        /// Duration in seconds.
        var duration: TimeInterval? {
            lengthSeconds.flatMap { TimeInterval($0) }
        }

        /// View count as integer.
        var views: Int? {
            viewCount.flatMap { Int($0) }
        }

        struct Thumbnails: Codable, Sendable {
            let thumbnails: [Thumbnail]?

            struct Thumbnail: Codable, Sendable {
                let url: String
                let width: Int?
                let height: Int?
            }

            /// Best quality thumbnail URL.
            var bestURL: URL? {
                thumbnails?
                    .sorted { ($0.width ?? 0) * ($0.height ?? 0) > ($1.width ?? 0) * ($1.height ?? 0) }
                    .first
                    .flatMap { URL(string: $0.url) }
            }
        }
    }
}

// MARK: - PlaybackTracking

extension PlayerResponse {
    struct PlaybackTracking: Codable, Sendable {
        let videostatsPlaybackUrl: TrackingUrl?
        let videostatsWatchtimeUrl: TrackingUrl?
        let atrUrl: TrackingUrl?

        struct TrackingUrl: Codable, Sendable {
            let baseUrl: String?
        }
    }
}

// MARK: - Player Error

/// Error returned when player request fails.
struct PlayerError: Error, LocalizedError {
    let status: String
    let reason: String?

    var errorDescription: String? {
        reason ?? "Playback not available: \(status)"
    }
}

import Foundation
import os

/// Audio format information for display.
struct AudioFormatInfo: Sendable {
    let bitrate: Int
    let codec: String
    let sampleRate: Int?
    let channels: Int?
    let availableFormats: Int
    let qualityLabel: String?

    var bitrateDisplay: String {
        "\(bitrate / 1000)kbps"
    }

    var description: String {
        if availableFormats == 1 {
            return "\(codec) \(bitrateDisplay) (VBR)"
        }
        return "\(codec) \(bitrateDisplay)"
    }
}

/// Client configurations for stream fetching.
/// Uses youtube.com (not music.youtube.com) to get direct URLs without cipher.
struct StreamClient: Sendable {
    let name: String
    let version: String
    let clientId: String
    let userAgent: String
    let osName: String?
    let osVersion: String?
    let deviceMake: String?
    let deviceModel: String?
    let androidSdkVersion: String?

    func toContext(visitorData: String? = nil) -> [String: Any] {
        var client: [String: Any] = [
            "clientName": name,
            "clientVersion": version,
            "hl": Locale.current.language.languageCode?.identifier ?? "en",
            "gl": Locale.current.region?.identifier ?? "US",
        ]

        if let osName { client["osName"] = osName }
        if let osVersion { client["osVersion"] = osVersion }
        if let deviceMake { client["deviceMake"] = deviceMake }
        if let deviceModel { client["deviceModel"] = deviceModel }
        if let androidSdkVersion { client["androidSdkVersion"] = androidSdkVersion }
        if let visitorData { client["visitorData"] = visitorData }

        return [
            "client": client,
            "user": ["lockedSafetyMode": false],
        ]
    }

    /// ANDROID_VR client - most reliable for direct stream URLs.
    static let androidVR = StreamClient(
        name: "ANDROID_VR",
        version: "1.61.48",
        clientId: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32"
    )

    /// Android Music client.
    static let androidMusic = StreamClient(
        name: "ANDROID_MUSIC",
        version: "7.27.52",
        clientId: "21",
        userAgent: "com.google.android.apps.youtube.music/7.27.52 (Linux; U; Android 14; en_US; Pixel 8 Pro; Build/UD1A.230803.041; Cronet/114.0.5735.27)",
        osName: "Android",
        osVersion: "14",
        deviceMake: "Google",
        deviceModel: "Pixel 8 Pro",
        androidSdkVersion: "34"
    )

    /// iOS client as fallback.
    static let ios = StreamClient(
        name: "IOS",
        version: "20.10.4",
        clientId: "5",
        userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        osName: "iOS",
        osVersion: "18.3.2.22D82",
        deviceMake: "Apple",
        deviceModel: "iPhone16,2",
        androidSdkVersion: nil
    )

    /// TVHTML5 embedded player.
    static let tvhtml5 = StreamClient(
        name: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
        version: "2.0",
        clientId: "85",
        userAgent: "Mozilla/5.0 (PlayStation 4 5.55) AppleWebKit/601.2 (KHTML, like Gecko)",
        osName: nil,
        osVersion: nil,
        deviceMake: nil,
        deviceModel: nil,
        androidSdkVersion: nil
    )

    /// Clients to try in order.
    static let fallbackClients: [StreamClient] = [.androidVR, .androidMusic, .ios, .tvhtml5]
}

/// Result of a successful stream fetch.
struct StreamFetchResult: Sendable {
    let streamURL: URL
    let format: PlayerResponse.StreamingData.Format
    let client: StreamClient
    let audioFormats: [PlayerResponse.StreamingData.Format]
    let apiDuration: TimeInterval?
}

/// Handles fetching audio streams from YouTube.
@MainActor
final class StreamFetcher {
    // MARK: - Constants

    /// YouTube API base URL.
    private static let youtubeAPIBaseURL = "https://www.youtube.com/youtubei/v1"

    // MARK: - Properties

    private let logger = DiagnosticsLogger.player

    /// Cached visitor data for bot detection avoidance.
    private var visitorData: String?

    // MARK: - Public Methods

    /// Fetches the best available stream for a video.
    /// - Parameters:
    ///   - videoId: The YouTube video ID
    ///   - formatSelector: A closure that selects the best format from available options
    /// - Returns: StreamFetchResult with URL and metadata, or nil if all clients failed
    func fetchStream(
        videoId: String,
        formatSelector: (PlayerResponse) -> PlayerResponse.StreamingData.Format?
    ) async -> Result<StreamFetchResult, Error> {
        await BackgroundTaskHelper.withBackgroundTask {
            await self.performFetchStream(videoId: videoId, formatSelector: formatSelector)
        }
    }

    private func performFetchStream(
        videoId: String,
        formatSelector: (PlayerResponse) -> PlayerResponse.StreamingData.Format?
    ) async -> Result<StreamFetchResult, Error> {
        let visitorData = await fetchVisitorData()
        logger.info("[StreamFetcher] Using visitor data: \(visitorData != nil)")

        var lastError: Error?

        for (index, client) in StreamClient.fallbackClients.enumerated() {
            do {
                logger.info("[StreamFetcher] Trying client \(index + 1)/\(StreamClient.fallbackClients.count): \(client.name)")

                let playerResponse = try await fetchPlayerResponse(
                    videoId: videoId,
                    client: client,
                    visitorData: visitorData
                )

                let audioFormats = playerResponse.audioFormats
                logAudioFormats(audioFormats)

                guard let format = formatSelector(playerResponse),
                      let urlString = format.url,
                      let streamURL = URL(string: urlString)
                else {
                    logger.warning("[StreamFetcher] No suitable format found, trying next client...")
                    continue
                }

                let bitrateK = (format.bitrate ?? 0) / 1000
                let codec = Self.parseCodec(from: format.mimeType)
                logger.info("[StreamFetcher] Selected: itag=\(format.itag), \(codec) \(bitrateK)kbps")

                // Get duration from API
                let apiDuration: TimeInterval?
                if let formatDuration = format.duration {
                    apiDuration = formatDuration
                } else if let videoDuration = playerResponse.videoDetails?.duration {
                    apiDuration = videoDuration
                } else {
                    apiDuration = nil
                }

                return .success(StreamFetchResult(
                    streamURL: streamURL,
                    format: format,
                    client: client,
                    audioFormats: audioFormats,
                    apiDuration: apiDuration
                ))

            } catch {
                logger.warning("[StreamFetcher] Client \(client.name) failed: \(error.localizedDescription)")
                lastError = error
            }
        }

        return .failure(lastError ?? YTMusicError.apiError(message: "All clients failed", code: nil))
    }

    /// Creates AudioFormatInfo from a format and available formats count.
    func makeAudioFormatInfo(
        from format: PlayerResponse.StreamingData.Format,
        availableFormats: Int
    ) -> AudioFormatInfo {
        AudioFormatInfo(
            bitrate: format.bitrate ?? 0,
            codec: Self.parseCodec(from: format.mimeType),
            sampleRate: format.sampleRate,
            channels: format.audioChannels,
            availableFormats: availableFormats,
            qualityLabel: format.audioQuality
        )
    }

    /// Parses codec name from mimeType string.
    static func parseCodec(from mimeType: String) -> String {
        if mimeType.contains("opus") {
            return "Opus"
        } else if mimeType.contains("mp4a.40.2") {
            return "AAC"
        } else if mimeType.contains("mp4a.40.5") {
            return "AAC-HE"
        } else if mimeType.contains("mp4a") {
            return "AAC"
        } else if mimeType.contains("vorbis") {
            return "Vorbis"
        } else if mimeType.contains("webm") {
            return "WebM"
        } else if mimeType.contains("mp4") {
            return "M4A"
        }
        return "Audio"
    }

    // MARK: - HLS Manifest

    /// Fetches the HLS manifest URL for a video, trying clients in fallback order.
    /// Used by DownloadManager for `AVAssetDownloadURLSession`.
    /// - Returns: The HLS manifest URL and the client that provided it.
    func fetchHLSManifestURL(videoId: String) async -> Result<(URL, StreamClient), Error> {
        let visitorData = await fetchVisitorData()
        var lastError: Error?

        for client in StreamClient.fallbackClients {
            do {
                let playerResponse = try await fetchPlayerResponse(
                    videoId: videoId,
                    client: client,
                    visitorData: visitorData
                )

                guard let hlsURLString = playerResponse.streamingData?.hlsManifestUrl,
                      let hlsURL = URL(string: hlsURLString)
                else {
                    logger.info("[StreamFetcher] No HLS manifest from \(client.name), trying next")
                    continue
                }

                logger.info("[StreamFetcher] Got HLS manifest from \(client.name)")
                return .success((hlsURL, client))
            } catch {
                logger.warning("[StreamFetcher] HLS fetch failed for \(client.name): \(error.localizedDescription)")
                lastError = error
            }
        }

        return .failure(lastError ?? YTMusicError.apiError(message: "No HLS manifest available", code: nil))
    }

    // MARK: - Private Methods

    /// Fetches visitor data from YouTube for bot detection avoidance.
    private func fetchVisitorData() async -> String? {
        if let cached = visitorData {
            return cached
        }

        logger.info("[StreamFetcher] Fetching visitor data from YouTube")

        guard let url = URL(string: "https://music.youtube.com/sw.js_data") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard var text = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Remove the )]}' prefix if present
            if text.hasPrefix(")]}'") {
                text = String(text.dropFirst(4))
            }

            // Parse JSON and find visitor data (format: starts with "Cgt" or "Cgs")
            if let jsonData = text.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: jsonData) as? [Any] {
                let visitorData = findVisitorData(in: json)
                if let visitorData {
                    self.visitorData = visitorData
                    logger.info("[StreamFetcher] Got visitor data: \(visitorData.prefix(20))...")
                }
                return visitorData
            }
        } catch {
            logger.warning("[StreamFetcher] Failed to fetch visitor data: \(error.localizedDescription)")
        }
        return nil
    }

    /// Recursively searches for visitor data in JSON structure.
    private func findVisitorData(in value: Any) -> String? {
        if let string = value as? String {
            if string.hasPrefix("Cgt") || string.hasPrefix("Cgs") {
                return string
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let found = findVisitorData(in: item) {
                    return found
                }
            }
        } else if let dict = value as? [String: Any] {
            for (_, v) in dict {
                if let found = findVisitorData(in: v) {
                    return found
                }
            }
        }
        return nil
    }

    /// Fetches player response from YouTube API.
    private func fetchPlayerResponse(
        videoId: String,
        client: StreamClient,
        visitorData: String?
    ) async throws -> PlayerResponse {
        let urlString = "\(Self.youtubeAPIBaseURL)/player?prettyPrint=false"

        guard let url = URL(string: urlString) else {
            throw YTMusicError.apiError(message: "Invalid URL", code: nil)
        }

        let body: [String: Any] = [
            "videoId": videoId,
            "context": client.toContext(visitorData: visitorData),
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(client.clientId, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YTMusicError.apiError(message: "Invalid response", code: nil)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw YTMusicError.apiError(message: "HTTP \(httpResponse.statusCode)", code: httpResponse.statusCode)
        }

        let playerResponse = try JSONDecoder().decode(PlayerResponse.self, from: data)

        guard playerResponse.isPlayable else {
            throw PlayerError(
                status: playerResponse.playabilityStatus.status,
                reason: playerResponse.playabilityStatus.reason
            )
        }

        return playerResponse
    }

    /// Logs available audio formats for debugging.
    private func logAudioFormats(_ formats: [PlayerResponse.StreamingData.Format]) {
        logger.info("[StreamFetcher] Audio formats: total=\(formats.count)")
        for fmt in formats {
            let bitrate = (fmt.bitrate ?? 0) / 1000
            let codec = Self.parseCodec(from: fmt.mimeType)
            let quality = fmt.audioQuality ?? "?"
            let hasUrl = fmt.url != nil ? "URL" : "CIPHER"
            logger.info("  itag=\(fmt.itag) \(codec) \(bitrate)kbps \(quality) [\(hasUrl)]")
        }
    }
}

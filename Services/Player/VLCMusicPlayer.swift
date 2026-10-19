import Foundation
import MediaPlayer
import Network
import os
#if os(iOS)
import AVFoundation
import MobileVLCKit
#else
import VLCKit
#endif

/// VLC-based audio player for YouTube Music playback.
/// Supports opus and other formats that AVPlayer cannot handle.
@MainActor
final class VLCMusicPlayer: NSObject, YTMusicPlayer {
    // MARK: - YTMusicPlayer Callbacks

    var onPlaybackUpdate: ((_ isPlaying: Bool, _ currentTime: TimeInterval, _ duration: TimeInterval) -> Void)?
    var onTrackEnded: (() -> Void)?
    var onLikeStatusChanged: ((_ status: LikeStatus) -> Void)?
    var onError: ((_ error: Error) -> Void)?
    var onAudioQualityChanged: ((_ bitrateKbps: Int, _ codec: String) -> Void)?
    var onStateChange: ((_ state: PlayerManager.PlaybackState) -> Void)?

    // MARK: - Properties

    /// VLC media player instance.
    private var mediaPlayer: VLCMediaPlayer?

    /// Timer for playback updates.
    private var updateTimer: Timer?

    private let logger = DiagnosticsLogger.player

    /// Stream fetcher for YouTube API interaction.
    private let streamFetcher = StreamFetcher()

    /// The current video ID being played.
    private(set) var currentVideoId: String?

    /// The current stream URL (expires after ~6 hours).
    private var currentStreamURL: URL?

    /// When the stream URL was fetched (for expiration tracking).
    private var streamFetchTime: Date?

    /// Current audio format info.
    private(set) var currentAudioFormat: AudioFormatInfo?

    /// Stream expiration time (refresh after 5 hours).
    private let streamExpirationBuffer: TimeInterval = 5 * 60 * 60

    /// Network path monitor for detecting cellular vs WiFi.
    private let networkMonitor = NWPathMonitor()

    /// Whether currently on cellular network.
    private var isOnCellular: Bool = false

    /// Current volume level.
    private(set) var volume: Float = 1.0

    /// API-provided duration (more reliable than VLC for streams).
    private var apiDuration: TimeInterval?

    /// Last reported playback time (for glitch detection).
    private var lastPlaybackTime: TimeInterval = 0

    /// The client used to fetch the current stream.
    private var currentStreamClient: StreamClient?

    // MARK: - YTMusicPlayer State

    var isPlaying: Bool {
        mediaPlayer?.isPlaying ?? false
    }

    var audioFormatDescription: String? {
        currentAudioFormat?.description
    }

    // MARK: - Initialization

    override init() {
        super.init()
        setupMediaPlayer()
        setupRemoteCommandCenter()
        setupNetworkMonitor()
        logger.info("[Player: VLC] VLCMusicPlayer initialized")
    }

    private func setupMediaPlayer() {
        let options = [
            "--network-caching=15000",
            "--file-caching=15000",
            "--live-caching=15000",
            "--http-reconnect",
            "--no-video",
            "--no-osd",
        ]
        let player = VLCMediaPlayer(options: options)
        player.delegate = self
        mediaPlayer = player
        logger.info("[Player: VLC] Media player initialized with options: \(options)")
    }

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let isCellular = path.usesInterfaceType(.cellular)
            Task { @MainActor [weak self] in
                self?.isOnCellular = isCellular
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            if self?.isPlaying == true {
                self?.pause()
            } else {
                self?.play()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }

        logger.info("[Player: VLC] Remote command center configured")
    }

    // MARK: - Playback Update Timer

    private func startUpdateTimer() {
        stopUpdateTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendPlaybackUpdate()
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func sendPlaybackUpdate() {
        guard let player = mediaPlayer else { return }

        let currentTime = player.time.intValue > 0 ? TimeInterval(player.time.intValue) / 1000.0 : 0
        let duration: TimeInterval
        if let apiDur = apiDuration, apiDur > 0 {
            duration = apiDur
        } else if player.media?.length.intValue ?? 0 > 0 {
            duration = TimeInterval(player.media?.length.intValue ?? 0) / 1000.0
        } else {
            duration = 0
        }

        // Detect playback glitches (time jumps or stalls)
        // Skip detection if lastPlaybackTime is 0 (track just started) or if jump is > 5s (track change)
        if player.isPlaying, lastPlaybackTime > 0 {
            let timeDelta = currentTime - lastPlaybackTime
            if timeDelta < -1.0, timeDelta > -5.0 {
                // Small backwards jump (likely buffer issue, not track change)
                logger.warning("[Player: VLC] Glitch: time went backwards (\(self.lastPlaybackTime) -> \(currentTime))")
            } else if timeDelta > 2.0 {
                logger.warning("[Player: VLC] Glitch: time jump detected (\(String(format: "%.1f", timeDelta))s gap)")
            }
        }
        lastPlaybackTime = currentTime

        onPlaybackUpdate?(player.isPlaying, currentTime, duration)
    }

    // MARK: - Format Selection

    /// Selects the best format for VLC, preferring opus for higher quality.
    /// Opus itags: 251 (160kbps), 250 (70kbps), 249 (50kbps)
    /// AAC itags: 141 (256kbps Premium), 140 (128kbps)
    private func selectBestVLCFormat(from response: PlayerResponse) -> PlayerResponse.StreamingData.Format? {
        let allFormats = response.streamingData?.adaptiveFormats
            .filter { $0.isAudio && $0.url != nil && $0.isOriginal }
            ?? []

        guard !allFormats.isEmpty else { return nil }

        // Priority: Opus 251 > AAC 141 > Opus 250 > AAC 140 > highest bitrate
        // Opus 251 is ~160kbps but perceptually similar to AAC 256kbps
        let preferredItags = [251, 141, 250, 140, 249]

        for itag in preferredItags {
            if let format = allFormats.first(where: { $0.itag == itag }) {
                return format
            }
        }

        // Fallback: return highest bitrate
        return allFormats.max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
    }

    /// Loads and plays a local audio file (e.g., downloaded Opus).
    func loadLocalFile(_ fileURL: URL) {
        logger.info("[Player: VLC] Loading local file: \(fileURL.lastPathComponent)")
        currentVideoId = nil
        lastPlaybackTime = 0
        onStateChange?(.loading)

        let media = VLCMedia(url: fileURL)
        mediaPlayer?.media = media
        mediaPlayer?.play()

        startUpdateTimer()
        onStateChange?(.playing)
    }

    // MARK: - YTMusicPlayer

    func loadVideo(videoId: String) async {
        // Don't reload if same video and stream is valid
        if videoId == currentVideoId, mediaPlayer?.media != nil, !isStreamExpired() {
            logger.info("[Player: VLC] Video \(videoId) already loaded and stream valid")
            play()
            return
        }

        logger.info("[Player: VLC] Loading video: \(videoId)")
        currentVideoId = videoId
        lastPlaybackTime = 0
        onStateChange?(.loading)

        logger.info("[Player: VLC] Fetching stream...")
        let result = await streamFetcher.fetchStream(videoId: videoId) { [weak self] response in
            self?.selectBestVLCFormat(from: response)
        }
        logger.info("[Player: VLC] Stream fetch completed")

        switch result {
        case .success(let streamResult):
            currentStreamURL = streamResult.streamURL
            streamFetchTime = Date()
            currentStreamClient = streamResult.client

            currentAudioFormat = streamFetcher.makeAudioFormatInfo(
                from: streamResult.format,
                availableFormats: streamResult.audioFormats.count
            )
            apiDuration = streamResult.apiDuration

            let bitrateK = (streamResult.format.bitrate ?? 0) / 1000
            let codec = StreamFetcher.parseCodec(from: streamResult.format.mimeType)
            logger.info("[Player: VLC] Playing: \(codec) \(bitrateK)kbps (itag=\(streamResult.format.itag), client: \(streamResult.client.name))")
            onAudioQualityChanged?(bitrateK, codec)

            // Create VLC media with HTTP headers
            logger.info("[Player: VLC] Creating media with URL: \(streamResult.streamURL.absoluteString.prefix(100))...")
            let media = VLCMedia(url: streamResult.streamURL)
            media.addOption(":http-user-agent=\(streamResult.client.userAgent)")
            media.addOption(":http-referrer=https://www.youtube.com/")

            mediaPlayer?.media = media
            logger.info("[Player: VLC] Calling play()")
            mediaPlayer?.play()

            startUpdateTimer()
            onStateChange?(.playing)

        case .failure(let error):
            logger.error("[Player: VLC] All clients failed, skipping track. Error: \(error.localizedDescription)")
            onStateChange?(.error(error.localizedDescription))
            onError?(error)
            onTrackEnded?()
        }
    }

    func play() {
        logger.debug("[Player: VLC] play()")
        mediaPlayer?.play()
        startUpdateTimer()
        onStateChange?(.playing)
    }

    func pause() {
        logger.debug("[Player: VLC] pause()")
        mediaPlayer?.pause()
        stopUpdateTimer()
        onStateChange?(.paused)
    }

    func seek(to time: TimeInterval) {
        guard let player = mediaPlayer else {
            logger.warning("[Player: VLC] Cannot seek - no player")
            return
        }
        logger.debug("[Player: VLC] seek(to: \(time))")

        // VLC uses position (0.0-1.0) or time in milliseconds
        let duration = apiDuration ?? (TimeInterval(player.media?.length.intValue ?? 0) / 1000.0)
        if duration > 0 {
            player.position = Float(time / duration)
        }
    }

    func setVolume(_ volume: Float) {
        let clampedVolume = max(0, min(1, volume))
        self.volume = clampedVolume
        logger.debug("[Player: VLC] setVolume(\(clampedVolume))")
        mediaPlayer?.audio?.volume = Int32(clampedVolume * 100)
    }

    func stop() {
        logger.debug("[Player: VLC] stop()")

        stopUpdateTimer()
        mediaPlayer?.stop()

        currentVideoId = nil
        currentStreamURL = nil
        streamFetchTime = nil
        currentStreamClient = nil
        apiDuration = nil
        lastPlaybackTime = 0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next() {
        // Queue management handled by PlayerManager
    }

    func previous() {
        // Queue management handled by PlayerManager
    }

    // MARK: - Private Helpers

    private func isStreamExpired() -> Bool {
        guard let fetchTime = streamFetchTime else { return true }
        return Date().timeIntervalSince(fetchTime) > streamExpirationBuffer
    }
}

// MARK: - VLCMediaPlayerDelegate

extension VLCMusicPlayer: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleStateChanged()
        }
    }

    private func handleStateChanged() {
        guard let player = mediaPlayer else { return }

        switch player.state {
        case .stopped:
            logger.info("[Player: VLC] State: stopped")
            stopUpdateTimer()

        case .ended:
            logger.info("[Player: VLC] State: ended")
            stopUpdateTimer()
            onStateChange?(.ended)
            onTrackEnded?()

        case .error:
            logger.error("[Player: VLC] State: error")
            stopUpdateTimer()
            let error = NSError(domain: "VLCMusicPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "VLC playback error"])
            onStateChange?(.error(error.localizedDescription))
            onError?(error)
            onTrackEnded?()

        case .playing:
            logger.debug("[Player: VLC] State: playing")
            startUpdateTimer()
            onStateChange?(.playing)

        case .paused:
            // VLC reports .paused instead of .ended for streams - detect track completion
            let currentTime = player.time.intValue > 0 ? TimeInterval(player.time.intValue) / 1000.0 : 0
            let duration = apiDuration ?? (player.media?.length.intValue ?? 0 > 0 ? TimeInterval(player.media!.length.intValue) / 1000.0 : 0)

            // If we're within 1 second of the end, treat as track ended
            if duration > 0, currentTime >= duration - 1 {
                logger.info("[Player: VLC] State: paused at end (treating as ended)")
                stopUpdateTimer()
                onStateChange?(.ended)
                onTrackEnded?()
                return
            }

            logger.debug("[Player: VLC] State: paused")
            stopUpdateTimer()
            onStateChange?(.paused)

        case .buffering:
            onStateChange?(.buffering)

        case .opening:
            logger.debug("[Player: VLC] State: opening")
            onStateChange?(.loading)

        case .esAdded:
            logger.debug("[Player: VLC] State: esAdded (elementary stream added)")

        @unknown default:
            logger.debug("[Player: VLC] State: unknown (\(player.state.rawValue))")
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.sendPlaybackUpdate()
        }
    }

    nonisolated func mediaPlayerSnapshot(_ notification: Notification) {
        // Not used for audio
    }
}

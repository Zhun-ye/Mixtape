import AVFoundation
import Foundation
import MediaPlayer
import Network
import os
#if os(iOS)
import UIKit
#endif

/// Native audio player using AVPlayer for direct stream playback.
/// Replaces WebView-based playback with native InnerTube API streams.
@MainActor
final class YTMusicNativePlayer: YTMusicPlayer {
    // MARK: - YTMusicPlayer Callbacks

    var onPlaybackUpdate: ((_ isPlaying: Bool, _ currentTime: TimeInterval, _ duration: TimeInterval) -> Void)?
    var onTrackEnded: (() -> Void)?
    var onTrackMetadataChanged: ((_ title: String, _ artist: String, _ thumbnailUrl: String) -> Void)?
    var onLikeStatusChanged: ((_ status: LikeStatus) -> Void)?
    var onError: ((_ error: Error) -> Void)?
    var onAudioQualityChanged: ((_ bitrateKbps: Int, _ codec: String) -> Void)?
    var onStateChange: ((_ state: PlayerManager.PlaybackState) -> Void)?

    // MARK: - Properties

    /// Current playback session (encapsulates AVPlayer and observers).
    private var session: NativePlayerSession?

    private let logger = DiagnosticsLogger.player

    /// Stream fetcher for YouTube API interaction.
    private let streamFetcher = StreamFetcher()

    /// The current video ID being played.
    private(set) var currentVideoId: String?

    /// The current stream URL (expires after ~6 hours).
    private var currentStreamURL: URL?

    /// When the stream URL was fetched (for expiration tracking).
    private var streamFetchTime: Date?

    /// Current audio format info (bitrate, codec, etc.).
    private(set) var currentAudioFormat: AudioFormatInfo?

    /// Stream expiration time in seconds (default 6 hours, but we refresh early).
    private let streamExpirationBuffer: TimeInterval = 5 * 60 * 60 // Refresh after 5 hours

    /// Network path monitor for detecting cellular vs WiFi.
    private let networkMonitor = NWPathMonitor()

    /// Whether currently on cellular network.
    private var isOnCellular: Bool = false

    /// Current volume level.
    private(set) var volume: Float = 1.0

    /// The client that was used to fetch the current stream (for header matching).
    private var currentStreamClient: StreamClient?

    // MARK: - YTMusicPlayer State

    var isPlaying: Bool {
        session?.isPlaying ?? false
    }

    var audioFormatDescription: String? {
        currentAudioFormat?.description
    }

    // MARK: - Initialization

    init() {
        setupRemoteCommandCenter()
        setupNetworkMonitor()
        logger.info("[Player: Native] YTMusicNativePlayer initialized")
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

        self.logger.info("[Player: Native] Remote command center configured")
    }

    // MARK: - YTMusicPlayer

    func loadVideo(videoId: String) async {
        // Don't reload if same video
        if videoId == currentVideoId, session != nil, !isStreamExpired() {
            self.logger.info("[Player: Native] Video \(videoId) already loaded and stream valid")
            play()
            return
        }

        self.logger.info("[Player: Native] Loading video: \(videoId)")
        self.currentVideoId = videoId
        onStateChange?(.loading)

        let result = await streamFetcher.fetchStream(videoId: videoId) { response in
            response.bestHighQualityFormat()
        }

        switch result {
        case .success(let streamResult):
            self.currentStreamURL = streamResult.streamURL
            self.streamFetchTime = Date()
            self.currentStreamClient = streamResult.client

            self.currentAudioFormat = streamFetcher.makeAudioFormatInfo(
                from: streamResult.format,
                availableFormats: streamResult.audioFormats.count
            )

            let bitrateKbps = (streamResult.format.bitrate ?? 0) / 1000
            let codec = StreamFetcher.parseCodec(from: streamResult.format.mimeType)
            onAudioQualityChanged?(bitrateKbps, codec)

            self.logger.info("[Player: Native] Playing: \(codec) \(bitrateKbps)kbps (itag=\(streamResult.format.itag), client: \(streamResult.client.name))")

            // Create headers matching the client
            let headers: [String: String] = [
                "User-Agent": streamResult.client.userAgent,
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/",
            ]

            // Create new session (replaces old one)
            let newSession = NativePlayerSession(
                url: streamResult.streamURL,
                headers: headers,
                apiDuration: streamResult.apiDuration
            )
            self.session = newSession

            // Wire up session callbacks
            newSession.onTimeUpdate = { [weak self] currentTime, duration, isPlaying in
                self?.onPlaybackUpdate?(isPlaying, currentTime, duration)
            }

            newSession.onTrackEnded = { [weak self] in
                self?.logger.info("[Player: Native] Session reported track ended")
                self?.onStateChange?(.ended)
                self?.onTrackEnded?()
            }

            newSession.onError = { [weak self] error in
                guard let self else { return }
                self.logger.warning("[Player: Native] Playback error occurred, skipping to next track")
                self.onStateChange?(.error(error.localizedDescription))
                self.onError?(error)
                // Auto-skip to next track when playback fails
                self.onTrackEnded?()
            }

            // Set volume and start playback
            newSession.volume = volume
            newSession.play()
            onStateChange?(.playing)

        case .failure(let error):
            self.logger.error("[Player: Native] All clients failed, skipping track. Error: \(error.localizedDescription)")
            onStateChange?(.ended)
            onTrackEnded?()
        }
    }

    /// Loads and plays a pre-downloaded HLS asset for offline playback.
    func loadAsset(_ asset: AVURLAsset) async {
        self.logger.info("[Player: Native] Loading offline asset")
        onStateChange?(.loading)

        let newSession = NativePlayerSession(asset: asset)
        self.session = newSession

        newSession.onTimeUpdate = { [weak self] currentTime, duration, isPlaying in
            self?.onPlaybackUpdate?(isPlaying, currentTime, duration)
        }

        newSession.onTrackEnded = { [weak self] in
            self?.logger.info("[Player: Native] Offline session track ended")
            self?.onStateChange?(.ended)
            self?.onTrackEnded?()
        }

        newSession.onError = { [weak self] error in
            guard let self else { return }
            self.logger.warning("[Player: Native] Offline playback error: \(error.localizedDescription)")
            self.onStateChange?(.error(error.localizedDescription))
            self.onError?(error)
            self.onTrackEnded?()
        }

        newSession.volume = volume
        newSession.play()
        onStateChange?(.playing)
    }

    func play() {
        self.logger.debug("[Player: Native] play()")
        session?.play()
        onStateChange?(.playing)
    }

    func pause() {
        self.logger.debug("[Player: Native] pause()")
        session?.pause()
        onStateChange?(.paused)
    }

    func seek(to time: TimeInterval) {
        guard let session = session else {
            self.logger.warning("[Player: Native] Cannot seek - no session")
            return
        }
        self.logger.debug("[Player: Native] seek(to: \(time))")
        session.seek(to: time)
    }

    func setVolume(_ volume: Float) {
        let clampedVolume = max(0, min(1, volume))
        self.volume = clampedVolume
        self.logger.debug("[Player: Native] setVolume(\(clampedVolume))")
        session?.volume = clampedVolume
    }

    func stop() {
        self.logger.debug("[Player: Native] stop()")

        // Session cleanup is handled by its deinit
        session = nil

        currentVideoId = nil
        currentStreamURL = nil
        streamFetchTime = nil
        currentStreamClient = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next() {
        // Native player doesn't support next/previous directly
        // Queue management is handled by PlayerManager
    }

    func previous() {
        // Native player doesn't support next/previous directly
        // Queue management is handled by PlayerManager
    }

    // MARK: - Private Helpers

    /// Checks if the current stream URL has expired.
    private func isStreamExpired() -> Bool {
        guard let fetchTime = streamFetchTime else { return true }
        return Date().timeIntervalSince(fetchTime) > streamExpirationBuffer
    }

    /// Refreshes the stream URL if expired.
    private func refreshStreamIfNeeded() async {
        guard let videoId = currentVideoId, isStreamExpired() else { return }

        self.logger.info("[Player: Native] Refreshing expired stream for \(videoId)")

        // Save current position
        let savedPosition = session?.currentTime ?? 0

        // Reload video (creates new session)
        await loadVideo(videoId: videoId)

        // Seek to saved position
        if savedPosition > 0 {
            session?.seek(to: savedPosition)
        }

        self.logger.info("[Player: Native] Stream refreshed, resumed at \(savedPosition)s")
    }
}

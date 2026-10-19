import Foundation
import os

// MARK: - YTMusicWebPlayer

/// Audio player that uses WebView-based playback via YouTube Music.
/// Wraps `SingletonPlayerWebView` and translates its callbacks to the `YTMusicPlayer` protocol.
@MainActor
final class YTMusicWebPlayer: YTMusicPlayer {
    // MARK: - YTMusicPlayer Callbacks

    var onPlaybackUpdate: ((_ isPlaying: Bool, _ currentTime: TimeInterval, _ duration: TimeInterval) -> Void)?
    var onTrackEnded: (() -> Void)?
    var onTrackMetadataChanged: ((_ title: String, _ artist: String, _ thumbnailUrl: String) -> Void)?
    var onLikeStatusChanged: ((_ status: LikeStatus) -> Void)?
    var onError: ((_ error: Error) -> Void)?
    var onAudioQualityChanged: ((_ bitrateKbps: Int, _ codec: String) -> Void)?
    var onStateChange: ((_ state: PlayerManager.PlaybackState) -> Void)?

    // MARK: - State

    private(set) var isPlaying: Bool = false
    private(set) var volume: Float = 1.0

    /// Audio format description (bitrate and codec from WebView observation).
    private(set) var audioFormatDescription: String?

    /// Current audio bitrate in kbps.
    private(set) var audioBitrateKbps: Int = 0

    /// Current audio codec.
    private(set) var audioCodec: String = ""

    private let logger = DiagnosticsLogger.player

    // MARK: - Initialization

    init() {
        // Register as observer for SingletonPlayerWebView updates
        SingletonPlayerWebView.shared.audioPlayerObserver = self
        logger.info("YTMusicWebPlayer initialized")
    }

    // MARK: - YTMusicPlayer

    func loadVideo(videoId: String) async {
        logger.info("[Player: Web] Loading video: \(videoId)")
        SingletonPlayerWebView.shared.loadVideo(videoId: videoId)
    }

    func play() {
        logger.debug("[Player: Web] play()")
        SingletonPlayerWebView.shared.play()
    }

    func pause() {
        logger.debug("[Player: Web] pause()")
        SingletonPlayerWebView.shared.pause()
    }

    func seek(to time: TimeInterval) {
        logger.debug("[Player: Web] seek(to: \(time))")
        SingletonPlayerWebView.shared.seek(to: time)
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        logger.debug("[Player: Web] setVolume(\(volume))")
        SingletonPlayerWebView.shared.setVolume(Double(volume))
    }

    func stop() {
        logger.debug("[Player: Web] stop()")
        SingletonPlayerWebView.shared.pause()
    }

    func next() {
        logger.debug("[Player: Web] next()")
        SingletonPlayerWebView.shared.next()
    }

    func previous() {
        logger.debug("[Player: Web] previous()")
        SingletonPlayerWebView.shared.previous()
    }

}

// MARK: - SingletonPlayerWebViewObserver

extension YTMusicWebPlayer: SingletonPlayerWebViewObserver {
    func webViewDidUpdatePlaybackState(isPlaying: Bool, progress: TimeInterval, duration: TimeInterval) {
        let wasPlaying = self.isPlaying
        self.isPlaying = isPlaying
        onPlaybackUpdate?(isPlaying, progress, duration)

        // Report state change when playing/paused state changes
        if isPlaying != wasPlaying {
            onStateChange?(isPlaying ? .playing : .paused)
        }
    }

    func webViewDidUpdateTrackMetadata(title: String, artist: String, thumbnailUrl: String) {
        onTrackMetadataChanged?(title, artist, thumbnailUrl)
    }

    func webViewDidUpdateLikeStatus(_ status: LikeStatus) {
        onLikeStatusChanged?(status)
    }

    func webViewDidUpdateAudioQuality(bitrateKbps: Int, codec: String) {
        self.audioBitrateKbps = bitrateKbps
        self.audioCodec = codec
        if bitrateKbps > 0 {
            self.audioFormatDescription = "\(codec) \(bitrateKbps)kbps"
        } else {
            self.audioFormatDescription = codec
        }
        onAudioQualityChanged?(bitrateKbps, codec)
    }

    func webViewDidEncounterError(_ error: Error) {
        onStateChange?(.error(error.localizedDescription))
        onError?(error)
    }

    func webViewTrackDidEnd() {
        onStateChange?(.ended)
        onTrackEnded?()
    }
}

import Foundation

// MARK: - YTMusicPlayer

/// Protocol defining a unified interface for YouTube Music playback.
/// Enables swapping between WebView-based playback and native AVPlayer.
/// Sendable because all access is MainActor-isolated.
@MainActor
protocol YTMusicPlayer: AnyObject, Sendable {
    // MARK: - Callbacks

    /// Called when playback state updates (isPlaying, currentTime, duration).
    var onPlaybackUpdate: ((_ isPlaying: Bool, _ currentTime: TimeInterval, _ duration: TimeInterval) -> Void)? { get set }

    /// Called when the current track ends.
    var onTrackEnded: (() -> Void)? { get set }

    /// Called when like status is detected (from WebView observation).
    var onLikeStatusChanged: ((_ status: LikeStatus) -> Void)? { get set }

    /// Called when an error occurs.
    var onError: ((_ error: Error) -> Void)? { get set }

    /// Called when audio quality info is available (bitrateKbps, codec).
    var onAudioQualityChanged: ((_ bitrateKbps: Int, _ codec: String) -> Void)? { get set }

    /// Called when playback state changes (loading, playing, paused, etc.).
    var onStateChange: ((_ state: PlayerManager.PlaybackState) -> Void)? { get set }

    // MARK: - State

    /// Whether audio is currently playing.
    var isPlaying: Bool { get }

    /// Current volume (0.0 - 1.0).
    var volume: Float { get }

    /// Description of current audio format (e.g., "AAC 256kbps").
    var audioFormatDescription: String? { get }

    // MARK: - Playback Control

    /// Loads and plays a video by ID.
    func loadVideo(videoId: String) async

    /// Resumes playback.
    func play()

    /// Pauses playback.
    func pause()

    /// Seeks to a specific time in seconds.
    func seek(to time: TimeInterval)

    /// Sets the volume (0.0 - 1.0).
    func setVolume(_ volume: Float)

    /// Stops playback and clears state.
    func stop()

    /// Skips to the next track
    func next()

    /// Goes to the previous track
    func previous()
}

// MARK: - Default Implementations

extension YTMusicPlayer {
    /// Default no-op for players that don't support next/previous.
    func next() {}
    func previous() {}
}

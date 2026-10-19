import FactoryKit
import Foundation
import Kingfisher
import MediaPlayer
import Observation
import os
#if os(macOS)
import AppKit
#else
import UIKit
import AVFoundation
#endif

// MARK: - PlayerManager

/// Controls music playback via a hidden WKWebView.
@MainActor
@Observable
final class PlayerManager: NSObject, PlayerManagerProtocol {

    // MARK: - Observable State

    /// Current playback state.
    private(set) var state: PlaybackState = .idle

    /// Currently playing track (native).
    private(set) var currentTrack: Song?

    /// User's playback intent (false = wants to play, true = wants to pause).
    private(set) var isPaused: Bool = true

    /// Whether we're transitioning between tracks (loading a new track).
    /// Used to ignore spurious .paused states from WebView during track changes.
    private var isTransitioningTrack: Bool = false

    /// Whether playback is active (based on user intent).
    var isPlaying: Bool { !isPaused }

    /// Current playback position in seconds.
    private(set) var progress: TimeInterval = 0

    /// Total duration of current track in seconds.
    private(set) var duration: TimeInterval = 0

    /// Current volume (0.0 - 1.0).
    private(set) var volume: Double = 1.0

    /// Volume before muting, for unmute restoration.
    private var volumeBeforeMute: Double = 1.0

    /// Whether audio is currently muted.
    var isMuted: Bool { self.volume == 0 }

    /// Whether shuffle mode is enabled.
    private(set) var shuffleEnabled: Bool = false

    /// Current repeat mode.
    private(set) var repeatMode: RepeatMode = .off

    /// Playback queue.
    private(set) var queue: [Song] = []
    /// Index of current track in queue.
    private(set) var currentIndex: Int = 0 {
        didSet {
            // Prefetch images when current track changes (sliding window)
            if currentIndex != oldValue {
                prefetchQueueImages()
            }
        }
    }

    /// Source playlist for the current queue (if playing from a playlist).
    private(set) var sourcePlaylist: Playlist?

    /// Whether the mini player should be shown (user needs to interact to start playback).
    var showMiniPlayer: Bool = false

    /// The video ID that needs to be played in the mini player.
    private(set) var pendingPlayVideoId: String?

    /// Whether the user has successfully interacted at least once this session.
    /// After first successful playback, we can auto-play without showing the popup.
    private(set) var hasUserInteractedThisSession: Bool = false

    /// Like status of the current track.
    private(set) var currentTrackLikeStatus: LikeStatus = .indifferent

    /// Whether the current track is in the user's library.
    private(set) var currentTrackInLibrary: Bool = false

    /// Current audio bitrate in kbps (0 if unknown).
    private(set) var audioBitrateKbps: Int = 0

    /// Current audio codec (e.g., "audio/webm; codecs=\"opus\"").
    private(set) var audioCodec: String = ""

    /// Whether the current track is playing from a local offline download.
    private(set) var isPlayingOffline: Bool = false

    /// Track info reported by the WebView player.
    private(set) var currentWebTrack: Song?

    /// Cached artwork for the current track (for Now Playing info).
    private var currentArtwork: MPMediaItemArtwork?

    /// Feedback tokens for the current track (used for library add/remove).
    private(set) var currentTrackFeedbackTokens: FeedbackTokens?

    /// Whether the lyrics panel is visible.
    var showLyrics: Bool = false {
        didSet {
            // Mutual exclusivity: opening lyrics closes queue
            if self.showLyrics, self.showQueue {
                self.showQueue = false
            }
        }
    }

    /// Whether the queue panel is visible.
    var showQueue: Bool = false {
        didSet {
            // Mutual exclusivity: opening queue closes lyrics
            if self.showQueue, self.showLyrics {
                self.showLyrics = false
            }
        }
    }

    // MARK: - Seek State

    /// Normalized seek value (0-1) for slider binding.
    private(set) var seekValue: Double = 0

    /// The seek position in seconds while seeking (prevents UI jumping).
    private(set) var seekingProgress: Double?

    /// Progress value for display - returns seek position while seeking.
    var displayProgress: Double {
        seekingProgress ?? progress
    }

    // MARK: - Private Properties

    private let logger = DiagnosticsLogger.player
    private let ytMusicClient: any YTMusicClientProtocol

    /// The audio player (WebView or native AVPlayer).
    private var audioPlayer: YTMusicPlayer?

    /// UserDefaults key for persisting volume.
    private static let volumeKey = "playerVolume"
    /// UserDefaults key for persisting volume before mute.
    private static let volumeBeforeMuteKey = "playerVolumeBeforeMute"
    /// UserDefaults key for persisting shuffle state.
    private static let shuffleKey = "playerShuffle"
    /// UserDefaults key for persisting repeat mode.
    private static let repeatKey = "playerRepeat"


    // MARK: - Initialization

    init(ytMusicClient: any YTMusicClientProtocol) {
        self.ytMusicClient = ytMusicClient
        super.init()
        // Restore saved volume from UserDefaults
        if UserDefaults.standard.object(forKey: Self.volumeKey) != nil {
            let savedVolume = UserDefaults.standard.double(forKey: Self.volumeKey)
            self.volume = max(0, min(1, savedVolume))
            self.logger.info("Restored saved volume: \(self.volume)")
        }
        // Restore volumeBeforeMute for proper unmute behavior
        if UserDefaults.standard.object(forKey: Self.volumeBeforeMuteKey) != nil {
            let savedVolumeBeforeMute = UserDefaults.standard.double(forKey: Self.volumeBeforeMuteKey)
            self.volumeBeforeMute = savedVolumeBeforeMute > 0 ? savedVolumeBeforeMute : 1.0
            self.logger.info("Restored volumeBeforeMute: \(self.volumeBeforeMute)")
        } else {
            self.volumeBeforeMute = self.volume > 0 ? self.volume : 1.0
        }

        // Restore shuffle/repeat state
        self.shuffleEnabled = UserDefaults.standard.bool(forKey: Self.shuffleKey)
        if let repeatRaw = UserDefaults.standard.object(forKey: Self.repeatKey) as? Int,
           let mode = RepeatMode(rawValue: repeatRaw) {
            self.repeatMode = mode
        }

        // Restore saved queue and current track (without auto-playing)
        self.restoreQueueState()

        // Configure audio session for iOS
        #if os(iOS)
        configureAudioSession()
        #endif
    }

    // MARK: - Audio Session (iOS)

    #if os(iOS)
    private var wasPlayingBeforeInterruption = false

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
            logger.info("Audio session configured for background playback")

            // Listen for audio interruptions (phone calls, Siri, camera, etc.)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioInterruption),
                name: AVAudioSession.interruptionNotification,
                object: session
            )
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        Task { @MainActor in
            switch type {
            case .began:
                wasPlayingBeforeInterruption = isPlaying
                logger.info("Audio interruption began, wasPlaying: \(self.wasPlayingBeforeInterruption)")

                // Pause player for clean state
                if wasPlayingBeforeInterruption {
                    audioPlayer?.pause()
                    logger.info("Paused player for interruption")
                }

            case .ended:
                logger.info("Audio interruption ended")

                // Check if we should resume
                let shouldResume: Bool
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    shouldResume = options.contains(.shouldResume)
                    logger.info("Interruption options - shouldResume: \(shouldResume)")
                } else {
                    shouldResume = true
                }

                if shouldResume && wasPlayingBeforeInterruption {
                    // Reactivate audio session
                    do {
                        try AVAudioSession.sharedInstance().setActive(true, options: [])
                        logger.info("Audio session reactivated")
                    } catch {
                        logger.error("Failed to reactivate audio session: \(error)")
                    }

                    // Resume playback
                    audioPlayer?.play()
                    logger.info("Resumed playback after interruption")
                }

            @unknown default:
                break
            }
        }
    }
    #endif

    /// Sets the audio player  (dependency injection).
    func setAudioPlayer(_ player: YTMusicPlayer) {
        self.audioPlayer = player
        setupPlayerCallbacks()
        self.logger.info("Audio player set: \(type(of: player))")
    }

    /// Switches to a different audio player at runtime.
    /// Stops current player and switches to the other singleton instance.
    func switchPlayer(to playerType: AudioPlayerType) async {
        // Don't switch if already using this player type
        guard playerType != currentPlayerType else {
            self.logger.info("Already using \(playerType.name), no switch needed")
            return
        }

        self.logger.info("Switching audio player to: \(playerType.name)")

        // Remember if we were playing (use intent, not transient state)
        let wasPlaying = isPlaying
        let currentVideoId = currentTrack?.videoId

        // Stop current playback on old player
        audioPlayer?.stop()

        // Get the other player (singleton, already exists)
        let newPlayer: YTMusicPlayer = switch playerType {
        case .webView:
            Container.shared.ytMusicWebPlayer()
        case .native:
            Container.shared.ytMusicNativePlayer()
        case .vlc:
            Container.shared.vlcMusicPlayer()
        }

        // Set the new player and wire up callbacks
        self.audioPlayer = newPlayer
        setupPlayerCallbacks()

        // Apply current volume to new player
        newPlayer.setVolume(Float(volume))

        // Update the setting
        AppDefaults.shared.audioPlayer = playerType

        self.logger.info("Player switched to: \(type(of: newPlayer))")

        // If we had a track playing, reload it on the new player
        if let videoId = currentVideoId, wasPlaying {
            self.logger.info("Reloading current track on new player")
            await newPlayer.loadVideo(videoId: videoId)
        }
    }

    /// Returns the current player type.
    var currentPlayerType: AudioPlayerType {
        if audioPlayer is YTMusicNativePlayer {
            return .native
        } else if audioPlayer is VLCMusicPlayer {
            return .vlc
        }
        return .webView
    }

    /// Wires up callbacks from the audio player.
    private func setupPlayerCallbacks() {
        guard let player = audioPlayer else { return }

        player.onPlaybackUpdate = { [weak self] isPlaying, currentTime, duration in
            self?.updatePlaybackState(isPlaying: isPlaying, progress: currentTime, duration: duration)
        }

        player.onTrackEnded = { [weak self] in
            Task { @MainActor in
                await self?.handleTrackEnded()
            }
        }

        player.onLikeStatusChanged = { [weak self] status in
            self?.updateLikeStatus(status)
        }

        player.onError = { [weak self] error in
            self?.logger.error("Audio player error: \(error.localizedDescription)")
            self?.state = .error(error.localizedDescription)
        }

        player.onAudioQualityChanged = { [weak self] bitrateKbps, codec in
            self?.updateAudioQuality(bitrateKbps: bitrateKbps, codec: codec)
        }

        player.onStateChange = { [weak self] playerState in
            self?.handlePlayerStateChange(playerState)
        }

        // Set initial volume on player
        player.setVolume(Float(volume))
    }

    /// Handles state changes from the audio player.
    private func handlePlayerStateChange(_ playerState: PlaybackState) {
        switch playerState {
        case .playing:
            seekingProgress = nil
            isTransitioningTrack = false
            isPaused = false
        case .paused:
            // Only sync isPaused if not transitioning between tracks
            // This prevents button flicker when WebView reports .paused during track switch
            if !isTransitioningTrack {
                isPaused = true
            }
        case .ended, .error:
            isTransitioningTrack = false
            isPaused = true
        default:
            break
        }
        state = playerState
    }

    /// Handles when the current track ends.
    /// Uses background task protection so iOS doesn't suspend the app before the next track loads.
    private func handleTrackEnded() async {
        await BackgroundTaskHelper.withBackgroundTask {
            await self.performHandleTrackEnded()
        }
    }

    private func performHandleTrackEnded() async {
        self.logger.info("Track ended, advancing to next - queue size: \(self.queue.count), currentIndex: \(self.currentIndex), repeatMode: \(self.repeatMode.rawValue)")

        // Check repeat mode
        if repeatMode == .one {
            await seek(to: 0)
            await resume()
            return
        }

        // Try to play next in queue
        if !queue.isEmpty, currentIndex < queue.count - 1 {
            self.logger.info("Playing next track in queue")
            await next()
        } else if repeatMode == .all, !queue.isEmpty {
            self.logger.info("Looping back to first track (repeat all)")
            currentIndex = 0
            saveQueueState()
            if let firstSong = queue.first {
                await play(song: firstSong)
            }
        } else {
            // End of queue
            self.logger.info("End of queue reached (queue empty: \(self.queue.isEmpty), at last track: \(self.currentIndex >= self.queue.count - 1))")
            state = .ended
        }
    }

    // MARK: - Public Methods

    /// Plays a track by video ID.
    func play(videoId: String) async {
        self.logger.info("Playing video: \(videoId) [type: \(self.currentPlayerType.name)]")
        self.isPaused = false
        self.isTransitioningTrack = true
        self.state = .loading

        // Create a minimal Song object for now
        self.currentTrack = Song(
            id: videoId,
            title: "Loading...",
            artists: [],
            album: nil,
            duration: nil,
            thumbnailURL: nil,
            videoId: videoId
        )

        self.pendingPlayVideoId = videoId

        // Native player doesn't need user interaction popup (only WebView needs it)
        let needsUserInteraction = currentPlayerType == .webView && !hasUserInteractedThisSession

        if needsUserInteraction {
            // First time with WebView: show the mini player for user interaction
            self.showMiniPlayer = true
            self.logger.info("Showing mini player for first-time user interaction")
        } else {
            self.showMiniPlayer = false
            // Load the video directly via audio player
            await audioPlayer?.loadVideo(videoId: videoId)
        }

        // Fetch full song metadata in the background to get feedbackTokens
        await self.fetchSongMetadata(videoId: videoId)
    }

    /// Plays a song.
    func play(song: Song) async {
        self.logger.info("Playing song: \(song.title) [type: \(self.currentPlayerType.name)]")

        // Check for offline download — play locally
        let downloadManager = Container.shared.downloadManager()
        if let fileURL = downloadManager.localFileURL(for: song.videoId) {
            let isOpus = fileURL.pathExtension == "opus"
            if isOpus {
                self.logger.info("Playing offline Opus file for: \(song.title)")
                await playLocalFileViaVLC(fileURL, song: song)
            } else {
                self.logger.info("Playing offline AAC asset for: \(song.title)")
                let asset = AVURLAsset(url: fileURL)
                await playLocalAsset(asset, song: song)
            }
            return
        }

        self.isPaused = false
        self.isTransitioningTrack = true
        self.state = .loading
        self.currentTrack = song
        self.isPlayingOffline = false

        // Fetch artwork for Now Playing / Dynamic Island
        if let thumbnailURL = song.thumbnailURL {
            self.fetchArtwork(from: thumbnailURL)
        } else {
            self.logger.warning("No thumbnailURL for song: \(song.title) (videoId: \(song.videoId))")
        }

        // Reset playback progress for new track
        self.progress = 0
        self.duration = 0
        self.seekingProgress = nil
        self.resetTrackStatus()

        // Use existing feedbackTokens if the song already has them
        if let tokens = song.feedbackTokens {
            self.currentTrackFeedbackTokens = tokens
            self.currentTrackInLibrary = song.isInLibrary ?? false
            if let likeStatus = song.likeStatus {
                self.currentTrackLikeStatus = likeStatus
            }
        }

        self.pendingPlayVideoId = song.videoId

        // Native player doesn't need user interaction popup (only WebView needs it)
        let needsUserInteraction = currentPlayerType == .webView && !hasUserInteractedThisSession

        if needsUserInteraction {
            // First time with WebView: show the mini player for user interaction
            self.showMiniPlayer = true
            self.logger.info("Showing mini player for first-time user interaction")
        } else {
            self.showMiniPlayer = false
            await audioPlayer?.loadVideo(videoId: song.videoId)
        }

        // Fetch full song metadata if we don't have feedbackTokens
        if song.feedbackTokens == nil {
            await self.fetchSongMetadata(videoId: song.videoId)
        }
    }

    /// Plays a locally downloaded HLS asset via the native player.
    private func playLocalAsset(_ asset: AVURLAsset, song: Song) async {
        self.isPaused = false
        self.isTransitioningTrack = true
        self.state = .loading
        self.currentTrack = song
        self.isPlayingOffline = true

        // Reset playback progress
        self.progress = 0
        self.duration = 0
        self.seekingProgress = nil
        self.resetTrackStatus()

        if let thumbnailURL = song.thumbnailURL {
            self.fetchArtwork(from: thumbnailURL)
        }

        if let tokens = song.feedbackTokens {
            self.currentTrackFeedbackTokens = tokens
            self.currentTrackInLibrary = song.isInLibrary ?? false
            if let likeStatus = song.likeStatus {
                self.currentTrackLikeStatus = likeStatus
            }
        }

        self.pendingPlayVideoId = song.videoId

        // Use the native player for local asset playback
        let nativePlayer = Container.shared.ytMusicNativePlayer()
        if self.audioPlayer !== nativePlayer {
            // Temporarily switch to native player for offline playback
            self.audioPlayer?.stop()
            self.audioPlayer = nativePlayer
            setupPlayerCallbacks()
        }

        // Load the local asset via the native player
        await nativePlayer.loadAsset(asset)
    }

    /// Plays a locally downloaded Opus file via VLC player.
    private func playLocalFileViaVLC(_ fileURL: URL, song: Song) async {
        self.isPaused = false
        self.isTransitioningTrack = true
        self.state = .loading
        self.currentTrack = song
        self.isPlayingOffline = true

        self.progress = 0
        self.duration = 0
        self.seekingProgress = nil
        self.resetTrackStatus()

        if let thumbnailURL = song.thumbnailURL {
            self.fetchArtwork(from: thumbnailURL)
        }

        if let tokens = song.feedbackTokens {
            self.currentTrackFeedbackTokens = tokens
            self.currentTrackInLibrary = song.isInLibrary ?? false
            if let likeStatus = song.likeStatus {
                self.currentTrackLikeStatus = likeStatus
            }
        }

        self.pendingPlayVideoId = song.videoId

        let vlcPlayer = Container.shared.vlcMusicPlayer()
        if self.audioPlayer !== vlcPlayer {
            self.audioPlayer?.stop()
            self.audioPlayer = vlcPlayer
            setupPlayerCallbacks()
        }

        vlcPlayer.loadLocalFile(fileURL)
    }

    /// Called when the mini player confirms playback has started.
    func confirmPlaybackStarted() {
        self.showMiniPlayer = false
        self.isPaused = false
        self.state = .playing
        self.hasUserInteractedThisSession = true
        self.logger.info("Playback confirmed started, user interaction recorded")
    }

    /// Called when the mini player is dismissed.
    func miniPlayerDismissed() {
        self.showMiniPlayer = false
        if self.state == .loading {
            self.state = .idle
        }
    }

    /// Updates playback state from the persistent WebView observer.
    func updatePlaybackState(isPlaying: Bool, progress: Double, duration: Double) {
        let previousProgress = self.progress
        self.progress = progress
        self.duration = duration
        
        // Update Now Playing info with current playback state and elapsed time
        if let currentTrack = self.currentTrack {
            self.updateNowPlayingInfo(title: currentTrack.title, artist: currentTrack.artistsDisplay)
        }

        // Detect when song is about to end (within last 2 seconds)
        // This helps us prepare to play the next track from our queue
        if duration > 0, progress >= duration - 2, previousProgress < duration - 2 {
            self.songNearingEnd = true
        }
    }

    /// Updates the system Now Playing info (lock screen, media center, etc.).
    private func updateNowPlayingInfo(title: String, artist: String) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: self.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: self.progress,
            MPNowPlayingInfoPropertyPlaybackRate: self.isPlaying ? 1.0 : 0.0,
        ]

        if let artwork = self.currentArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Fetches and caches artwork for the current track.
    private func fetchArtwork(from url: URL) {
        self.logger.debug("Fetching artwork from: \(url.absoluteString)")
        KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
            switch result {
            case .success(let value):
                let image = value.image
                self?.logger.debug("Artwork fetched successfully - size: \(image.size.width)x\(image.size.height), cached: \(value.cacheType != .none)")
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

                Task { @MainActor [weak self] in
                    self?.currentArtwork = artwork
                    // Update Now Playing info with the new artwork
                    if let track = self?.currentTrack {
                        self?.updateNowPlayingInfo(title: track.title, artist: track.artistsDisplay)
                    }
                }
            case .failure(let error):
                self?.logger.warning("Failed to fetch artwork: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Image Prefetching

    /// Active prefetcher instance.
    private var imagePrefetcher: ImagePrefetcher?

    /// Prefetches images for upcoming tracks in the queue.
    /// - Parameters:
    ///   - prefetchForward: Number of tracks ahead to prefetch (default: 5)
    ///   - prefetchBackward: Number of tracks behind to prefetch (default: 2)
    private func prefetchQueueImages(prefetchForward: Int = 5, prefetchBackward: Int = 2) {
        // Cancel any existing prefetching
        imagePrefetcher?.stop()

        // Build list of track indices to prefetch
        var indicesToPrefetch: [Int] = []

        // Add forward tracks
        for offset in 1...prefetchForward {
            let index = currentIndex + offset
            if index < queue.count {
                indicesToPrefetch.append(index)
            }
        }

        // Add backward tracks
        for offset in 1...prefetchBackward {
            let index = currentIndex - offset
            if index >= 0 {
                indicesToPrefetch.append(index)
            }
        }

        // Collect URLs to prefetch
        var urlsToPrefetch: [URL] = []
        for index in indicesToPrefetch {
            guard let song = queue[safe: index] else { continue }
            if let heroURL = song.thumbnailURL?.heroThumbnailURL {
                urlsToPrefetch.append(heroURL)
            }
            if let cardURL = song.thumbnailURL?.cardThumbnailURL {
                urlsToPrefetch.append(cardURL)
            }
        }

        guard !urlsToPrefetch.isEmpty else {
            self.logger.debug("No images to prefetch")
            return
        }

        self.logger.info("Prefetching \(urlsToPrefetch.count) images for \(indicesToPrefetch.count) tracks")

        // Start prefetching
        imagePrefetcher = ImagePrefetcher(urls: urlsToPrefetch) { skipped, failed, completed in
            self.logger.debug("Prefetch completed: \(completed.count) succeeded, \(failed.count) failed, \(skipped.count) skipped")
        }
        imagePrefetcher?.start()
    }

    /// Flag to track when a song is nearing its end.
    private var songNearingEnd: Bool = false

    /// Updates track metadata when track changes (e.g., via next/previous).
    /// Also handles enforcing our queue when YouTube autoplay kicks in.
    func updateWebTrackMetadata(title: String, artist: String, thumbnailUrl: String) {
        self.logger.debug("Track metadata updated: \(title) - \(artist)")

        let thumbnailURL = URL(string: thumbnailUrl)
        let artistObj = Artist(id: "unknown", name: artist)
        let videoId = self.currentTrack?.videoId ?? self.pendingPlayVideoId ?? "unknown"

        // Update web track for UI display
        self.currentWebTrack = Song(
            id: videoId,
            title: title,
            artists: [artistObj],
            album: self.currentTrack?.album,
            duration: self.duration > 0 ? self.duration : self.currentTrack?.duration,
            thumbnailURL: thumbnailURL,
            videoId: videoId,
            likeStatus: self.currentTrack?.likeStatus,
            isInLibrary: self.currentTrack?.isInLibrary,
            feedbackTokens: self.currentTrack?.feedbackTokens
        )

        // Check if track actually changed (compare against native track, not web display)
        let trackChanged = self.currentTrack?.title != title || self.currentTrack?.artistsDisplay != artist

        // If track changed and we have a queue, check if YouTube autoplay kicked in
        if trackChanged, !self.queue.isEmpty, self.songNearingEnd {
            self.songNearingEnd = false

            // Check if the new track matches our expected next track in queue
            let expectedNextIndex = self.currentIndex + 1
            if expectedNextIndex < self.queue.count {
                let expectedNextTrack = self.queue[expectedNextIndex]
                // If title doesn't match expected next track, YouTube autoplay overrode our queue
                if title != expectedNextTrack.title {
                    self.logger.info("YouTube autoplay detected, overriding with queue track")
                    // Play our queue's next track instead
                    Task {
                        await self.next()
                    }
                    return
                } else {
                    // Track matches our queue, update the index
                    self.currentIndex = expectedNextIndex
                    saveQueueState()
                    self.logger.info("Track advanced to queue index \(expectedNextIndex)")
                }
            }
        }

        self.currentTrack = Song(
            id: videoId,
            title: title,
            artists: [artistObj],
            album: nil,
            duration: self.duration > 0 ? self.duration : nil,
            thumbnailURL: thumbnailURL,
            videoId: videoId
        )

    }

    /// Toggles play/pause.
    func playPause() async {
        self.logger.debug("Toggle play/pause")

        if self.isPlaying {
            await self.pause()
        } else {
            // Nothing to play - try to fetch liked songs
            guard currentTrack != nil else {
                self.logger.debug("No track to play, fetching liked songs")
                await self.playLikedSongs()
                return
            }
            // If idle with a current track, load it first (e.g., after app restore)
            if self.state == .idle, let track = currentTrack {
                await self.play(song: track)
            } else {
                await self.resume()
            }
        }
    }

    /// Fetches liked songs and starts playback with shuffle.
    private func playLikedSongs() async {
        self.state = .loading
        do {
            let likedSongs = try await ytMusicClient.getLikedSongs()
            guard !likedSongs.isEmpty else {
                self.logger.info("No liked songs found")
                self.state = .idle
                return
            }
            // Shuffle and play
            let shuffled = likedSongs.shuffled()
            await self.playQueue(shuffled, startingAt: 0)
            self.logger.info("Playing \(shuffled.count) liked songs (shuffled)")
        } catch {
            self.logger.error("Failed to fetch liked songs: \(error.localizedDescription)")
            self.state = .idle
        }
    }

    /// Pauses playback.
    func pause() async {
        self.logger.debug("Pausing playback")
        self.isPaused = true
        audioPlayer?.pause()
    }

    /// Resumes playback.
    func resume() async {
        self.logger.debug("Resuming playback")
        self.isPaused = false
        audioPlayer?.play()
    }

    /// Skips to next track.
    func next() async {
        self.logger.info("Skipping to next track - queue size: \(self.queue.count), currentIndex: \(self.currentIndex)")

        // Prioritize local queue if we have one
        if !self.queue.isEmpty {
            // Handle repeat one mode - replay current track
            if self.repeatMode == .one {
                await self.seek(to: 0)
                await self.resume()
                return
            }

            // Handle shuffle mode - pick random track
            if self.shuffleEnabled {
                let randomIndex = Int.random(in: 0 ..< self.queue.count)
                self.currentIndex = randomIndex
                saveQueueState()
                if let nextSong = queue[safe: currentIndex] {
                    await self.play(song: nextSong)
                }
                return
            }

            // Normal next behavior
            if self.currentIndex < self.queue.count - 1 {
                self.currentIndex += 1
                saveQueueState()
                if let nextSong = queue[safe: currentIndex] {
                    await self.play(song: nextSong)
                }
            } else if self.repeatMode == .all {
                // Loop back to start if repeat all is enabled
                self.currentIndex = 0
                saveQueueState()
                if let firstSong = queue.first {
                    await self.play(song: firstSong)
                }
            }
            // At end of queue with repeat off, don't do anything
            return
        }

        // Fall back to player's next if no local queue
        audioPlayer?.next()
    }

    /// Goes to previous track.
    func previous() async {
        self.logger.info("Going to previous track - queue size: \(self.queue.count), currentIndex: \(self.currentIndex), progress: \(self.progress)")

        // Prioritize local queue if we have one
        if !self.queue.isEmpty {
            if self.progress > 3 {
                // Restart current track
                await self.seek(to: 0)
            } else if self.currentIndex > 0 {
                self.currentIndex -= 1
                saveQueueState()
                if let prevSong = queue[safe: currentIndex] {
                    await self.play(song: prevSong)
                }
            } else {
                // At start of queue, just restart current track
                await self.seek(to: 0)
            }
            return
        }

        // Fall back to players's previous if no local queue
        if self.progress > 3 {
            await self.seek(to: 0)
        } else {
            audioPlayer?.previous()
        }
    }

    /// Seeks to a specific time.
    func seek(to time: TimeInterval) async {
        self.logger.info("Seeking to \(time)")
        // Store seeking time immediately to prevent UI jumping during seek
        self.seekingProgress = time
        audioPlayer?.seek(to: time)
        self.progress = time
    }

    /// Updates seeking progress while user is dragging the seek slider.
    func updateSeekingProgress(_ normalizedValue: Double) {
        self.seekValue = normalizedValue
        self.seekingProgress = normalizedValue * duration
    }

    /// Performs the seek when user releases the slider.
    func performSeek() {
        let seekTime = seekValue * duration
        Task {
            await seek(to: seekTime)
        }
    }

    /// Sets the volume.
    func setVolume(_ value: Double) async {
        let clampedValue = max(0, min(1, value))
        self.logger.debug("Setting volume to \(clampedValue)")
        self.volume = clampedValue

        // Persist volume to UserDefaults (including mute state of 0)
        UserDefaults.standard.set(clampedValue, forKey: Self.volumeKey)

        audioPlayer?.setVolume(Float(clampedValue))
    }

    /// Toggles mute state. Remembers previous volume for unmuting.
    func toggleMute() async {
        if self.isMuted {
            // Unmute - restore previous volume
            let restoredVolume = self.volumeBeforeMute > 0 ? self.volumeBeforeMute : 1.0
            await self.setVolume(restoredVolume)
            self.logger.info("Unmuted, volume restored to \(restoredVolume)")
        } else {
            // Mute - save current volume and set to 0
            self.volumeBeforeMute = self.volume
            // Persist volumeBeforeMute so we can restore after app restart
            UserDefaults.standard.set(self.volumeBeforeMute, forKey: Self.volumeBeforeMuteKey)
            await self.setVolume(0)
            self.logger.info("Muted")
        }
    }

    /// Toggles shuffle mode.
    func toggleShuffle() {
        self.shuffleEnabled.toggle()
        let status = self.shuffleEnabled ? "enabled" : "disabled"
        self.logger.info("Shuffle mode: \(status)")
        UserDefaults.standard.set(shuffleEnabled, forKey: Self.shuffleKey)
    }

    /// Cycles through repeat modes: off -> all -> one -> off.
    func cycleRepeatMode() {
        switch self.repeatMode {
        case .off:
            self.repeatMode = .all
        case .all:
            self.repeatMode = .one
        case .one:
            self.repeatMode = .off
        }
        let mode = self.repeatMode
        self.logger.info("Repeat mode: \(String(describing: mode))")
        UserDefaults.standard.set(repeatMode.rawValue, forKey: Self.repeatKey)
    }

    /// Resets shuffle/repeat to defaults and clears persisted state.
    private func resetPlaybackPreferences() {
        self.shuffleEnabled = false
        self.repeatMode = .off
        UserDefaults.standard.removeObject(forKey: Self.shuffleKey)
        UserDefaults.standard.removeObject(forKey: Self.repeatKey)
    }

    /// Stops playback and clears state.
    func stop() async {
        self.logger.debug("Stopping playback")
        await self.evaluatePlayerCommand("pauseVideo()")
        self.isPaused = true
        self.isTransitioningTrack = false
        self.state = .idle
        self.currentTrack = nil
        self.progress = 0
        self.duration = 0
    }

    /// Plays a queue of songs starting at the specified index.
    /// - Parameters:
    ///   - songs: The songs to play.
    ///   - index: The index to start playing from.
    ///   - sourcePlaylist: The playlist these songs came from (for navigation back to it).
    func playQueue(_ songs: [Song], startingAt index: Int = 0, from sourcePlaylist: Playlist? = nil) async {
        guard !songs.isEmpty else { return }
        let safeIndex = max(0, min(index, songs.count - 1))

        // Reset shuffle/repeat when starting a new playlist
        let isNewPlaylist = sourcePlaylist?.id != self.sourcePlaylist?.id
        if isNewPlaylist {
            resetPlaybackPreferences()
        }

        self.queue = songs
        self.currentIndex = safeIndex
        self.sourcePlaylist = sourcePlaylist

        self.logger.info("Queue set: \(songs.count) songs, starting at index \(safeIndex)")
        saveQueueState()
        if let song = songs[safe: safeIndex] {
            await self.play(song: song)
        }
    }

    /// Plays a song and fetches similar songs (radio queue) in the background.
    /// The queue will be populated with similar songs from the radio feature.
    func playWithRadio(song: Song) async {
        self.logger.info("Playing with radio: \(song.title)")

        // Start with just this song in the queue
        self.queue = [song]
        self.currentIndex = 0
        saveQueueState()
        await self.play(song: song)

        // Fetch radio queue in background
        await self.fetchAndApplyRadioQueue(for: song.videoId)
    }

    /// Fetches radio queue and applies it, keeping the current song at the front.
    private func fetchAndApplyRadioQueue(for videoId: String) async {
        await BackgroundTaskHelper.withBackgroundTask {
            await self.performFetchAndApplyRadioQueue(for: videoId)
        }
    }

    private func performFetchAndApplyRadioQueue(for videoId: String) async {
        do {
            let radioSongs = try await ytMusicClient.getRadioQueue(videoId: videoId)
            guard !radioSongs.isEmpty else {
                self.logger.info("No radio songs returned")
                return
            }

            // Only update if we're still playing the same song
            guard let currentSong = self.currentTrack, currentSong.videoId == videoId else {
                self.logger.info("Track changed, discarding radio queue")
                return
            }

            // Ensure the current song is at the front of the queue
            // The radio queue may or may not include the seed song
            var newQueue: [Song] = []

            // Check if the current song is already in the radio queue
            let radioContainsCurrentSong = radioSongs.contains { $0.videoId == videoId }

            if radioContainsCurrentSong {
                // Find the index of current song and reorder queue to start from it
                if let currentSongIndex = radioSongs.firstIndex(where: { $0.videoId == videoId }) {
                    // Put current song first, then the rest
                    newQueue.append(currentSong)
                    for (index, song) in radioSongs.enumerated() where index != currentSongIndex {
                        newQueue.append(song)
                    }
                } else {
                    newQueue = radioSongs
                }
            } else {
                // Current song not in radio queue - prepend it
                newQueue.append(currentSong)
                newQueue.append(contentsOf: radioSongs)
            }

            self.queue = newQueue
            self.currentIndex = 0
            self.saveQueueState()
            self.logger.info("Radio queue updated with \(newQueue.count) songs (current song at front)")
        } catch {
            self.logger.warning("Failed to fetch radio queue: \(error.localizedDescription)")
        }
    }

    /// Clears the playback queue except for the currently playing track.
    func clearQueue() {
        guard let currentTrack else {
            self.queue = []
            self.currentIndex = 0
            saveQueueState()
            return
        }
        // Keep only the current track
        self.queue = [currentTrack]
        self.currentIndex = 0
        saveQueueState()
        self.logger.info("Queue cleared, keeping current track")
    }

    /// Plays a song from the queue at the specified index.
    func playFromQueue(at index: Int) async {
        guard index >= 0, index < self.queue.count else { return }
        self.currentIndex = index
        saveQueueState()
        if let song = queue[safe: index] {
            await self.play(song: song)
        }
    }

    /// Inserts songs immediately after the current track.
    /// - Parameter songs: The songs to insert into the queue.
    func insertNextInQueue(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        let insertIndex = min(self.currentIndex + 1, self.queue.count)
        self.queue.insert(contentsOf: songs, at: insertIndex)
        saveQueueState()
        self.logger.info("Inserted \(songs.count) songs at position \(insertIndex)")
    }

    /// Removes songs from the queue by video ID.
    /// - Parameter videoIds: Set of video IDs to remove.
    func removeFromQueue(videoIds: Set<String>) {
        let previousCount = self.queue.count
        self.queue.removeAll { videoIds.contains($0.videoId) }

        // Adjust currentIndex if needed
        if let current = currentTrack,
           let newIndex = queue.firstIndex(where: { $0.videoId == current.videoId })
        {
            self.currentIndex = newIndex
        } else if self.currentIndex >= self.queue.count {
            self.currentIndex = max(0, self.queue.count - 1)
        }

        saveQueueState()
        self.logger.info("Removed \(previousCount - self.queue.count) songs from queue")
    }

    /// Reorders the queue based on a new order of video IDs.
    /// - Parameter videoIds: The new order of video IDs.
    func reorderQueue(videoIds: [String]) {
        var reordered: [Song] = []
        var videoIdToSong: [String: Song] = [:]

        for song in self.queue {
            videoIdToSong[song.videoId] = song
        }

        for videoId in videoIds {
            if let song = videoIdToSong[videoId] {
                reordered.append(song)
            }
        }

        self.queue = reordered

        // Update currentIndex to match current track's new position
        if let current = currentTrack,
           let newIndex = queue.firstIndex(where: { $0.videoId == current.videoId })
        {
            self.currentIndex = newIndex
        }

        saveQueueState()
        self.logger.info("Queue reordered with \(reordered.count) songs")
    }

    /// Shuffles the queue, keeping the current track in place at the front.
    func shuffleQueue() {
        guard self.queue.count > 1 else { return }

        // Remove current track, shuffle the rest, put current track at front
        if let currentSong = queue[safe: currentIndex] {
            var shuffled = self.queue
            shuffled.remove(at: self.currentIndex)
            shuffled.shuffle()
            shuffled.insert(currentSong, at: 0)
            self.queue = shuffled
            self.currentIndex = 0
        } else {
            self.queue.shuffle()
            self.currentIndex = 0
        }

        saveQueueState()
        self.logger.info("Queue shuffled")
    }

    /// Adds songs to the end of the queue.
    /// - Parameter songs: The songs to append to the queue.
    func appendToQueue(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        self.queue.append(contentsOf: songs)
        saveQueueState()
        self.logger.info("Appended \(songs.count) songs to queue")
    }

    // MARK: - Like/Dislike/Library Actions

    /// Plays a song and likes it.
    func playAndLike(song: Song) async {
        await self.play(song: song)
        try? await Task.sleep(for: .milliseconds(100))
        self.likeCurrentTrack()
    }

    /// Plays a song and dislikes it.
    func playAndDislike(song: Song) async {
        await self.play(song: song)
        try? await Task.sleep(for: .milliseconds(100))
        self.dislikeCurrentTrack()
    }

    /// Plays a song and adds it to the library.
    func playAndAddToLibrary(song: Song) async {
        await self.play(song: song)
        try? await Task.sleep(for: .milliseconds(100))
        self.toggleLibraryStatus()
    }

    /// Likes the current track (thumbs up).
    func likeCurrentTrack() {
        guard let track = currentTrack else { return }
        self.logger.info("Liking current track: \(track.videoId)")

        // Toggle: if already liked, remove the like
        let newStatus: LikeStatus = self.currentTrackLikeStatus == .like ? .indifferent : .like
        let previousStatus = self.currentTrackLikeStatus
        self.currentTrackLikeStatus = newStatus

        // Use API call for reliable rating
        Task {
            do {
                try await self.ytMusicClient.rateSong(videoId: track.videoId, rating: newStatus)
                self.logger.info("Successfully rated song as \(newStatus.rawValue)")
            } catch {
                self.logger.error("Failed to rate song: \(error.localizedDescription)")
                // Revert on failure
                self.currentTrackLikeStatus = previousStatus
            }
        }
    }

    /// Dislikes the current track (thumbs down).
    func dislikeCurrentTrack() {
        guard let track = currentTrack else { return }
        self.logger.info("Disliking current track: \(track.videoId)")

        // Toggle: if already disliked, remove the dislike
        let newStatus: LikeStatus = self.currentTrackLikeStatus == .dislike ? .indifferent : .dislike
        let previousStatus = self.currentTrackLikeStatus
        self.currentTrackLikeStatus = newStatus

        // Use API call for reliable rating
        Task {
            do {
                try await self.ytMusicClient.rateSong(videoId: track.videoId, rating: newStatus)
                self.logger.info("Successfully rated song as \(newStatus.rawValue)")
            } catch {
                self.logger.error("Failed to rate song: \(error.localizedDescription)")
                // Revert on failure
                self.currentTrackLikeStatus = previousStatus
            }
        }
    }

    /// Toggles the library status of the current track.
    func toggleLibraryStatus() {
        guard let track = currentTrack else { return }
        self.logger.info("Toggling library status for current track: \(track.videoId)")

        // Determine which token to use based on current state
        let isCurrentlyInLibrary = self.currentTrackInLibrary
        let tokenToUse = isCurrentlyInLibrary
            ? self.currentTrackFeedbackTokens?.remove
            : self.currentTrackFeedbackTokens?.add

        guard let token = tokenToUse else {
            self.logger.warning("No feedback token available for library toggle")
            return
        }

        // Optimistic update
        let previousState = self.currentTrackInLibrary
        self.currentTrackInLibrary.toggle()

        // Use API call for reliable library management
        Task {
            do {
                try await self.ytMusicClient.editSongLibraryStatus(feedbackTokens: [token])
                let action = isCurrentlyInLibrary ? "removed from" : "added to"
                self.logger.info("Successfully \(action) library")

                // After successful toggle, we need to swap the tokens
                // The remove token becomes add, and vice versa
                // Re-fetch metadata to get updated tokens
                await self.fetchSongMetadata(videoId: track.videoId)
            } catch {
                self.logger.error("Failed to toggle library status: \(error.localizedDescription)")
                // Revert on failure
                self.currentTrackInLibrary = previousState
            }
        }
    }

    /// Updates the like status from WebView observation.
    func updateLikeStatus(_ status: LikeStatus) {
        self.currentTrackLikeStatus = status
    }

    /// Updates the audio quality info from WebView observation.
    func updateAudioQuality(bitrateKbps: Int, codec: String) {
        self.audioBitrateKbps = bitrateKbps
        self.audioCodec = codec
    }

    /// Resets like/library status when track changes.
    private func resetTrackStatus() {
        self.currentTrackLikeStatus = .indifferent
        self.currentTrackInLibrary = false
        self.currentTrackFeedbackTokens = nil
        self.audioBitrateKbps = 0
        self.audioCodec = ""
        self.currentArtwork = nil
        self.currentWebTrack = nil
    }

    /// Fetches full song metadata including feedbackTokens from the API.
    private func fetchSongMetadata(videoId: String) async {
        await BackgroundTaskHelper.withBackgroundTask {
            await self.performFetchSongMetadata(videoId: videoId)
        }
    }

    private func performFetchSongMetadata(videoId: String) async {
        do {
            let songData = try await ytMusicClient.getSong(videoId: videoId)

            // Update current track with full metadata if it's still the same song
            if self.currentTrack?.videoId == videoId {
                // Preserve the title/artist from WebView if they're better
                let title = self.currentTrack?.title == "Loading..." ? songData.title : (self.currentTrack?.title ?? songData.title)
                let artists = self.currentTrack?.artists.isEmpty == true ? songData.artists : (self.currentTrack?.artists ?? songData.artists)

                let finalThumbnailURL = songData.thumbnailURL ?? self.currentTrack?.thumbnailURL
                self.logger.debug("Song metadata - API thumbnailURL: \(songData.thumbnailURL?.absoluteString ?? "nil"), final: \(finalThumbnailURL?.absoluteString ?? "nil")")

                // If we now have a thumbnail but didn't before, fetch it
                if finalThumbnailURL != nil, self.currentArtwork == nil {
                    self.logger.debug("Fetching artwork from API metadata")
                    self.fetchArtwork(from: finalThumbnailURL!)
                }

                self.currentTrack = Song(
                    id: videoId,
                    title: title,
                    artists: artists,
                    album: songData.album ?? self.currentTrack?.album,
                    duration: songData.duration ?? self.currentTrack?.duration,
                    thumbnailURL: finalThumbnailURL,
                    videoId: videoId,
                    likeStatus: songData.likeStatus,
                    isInLibrary: songData.isInLibrary,
                    feedbackTokens: songData.feedbackTokens
                )

                // Update service state
                if let likeStatus = songData.likeStatus {
                    self.currentTrackLikeStatus = likeStatus
                }
                self.currentTrackInLibrary = songData.isInLibrary ?? false
                self.currentTrackFeedbackTokens = songData.feedbackTokens

                self.logger.info("Updated track metadata - inLibrary: \(self.currentTrackInLibrary), hasTokens: \(self.currentTrackFeedbackTokens != nil)")
            }
        } catch {
            self.logger.warning("Failed to fetch song metadata: \(error.localizedDescription)")
        }
    }

    // MARK: - Queue Persistence

    /// Saves the current queue and index to persistent storage.
    private func saveQueueState() {
        AppDefaults.shared.savedQueue = queue
        AppDefaults.shared.savedQueueIndex = currentIndex
        logger.debug("Saved queue state: \(self.queue.count) songs, index \(self.currentIndex)")
    }

    /// Restores the queue and current track from persistent storage.
    private func restoreQueueState() {
        guard let savedQueue = AppDefaults.shared.savedQueue, !savedQueue.isEmpty else {
            logger.debug("No saved queue to restore")
            return
        }

        let savedIndex = AppDefaults.shared.savedQueueIndex
        let safeIndex = max(0, min(savedIndex, savedQueue.count - 1))

        queue = savedQueue
        currentIndex = safeIndex
        currentTrack = savedQueue[safeIndex]

        logger.info("Restored queue state: \(savedQueue.count) songs, index \(safeIndex), track: \(self.currentTrack?.title ?? "unknown")")
    }

    // MARK: - Private Methods

    /// Legacy method for evaluating player commands - now delegates to audio player.
    private func evaluatePlayerCommand(_ command: String) async {
        switch command {
        case "pause", "pauseVideo()":
            audioPlayer?.pause()
        case "play", "playVideo()":
            audioPlayer?.play()
        default:
            if command.hasPrefix("seekTo(") {
                let timeStr = command.dropFirst(7).prefix(while: { $0 != "," && $0 != ")" })
                if let time = Double(timeStr) {
                    audioPlayer?.seek(to: time)
                }
            } else if command.hasPrefix("setVolume(") {
                let volStr = command.dropFirst(10).dropLast()
                if let vol = Int(volStr) {
                    audioPlayer?.setVolume(Float(vol) / 100.0)
                }
            }
        }
    }

}

extension PlayerManager {

    /// Current playback state.
    enum PlaybackState: Equatable, Sendable {
        case idle
        case loading
        case playing
        case paused
        case buffering
        case ended
        case error(String)

        var isPlaying: Bool {
            self == .playing
        }
    }

    /// Repeat mode for playback.
    enum RepeatMode: Int, Sendable {
        case off = 0
        case all = 1
        case one = 2
    }

}

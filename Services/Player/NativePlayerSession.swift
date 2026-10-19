import AVFoundation
import Foundation
import os

/// Represents a native audio playback session with AVPlayer.
/// Encapsulates the player, player item, and all observers.
@MainActor
final class NativePlayerSession {
    // MARK: - Properties

    let player: AVPlayer
    let playerItem: AVPlayerItem

    /// Duration from API (more reliable than playerItem.duration for streams).
    let apiDuration: TimeInterval?

    private(set) var currentTime: TimeInterval = 0
    private(set) var status: Status = .idle

    // These observers need nonisolated(unsafe) to be accessible from deinit.
    // Safe because deinit only runs when no other references exist.
    nonisolated(unsafe) private var timeObserver: Any?
    nonisolated(unsafe) private var statusObserver: NSKeyValueObservation?
    nonisolated(unsafe) private var timeControlStatusObserver: NSKeyValueObservation?
    nonisolated(unsafe) private var endTimeObserver: NSObjectProtocol?

    private let logger = DiagnosticsLogger.player

    // MARK: - Callbacks

    var onStatusChanged: ((Status) -> Void)?
    var onTimeUpdate: ((_ currentTime: TimeInterval, _ duration: TimeInterval, _ isPlaying: Bool) -> Void)?
    var onTrackEnded: (() -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Status Enum

    enum Status {
        case idle
        case ready
        case playing
        case paused
        case buffering
        case completed
        case failed(Error)

        var isCompleted: Bool {
            if case .completed = self { return true }
            return false
        }
    }

    // MARK: - Computed Properties

    var duration: TimeInterval {
        if let apiDur = apiDuration, apiDur > 0 {
            return apiDur
        }
        let itemDuration = playerItem.duration.seconds
        return itemDuration.isNaN ? 0 : itemDuration
    }

    /// Logs duration sources for debugging
    func logDurationSources() {
        let apiDur = apiDuration ?? 0
        let itemDur = playerItem.duration.seconds
        let itemDurStr = itemDur.isNaN ? "NaN" : String(format: "%.2f", itemDur)
        logger.info("[PlayerSession] Duration sources: apiDuration=\(apiDur)s, playerItem.duration=\(itemDurStr)s, using=\(self.duration)s")
    }

    var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    // MARK: - Initialization

    init(url: URL, headers: [String: String]? = nil, apiDuration: TimeInterval? = nil) {
        self.apiDuration = apiDuration

        // Create asset with headers if provided
        let asset: AVURLAsset
        if let headers = headers {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        } else {
            asset = AVURLAsset(url: url)
        }

        self.playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)

        setupObservers()
        if let apiDur = apiDuration {
            logger.info("[PlayerSession] Created with apiDuration: \(apiDur)s (\(self.formatTime(apiDur)))")
        } else {
            logger.info("[PlayerSession] Created without apiDuration, will use playerItem.duration")
        }
    }

    /// Creates a session from a pre-existing AVURLAsset (e.g., a downloaded offline asset).
    init(asset: AVURLAsset, apiDuration: TimeInterval? = nil) {
        self.apiDuration = apiDuration
        self.playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)

        setupObservers()
        logger.info("[PlayerSession] Created from local asset")
    }

    deinit {
        // Cleanup observers synchronously (can't call MainActor methods from deinit)
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        statusObserver?.invalidate()
        timeControlStatusObserver?.invalidate()
        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        player.pause()
    }

    // MARK: - Playback Control

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, duration - 0.5))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player.seek(to: cmTime) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sendTimeUpdate()
            }
        }
    }

    // MARK: - Observer Setup

    private func setupObservers() {
        // Observe player item status
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            let status = item.status
            Task { @MainActor [weak self] in
                self?.handleItemStatus(status)
            }
        }

        // Observe timeControlStatus for play/pause/buffering
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                self?.handleTimeControlStatus(status)
            }
        }

        // Periodic time observer (1 second interval)
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.handleTimeUpdate(time)
            }
        }

        // Track ended notification
        endTimeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logger.info("[PlayerSession] AVPlayerItemDidPlayToEndTime notification received")
                self?.handleTrackEnded()
            }
        }
        logger.info("[PlayerSession] Registered end time observer for playerItem")
    }

    // MARK: - Event Handlers

    private func handleItemStatus(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            logger.info("[PlayerSession] Ready to play")
            logDurationSources()
            updateStatus(.ready)
            sendTimeUpdate()
        case .failed:
            if let error = playerItem.error {
                let nsError = error as NSError
                logger.error("❌ [PlayerSession] Failed: domain=\(nsError.domain), code=\(nsError.code), description=\(error.localizedDescription)")
                if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    logger.error("   ↳ Underlying: domain=\(underlyingError.domain), code=\(underlyingError.code), description=\(underlyingError.localizedDescription)")
                }
                updateStatus(.failed(error))
                onError?(error)
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            logger.debug("[PlayerSession] Playing")
            updateStatus(.playing)
        case .paused:
            logger.debug("[PlayerSession] Paused")
            updateStatus(.paused)
        case .waitingToPlayAtSpecifiedRate:
            logger.debug("[PlayerSession] Buffering")
            updateStatus(.buffering)
        @unknown default:
            break
        }
        sendTimeUpdate()
    }

    private func handleTimeUpdate(_ time: CMTime) {
        let seconds = time.seconds
        guard !seconds.isNaN, duration > 0, !status.isCompleted else { return }
        currentTime = seconds
        sendTimeUpdate()

        // Fallback: detect track end if notification doesn't fire
        // Check if currentTime has passed duration (API duration can be slightly shorter than stream)
        let remaining = duration - seconds
        if remaining <= 0 {
            let progressStr = formatTime(seconds)
            let durationStr = formatTime(duration)
            logger.info("[PlayerSession] Track end detected via time check (progress: \(progressStr), duration: \(durationStr))")
            handleTrackEnded()
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func handleTrackEnded() {
        // Guard against multiple calls (time observer fallback + AVPlayerItemDidPlayToEndTime)
        guard !status.isCompleted else { return }
        logger.info("[PlayerSession] Track ended")
        updateStatus(.completed)
        onTrackEnded?()
    }

    private func sendTimeUpdate() {
        guard duration > 0 else { return }
        onTimeUpdate?(currentTime, duration, isPlaying)
    }

    private func updateStatus(_ newStatus: Status) {
        status = newStatus
        onStatusChanged?(newStatus)
    }

    // MARK: - Cleanup

    private func cleanup() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil

        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
            endTimeObserver = nil
        }

        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

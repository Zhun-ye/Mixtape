import Foundation
import FactoryKit
import SwiftUI

// MARK: - PlayerViewModel

@MainActor
@Observable
final class PlayerViewModel {
    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    // Volume state
    var volumeValue: Double = 1.0
    var isAdjustingVolume = false

    // Navigation callback
    var onNavigateToPlaylist: (() -> Void)?

    // Fullscreen player state (iOS)
    var showFullscreenPlayer = false

    // Task for player operations - auto-cancels previous operation
    private var playerTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    init() {
        self.volumeValue = playerManager.volume
    }

    // MARK: - Computed Properties

    var currentTrack: Song? { playerManager.currentTrack }
    var currentWebTrack: Song? { playerManager.currentWebTrack }
    var isPlaying: Bool { playerManager.isPlaying  }
    var progress: Double { playerManager.displayProgress }
    var duration: Double { playerManager.duration }

    /// Progress value for display - returns seek position while seeking to prevent jumping
    var volume: Double { playerManager.volume }
    var shuffleEnabled: Bool { playerManager.shuffleEnabled }
    var repeatMode: PlayerManager.RepeatMode { playerManager.repeatMode }
    var sourcePlaylist: Playlist? { playerManager.sourcePlaylist }
    var showQueue: Bool {
        get { playerManager.showQueue }
        set { playerManager.showQueue = newValue }
    }
    var showLyrics: Bool {
        get { playerManager.showLyrics }
        set { playerManager.showLyrics = newValue }
    }
    var currentTrackLikeStatus: LikeStatus { playerManager.currentTrackLikeStatus }
    var audioBitrateKbps: Int { playerManager.audioBitrateKbps }
    var audioCodec: String { playerManager.audioCodec }
    var currentPlayerType: AudioPlayerType { playerManager.currentPlayerType }
    var isPlayingOffline: Bool { playerManager.isPlayingOffline }

    var repeatIcon: String {
        switch repeatMode {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var repeatAccessibilityValue: String {
        switch repeatMode {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
    }

    var volumeIcon: String {
        let currentVolume = isAdjustingVolume ? volumeValue : volume
        if currentVolume == 0 {
            return "speaker.slash.fill"
        } else if currentVolume < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }

    var audioQualityLabel: String? {
        let bitrate = audioBitrateKbps
        let codec = audioCodec

        #if DEBUG
        let playerType: String = switch currentPlayerType {
        case .native: " (Native)"
        case .vlc: " (VLC)"
        case .webView: " (Web)"
        }
        #else
        let playerType = ""
        #endif

        let offlineTag = isPlayingOffline ? "Offline · " : ""

        var codecName: String?
        if codec.contains("opus") || codec.contains("Opus") {
            codecName = "OPUS"
        } else if codec.contains("mp4a") || codec.contains("aac") || codec.contains("AAC") {
            codecName = "AAC"
        } else if codec.contains("vorbis") {
            codecName = "VORBIS"
        }

        if bitrate > 0 {
            if let name = codecName {
                return "\(offlineTag)\(bitrate)kbps \(name)\(playerType)"
            }
            return "\(offlineTag)\(bitrate)kbps\(playerType)"
        } else if let name = codecName {
            return "\(offlineTag)\(name)\(playerType)"
        } else if isPlayingOffline {
            return "Offline\(playerType)"
        }
        return playerType.isEmpty ? nil : String(playerType.dropFirst(2).dropLast())
    }

    // MARK: - Time Formatting

    func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    func formatRemainingTime(_ current: Double, total: Double) -> String {
        guard total.isFinite, total > 0 else { return "-0:00" }
        let remaining = max(0, total - current)
        return "-\(formatTime(remaining))"
    }

    // MARK: - Actions

    func playPause() {
        playerTask = Task {
            await playerManager.playPause()
        }
    }

    func next() {
        playerTask = Task {
            await playerManager.next()
        }
    }

    func previous() {
        playerTask = Task {
            await playerManager.previous()
        }
    }

    func seek(to time: Double) {
        playerTask = Task {
            await playerManager.seek(to: time)
        }
    }

    func setVolume(_ value: Double) {
        playerTask = Task {
            await playerManager.setVolume(value)
        }
    }

    func toggleMute() {
        playerTask = Task {
            await playerManager.toggleMute()
        }
    }

    func toggleShuffle() {
        playerManager.toggleShuffle()
    }

    func cycleRepeatMode() {
        playerManager.cycleRepeatMode()
    }

    func likeCurrentTrack() {
        playerManager.likeCurrentTrack()
    }

    func dislikeCurrentTrack() {
        playerManager.dislikeCurrentTrack()
    }

    func addToLibrary(_ track: Song) {
        // Track is already playing in the player, just toggle library status
        playerManager.toggleLibraryStatus()
    }

    // MARK: - Seek Binding

    /// Binding for seek slider - stores seeking progress to prevent jumping
    var seekBinding: Binding<Double> {
        Binding(
            get: {
                self.duration > 0 ? self.progress / self.duration : 0
            },
            set: { newValue in
                self.playerManager.updateSeekingProgress(newValue)
            }
        )
    }

    // MARK: - Sync Helpers

    func syncVolumeValue() {
        if !isAdjustingVolume {
            volumeValue = volume
        }
    }

    func performSeek() {
        playerManager.performSeek()
    }

    func performVolumeChange() {
        guard isAdjustingVolume else { return }
        setVolume(volumeValue)
        isAdjustingVolume = false
    }
}

import FactoryKit
import Foundation
import Observation
import SwiftUINavigation

/// ViewModel for the Downloads management view.
@MainActor
@Observable
final class DownloadsViewModel: HashableObject {
    @ObservationIgnored
    @Injected(\.downloadManager) private var downloadManager

    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    /// Delegate for navigation actions.
    weak var delegate: CoordinatableDelegate?

    // MARK: - Computed Properties

    /// Saved playlists/albums.
    var playlists: [DownloadedPlaylist] {
        downloadManager.playlists
    }

    /// Individual downloads not in any playlist.
    var looseSongs: [DownloadedSong] {
        downloadManager.looseSongs
    }

    /// All completed downloads.
    var downloads: [DownloadedSong] {
        downloadManager.downloads
    }

    /// Active and pending download tasks.
    var activeTasks: [DownloadTaskInfo] {
        downloadManager.activeTasks
    }

    /// Whether there are any active downloads.
    var hasActiveTasks: Bool {
        !activeTasks.isEmpty
    }

    /// Total downloaded size display string.
    var totalSizeDisplay: String {
        downloadManager.totalDownloadSizeDisplay
    }

    /// Whether there are any downloads at all.
    var isEmpty: Bool {
        downloads.isEmpty && activeTasks.isEmpty
    }

    // MARK: - Playlist Helpers

    /// Returns downloaded songs for a playlist, in playlist order.
    func songs(for playlist: DownloadedPlaylist) -> [DownloadedSong] {
        playlist.songIds.compactMap { videoId in
            downloadManager.downloads.first { $0.id == videoId }
        }
    }

    /// Download progress for a playlist (completed / total).
    func playlistProgress(_ playlist: DownloadedPlaylist) -> (downloaded: Int, total: Int) {
        let downloaded = playlist.songIds.filter { downloadManager.isDownloaded(videoId: $0) }.count
        return (downloaded, playlist.songIds.count)
    }

    /// Total size of a downloaded playlist.
    func playlistSize(_ playlist: DownloadedPlaylist) -> String {
        let totalBytes = songs(for: playlist).reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    // MARK: - Playback Actions

    /// Plays a downloaded song.
    func play(_ song: Song) {
        Task {
            await playerManager.play(song: song)
        }
    }

    /// Plays all downloaded songs as a queue.
    func playAll() {
        let songs = downloads.map(\.song)
        guard !songs.isEmpty else { return }
        Task {
            await playerManager.playQueue(songs, startingAt: 0)
        }
    }

    /// Shuffles and plays all downloaded songs.
    func shuffleAll() {
        let songs = downloads.map(\.song).shuffled()
        guard !songs.isEmpty else { return }
        Task {
            await playerManager.playQueue(songs, startingAt: 0)
        }
    }

    /// Plays all songs in a downloaded playlist.
    func playPlaylist(_ playlist: DownloadedPlaylist) {
        let songs = songs(for: playlist).map(\.song)
        guard !songs.isEmpty else { return }
        Task {
            await playerManager.playQueue(songs, startingAt: 0)
        }
    }

    /// Shuffles and plays a downloaded playlist.
    func shufflePlaylist(_ playlist: DownloadedPlaylist) {
        let songs = songs(for: playlist).map(\.song).shuffled()
        guard !songs.isEmpty else { return }
        Task {
            await playerManager.playQueue(songs, startingAt: 0)
        }
    }

    // MARK: - Navigation

    /// Navigate to a downloaded playlist's detail view.
    func selectPlaylist(_ playlist: DownloadedPlaylist) {
        let p = Playlist(
            id: playlist.id,
            title: playlist.title,
            description: nil,
            thumbnailURL: playlist.thumbnailURL,
            trackCount: playlist.songIds.count,
            author: playlist.author
        )
        delegate?.didSelectPlaylist(p)
    }

    // MARK: - Delete Actions

    /// Deletes a downloaded song.
    func deleteDownload(_ download: DownloadedSong) {
        downloadManager.deleteDownload(videoId: download.id)
    }

    /// Deletes a downloaded playlist and its unique songs.
    func deletePlaylist(_ playlist: DownloadedPlaylist) {
        downloadManager.deletePlaylist(playlistId: playlist.id)
    }

    /// Deletes all downloads, playlists, and cancels active tasks.
    func deleteAll() {
        downloadManager.deleteAllDownloads()
    }

    /// Cancels an active download.
    func cancelDownload(_ task: DownloadTaskInfo) {
        downloadManager.cancel(videoId: task.id)
    }

    /// Retries a failed download.
    func retryDownload(_ task: DownloadTaskInfo) {
        Task {
            await downloadManager.retry(videoId: task.id)
        }
    }
}

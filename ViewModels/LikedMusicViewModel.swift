import Foundation
import Observation
import FactoryKit
import os

/// View model for the Liked Music view.
@MainActor
@Observable
final class LikedMusicViewModel {
    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Liked songs.
    private(set) var songs: [Song] = []

    /// The API client.
    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    /// Song like status manager for caching.
    @ObservationIgnored
    @Injected(\.songLikeStatusManager) private var likeStatusManager

    private let logger = DiagnosticsLogger.api

    init() {}

    /// Loads liked songs.
    func load() async {
        guard self.loadingState != .loading else { return }

        self.loadingState = .loading
        self.logger.info("Loading liked songs")

        do {
            let loadedSongs = try await self.client.getLikedSongs()
            // Mark all songs as liked since they come from the liked songs API
            self.songs = loadedSongs.map { song in
                var mutableSong = song
                mutableSong.likeStatus = .like
                return mutableSong
            }
            // Also populate the like status manager cache
            for song in self.songs {
                self.likeStatusManager.setStatus(.like, for: song.videoId)
            }
            self.loadingState = .loaded
            self.logger.info("Loaded \(loadedSongs.count) liked songs")
        } catch is CancellationError {
            // Task was cancelled (e.g., user navigated away) — reset to idle so it can retry
            self.logger.debug("Liked songs load cancelled")
            self.loadingState = .idle
        } catch {
            self.logger.error("Failed to load liked songs: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Refreshes liked songs.
    func refresh() async {
        self.songs = []
        await self.load()
    }
}

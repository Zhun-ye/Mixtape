import Foundation
import FactoryKit
import Observation
import os

// MARK: - LibraryRepository

/// Repository that manages library data (playlists, artists, albums).
/// Centralizes library state and provides staggered loading to avoid rate limiting.
@MainActor
@Observable
final class LibraryRepository: LibraryRepositoryProtocol {
    /// Delay between fetching playlists and fetching artists/albums.
    private static let fetchDelayNanoseconds: UInt64 = 500_000_000 // 500ms

    /// Delay before refreshing library after a mutation (2 seconds).
    private static let refreshDelayNanoseconds: UInt64 = 2_000_000_000

    // MARK: - Loading States

    private(set) var playlistsLoadingState: LoadingState = .idle
    private(set) var artistsLoadingState: LoadingState = .idle
    private(set) var albumsLoadingState: LoadingState = .idle

    // MARK: - Data

    private(set) var playlists: [Playlist] = []
    private(set) var artists: [Artist] = []
    private(set) var albums: [Album] = []

    private(set) var libraryPlaylistIds: Set<String> = []
    private(set) var libraryAlbumIds: Set<String> = []

    // MARK: - Dependencies

    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    private let logger = DiagnosticsLogger.api

    /// Task for scheduled refresh after mutations.
    @ObservationIgnored
    private var scheduledRefreshTask: Task<Void, Never>?

    /// Task for async loading operations.
    var asyncTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }

    /// Callback invoked when library data changes.
    @ObservationIgnored
    var onDataChanged: (() -> Void)?

    // MARK: - Initialization

    init() {
        asyncTask = Task {
            await load()
        }
    }

    // MARK: - Loading

    /// Starts loading library data with staggered fetching.
    /// Playlists load first, then artists and albums after a short delay.
    func load() async {

        await self.loadPlaylists()

        await self.loadAlbums()

        await self.loadArtists()
    }

    /// Refreshes all library data.
    func refresh() async {
        // Clear existing data
        self.playlists = []
        self.artists = []
        self.albums = []
        self.libraryPlaylistIds = []
        self.libraryAlbumIds = []

        // Reset loading states
        self.playlistsLoadingState = .idle
        self.artistsLoadingState = .idle
        self.albumsLoadingState = .idle

        // Reload everything
        await self.load()
    }

    // MARK: - Private Loading Methods

    private func loadPlaylists() async {
        guard self.playlistsLoadingState != .loading else { return }

        self.playlistsLoadingState = .loading
        self.logger.info("Loading library playlists")

        do {
            let playlists = try await self.client.getLibraryPlaylists()
            self.playlists = playlists
            self.libraryPlaylistIds = Set(playlists.map(\.id))
            self.playlistsLoadingState = .loaded
            self.logger.info("Loaded \(playlists.count) playlists")
            self.onDataChanged?()
        } catch is CancellationError {
            self.logger.debug("Playlists load cancelled")
            self.playlistsLoadingState = .idle
        } catch {
            self.logger.error("Failed to load playlists: \(error.localizedDescription)")
            self.playlistsLoadingState = .error(LoadingError(from: error))
        }
    }

    private func loadArtists() async {
        guard self.artistsLoadingState != .loading else { return }

        self.artistsLoadingState = .loading
        self.logger.info("Loading library artists")

        do {
            let artists = try await self.client.getLibraryArtists()
            self.artists = artists
            self.artistsLoadingState = .loaded
            self.logger.info("Loaded \(artists.count) artists")
            self.onDataChanged?()
        } catch is CancellationError {
            self.logger.debug("Artists load cancelled")
            self.artistsLoadingState = .idle
        } catch {
            self.logger.error("Failed to load artists: \(error.localizedDescription)")
            self.artistsLoadingState = .error(LoadingError(from: error))
        }
    }

    private func loadAlbums() async {
        guard self.albumsLoadingState != .loading else { return }

        self.albumsLoadingState = .loading
        self.logger.info("Loading library albums")

        do {
            let albums = try await self.client.getLibraryAlbums()
            self.albums = albums
            self.libraryAlbumIds = Set(albums.map(\.id))
            self.albumsLoadingState = .loaded
            self.logger.info("Loaded \(albums.count) albums")
            self.onDataChanged?()
        } catch is CancellationError {
            self.logger.debug("Albums load cancelled")
            self.albumsLoadingState = .idle
        } catch {
            self.logger.error("Failed to load albums: \(error.localizedDescription)")
            self.albumsLoadingState = .error(LoadingError(from: error))
        }
    }

    // MARK: - Playlist Lookup

    func isInLibrary(playlistId: String) -> Bool {
        // Normalize the ID for comparison (remove VL prefix if present)
        let normalizedId = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        return self.libraryPlaylistIds.contains { storedId in
            let normalizedStoredId = storedId.hasPrefix("VL") ? String(storedId.dropFirst(2)) : storedId
            return normalizedId == normalizedStoredId || playlistId == storedId
        }
    }

    func addToLibrarySet(playlistId: String) {
        self.libraryPlaylistIds.insert(playlistId)
    }

    func removeFromLibrarySet(playlistId: String) {
        // Remove both the exact ID and normalized versions
        self.libraryPlaylistIds.remove(playlistId)
        let normalizedId = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        self.libraryPlaylistIds = self.libraryPlaylistIds.filter { storedId in
            let normalizedStoredId = storedId.hasPrefix("VL") ? String(storedId.dropFirst(2)) : storedId
            return normalizedId != normalizedStoredId
        }
    }

    // MARK: - Album Lookup

    func isAlbumInLibrary(albumId: String) -> Bool {
        self.libraryAlbumIds.contains(albumId)
    }

    func addAlbumToLibrarySet(albumId: String) {
        self.libraryAlbumIds.insert(albumId)
    }

    func removeAlbumFromLibrarySet(albumId: String) {
        self.libraryAlbumIds.remove(albumId)
    }

    // MARK: - Library Mutations

    /// Adds a playlist or album to the user's library.
    func addToLibrary(_ playlist: Playlist) async throws {
        self.logger.info("Adding to library: \(playlist.title)")

        // Call YouTube Music API
        try await self.client.subscribeToPlaylist(playlistId: playlist.libraryId)

        // Optimistic update
        if playlist.isAlbum {
            self.addAlbumToLibrarySet(albumId: playlist.id)
        } else {
            self.addToLibrarySet(playlistId: playlist.id)
        }

        self.logger.info("Added to library: \(playlist.title)")

        // Schedule delayed refresh
        self.scheduleRefresh()
    }

    /// Removes a playlist or album from the user's library.
    func removeFromLibrary(_ playlist: Playlist) async throws {
        self.logger.info("Removing from library: \(playlist.title)")

        // Call YouTube Music API
        try await self.client.unsubscribeFromPlaylist(playlistId: playlist.libraryId)

        // Optimistic update
        if playlist.isAlbum {
            self.removeAlbumFromLibrarySet(albumId: playlist.id)
        } else {
            self.removeFromLibrarySet(playlistId: playlist.id)
        }

        self.logger.info("Removed from library: \(playlist.title)")

        // Schedule delayed refresh
        self.scheduleRefresh()
    }

    // MARK: - Scheduled Refresh

    /// Schedules a delayed refresh of library data.
    /// If a refresh is already scheduled, it resets the timer.
    private func scheduleRefresh() {
        // Cancel any existing scheduled refresh
        self.scheduledRefreshTask?.cancel()

        self.scheduledRefreshTask = Task {
            do {
                try await Task.sleep(nanoseconds: Self.refreshDelayNanoseconds)
                await self.load()
            } catch {
                // Task was cancelled, ignore
            }
        }
    }
}

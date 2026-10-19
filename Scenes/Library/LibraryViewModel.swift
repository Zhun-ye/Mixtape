import Foundation
import Observation
import FactoryKit
import SwiftUINavigation
import os

/// Display mode for library content.
enum LibraryDisplayMode: String, CaseIterable {
    case list
    case grid
}

/// Sort order for library content.
enum LibrarySortOrder: String, CaseIterable {
    case recentlyAdded
    case aToZ
    case zToA
    case mostSongs

    var displayName: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .aToZ: "A to Z"
        case .zToA: "Z to A"
        case .mostSongs: "Most Songs"
        }
    }
}

/// View model for the Library view.
@MainActor
@Observable
final class LibraryViewModel: HashableObject {
    /// Player service for playback.
    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    /// Library repository for data access.
    @ObservationIgnored
    @Injected(\.libraryRepository) private var repository

    /// The client for playlist detail loading.
    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    /// Download manager for offline content.
    @ObservationIgnored
    @Injected(\.downloadManager) private var downloadManager

    /// Delegate for navigation events.
    weak var delegate: CoordinatableDelegate?

    /// Display mode for artists view (persisted in AppDefaults).
    var artistsDisplayMode: LibraryDisplayMode = AppDefaults.shared.libraryArtistsDisplayMode {
        didSet { AppDefaults.shared.libraryArtistsDisplayMode = artistsDisplayMode }
    }

    /// Sort order for artists view (persisted in AppDefaults).
    var artistsSortOrder: LibrarySortOrder = AppDefaults.shared.libraryArtistsSortOrder {
        didSet { AppDefaults.shared.libraryArtistsSortOrder = artistsSortOrder }
    }

    /// Sorted artists based on current sort order.
    var sortedArtists: [Artist] {
        switch artistsSortOrder {
        case .recentlyAdded:
            return repository.artists
        case .aToZ:
            return repository.artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .zToA:
            return repository.artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .mostSongs:
            return repository.artists.sorted { ($0.songCount ?? 0) > ($1.songCount ?? 0) }
        }
    }

    /// Selected artist for split view.
    var selectedArtist: Artist? {
        didSet {
            if let artist = selectedArtist {
                let viewModel = ArtistDetailViewModel(artist: artist)
                viewModel.delegate = delegate
                selectedArtistViewModel = viewModel
            } else {
                selectedArtistViewModel = nil
            }
        }
    }

    /// View model for the selected artist.
    private(set) var selectedArtistViewModel: ArtistDetailViewModel?


    /// Selected playlist detail.
    private(set) var selectedPlaylistDetail: PlaylistDetail?

    /// Loading state for playlist detail.
    private(set) var playlistDetailLoadingState: LoadingState = .idle

    private let logger = DiagnosticsLogger.api

    var asyncTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }

    init() {
        // Subscribe to repository data changes
        repository.onDataChanged = { [weak self] in
            self?.syncFromRepository()
        }

        // Sync initial data if repository already loaded
        syncFromRepository()
    }

    // MARK: - Data

    /// User's playlists.
    private(set) var playlists: [Playlist] = []

    /// User's artists.
    private(set) var artists: [Artist] = []

    /// User's albums.
    private(set) var albums: [Album] = []

    private(set) var loadingState: LoadingState = .idle

    // MARK: - Downloads

    /// Whether there are any downloads or active download tasks.
    var hasDownloads: Bool {
        !downloadManager.downloads.isEmpty || !downloadManager.activeTasks.isEmpty
    }

    /// Number of completed downloads.
    var downloadCount: Int { downloadManager.downloads.count }

    /// Formatted total download size.
    var downloadSizeDisplay: String { downloadManager.totalDownloadSizeDisplay }

    /// Number of active download tasks.
    var activeDownloadCount: Int { downloadManager.activeTasks.count }

    /// Thumbnail URLs for recent downloads (playlists first, then loose songs).
    var recentDownloadThumbnails: [URL?] {
        var urls: [URL?] = []
        var seen = Set<String>()

        for playlist in downloadManager.playlists {
            let key = playlist.thumbnailURL?.absoluteString ?? playlist.id
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            urls.append(playlist.thumbnailURL)
            if urls.count >= 5 { return urls }
        }

        for song in downloadManager.looseSongs {
            let key = song.song.thumbnailURL?.absoluteString ?? song.id
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            urls.append(song.song.thumbnailURL)
            if urls.count >= 5 { return urls }
        }

        return urls
    }

    // MARK: - Navigation Actions

    func didSelectPlaylist(_ playlist: Playlist) {
        delegate?.didSelectPlaylist(playlist)
    }

    func didSelectArtist(_ artist: Artist) {
        delegate?.didSelectArtist(artist)
    }

    func didRequestSettings() {
        delegate?.didRequestSettings()
    }

    func didSelectDownloads() {
        delegate?.didSelectDownloads()
    }

    /// Checks if a playlist is in the user's library.
    func isInLibrary(playlistId: String) -> Bool {
        repository.isInLibrary(playlistId: playlistId)
    }

    /// Adds a playlist ID to the library set (called after successful add to library).
    func addToLibrarySet(playlistId: String) {
        repository.addToLibrarySet(playlistId: playlistId)
    }

    /// Removes a playlist ID from the library set (called after successful remove from library).
    func removeFromLibrarySet(playlistId: String) {
        repository.removeFromLibrarySet(playlistId: playlistId)
    }

    /// Syncs local data from repository.
    private func syncFromRepository() {
        updatePlaylists(with: repository.playlists)
        updateArtists(with: repository.artists)
        updateAlbums(with: repository.albums)

        // Update loading state based on repository state
        if repository.playlistsLoadingState == .loaded {
            loadingState = .loaded
        }
    }

    /// Refreshes library content. When offline, skips the network load and
    /// surfaces the downloads section immediately.
    func refresh() {
        asyncTask = Task {
            let repo = repository
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await repo.load() }
                group.addTask { try? await Task.sleep(for: .seconds(15)) }
                await group.next()
                group.cancelAll()
            }
            loadingState = .loaded
        }
    }

    // MARK: - Data Management

    /// Updates playlists with fresh data, skipping update if unchanged.
    private func updatePlaylists(with newPlaylists: [Playlist]) {
        let deduplicated = newPlaylists.uniqued(by: \.id)
        guard playlists != deduplicated else {
            logger.debug("Playlists unchanged, skipping update")
            return
        }
        logger.info("Updating playlists: \(deduplicated.count) items")
        playlists = deduplicated
    }

    /// Updates artists with fresh data, skipping update if unchanged.
    private func updateArtists(with newArtists: [Artist]) {
        let deduplicated = newArtists.uniqued(by: \.id)
        guard artists != deduplicated else {
            logger.debug("Artists unchanged, skipping update")
            return
        }
        logger.info("Updating artists: \(deduplicated.count) items")
        artists = deduplicated
    }

    /// Updates albums with fresh data, skipping update if unchanged.
    private func updateAlbums(with newAlbums: [Album]) {
        let deduplicated = newAlbums.uniqued(by: \.id)
        guard albums != deduplicated else {
            logger.debug("Albums unchanged, skipping update")
            return
        }
        logger.info("Updating albums: \(deduplicated.count) items")
        albums = deduplicated
    }

    /// Loads a specific playlist's details.
    func loadPlaylist(id: String) async {
        guard self.playlistDetailLoadingState != .loading else { return }

        self.playlistDetailLoadingState = .loading
        self.logger.info("Loading playlist: \(id)")

        do {
            let detail = try await client.getPlaylist(id: id)
            self.selectedPlaylistDetail = detail
            self.playlistDetailLoadingState = .loaded
            let trackCount = detail.tracks.count
            self.logger.info("Loaded playlist with \(trackCount) tracks")
        } catch is CancellationError {
            self.logger.debug("Playlist load cancelled")
            self.playlistDetailLoadingState = .idle
        } catch {
            self.logger.error("Failed to load playlist: \(error.localizedDescription)")
            self.playlistDetailLoadingState = .error(LoadingError(from: error))
        }
    }

    /// Clears the selected playlist.
    func clearSelectedPlaylist() {
        self.selectedPlaylistDetail = nil
        self.playlistDetailLoadingState = .idle
    }

    /// Checks if an album is in the user's library.
    func isAlbumInLibrary(albumId: String) -> Bool {
        repository.isAlbumInLibrary(albumId: albumId)
    }

    /// Adds an album ID to the library set.
    func addAlbumToLibrarySet(albumId: String) {
        repository.addAlbumToLibrarySet(albumId: albumId)
    }

    /// Removes an album ID from the library set.
    func removeAlbumFromLibrarySet(albumId: String) {
        repository.removeAlbumFromLibrarySet(albumId: albumId)
    }

    /// Plays a playlist.
    func playPlaylist(_ playlist: Playlist) async {
        do {
            let detail = try await self.client.getPlaylist(id: playlist.id)
            guard !detail.tracks.isEmpty else { return }
            await playerManager.playQueue(detail.tracks, startingAt: 0, from: playlist)
        } catch {
            self.logger.error("Failed to play playlist: \(error.localizedDescription)")
        }
    }

    /// Plays an album.
    func playAlbum(_ album: Album) async {
        do {
            let detail = try await self.client.getPlaylist(id: album.id)
            guard !detail.tracks.isEmpty else { return }
            let albumAsPlaylist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL,
                trackCount: album.trackCount,
                author: album.artistsDisplay
            )
            await playerManager.playQueue(detail.tracks, startingAt: 0, from: albumAsPlaylist)
        } catch {
            self.logger.error("Failed to play album: \(error.localizedDescription)")
        }
    }
}

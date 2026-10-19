import Foundation
import Observation
import os
import SwiftUINavigation
import FactoryKit

/// View model for the ArtistDetailView.
@MainActor
@Observable
final class ArtistDetailViewModel: HashableObject {
    /// Player service for playback.
    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    /// Delegate for navigation events.
    @ObservationIgnored
    weak var delegate: CoordinatableDelegate?

    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// The loaded artist detail.
    private(set) var artistDetail: ArtistDetail?

    /// Whether a subscription operation is in progress.
    private(set) var isSubscribing: Bool = false

    /// Whether to show all songs instead of limited preview.
    var showAllSongs: Bool = false

    /// Number of songs to show in preview mode (4 songs per page × 5 pages).
    static let previewSongCount = 20

    /// Number of albums to show in preview mode.
    static let previewAlbumCount = 10

    let artist: Artist

    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    private let logger = DiagnosticsLogger.api

    var asyncTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }

    init(artist: Artist) {
        self.artist = artist
        asyncTask = Task {
            await load()
        }
    }

    /// Navigate to top songs detail view.
    func showTopSongs() {
        guard let detail = artistDetail else { return }
        let destination = TopSongsDestination(
            artistId: detail.id,
            artistName: detail.name,
            songs: allSongs ?? detail.songs,
            songsBrowseId: detail.songsBrowseId,
            songsParams: detail.songsParams
        )
        delegate?.didSelectTopSongs(destination)
    }

    /// Navigate to all albums in a section.
    func showAllAlbums(in section: AlbumSection) {
        delegate?.didSelectAllAlbums(section)
    }

    /// Navigate to album detail.
    func didSelectAlbum(_ album: Album) {
        delegate?.didSelectAlbum(album)
    }

    /// Navigate to playlist detail.
    func didSelectPlaylist(_ playlist: Playlist) {
        delegate?.didSelectPlaylist(playlist)
    }

    /// Loads the artist details including songs and albums.
    func load() async {
        guard self.loadingState != .loading else { return }

        self.loadingState = .loading
        let artistName = self.artist.name
        self.logger.info("Loading artist: \(artistName)")

        do {
            var detail = try await client.getArtist(id: self.artist.id)

            // Use original artist info as fallback if API returned unknown/empty values
            if detail.name == "Unknown Artist", self.artist.name != "Unknown Artist" {
                let mergedArtist = Artist(
                    id: artist.id,
                    name: self.artist.name,
                    thumbnailURL: detail.thumbnailURL ?? self.artist.thumbnailURL
                )
                detail = ArtistDetail(
                    artist: mergedArtist,
                    description: detail.description,
                    songs: detail.songs,
                    albumSections: detail.albumSections,
                    thumbnailURL: detail.thumbnailURL ?? self.artist.thumbnailURL,
                    channelId: detail.channelId,
                    isSubscribed: detail.isSubscribed,
                    subscriberCount: detail.subscriberCount,
                    hasMoreSongs: detail.hasMoreSongs,
                    songsBrowseId: detail.songsBrowseId,
                    songsParams: detail.songsParams
                )
            }

            self.artistDetail = detail
            let songCount = detail.songs.count
            self.logger.info("Artist loaded: \(songCount) songs")

            // Fetch more songs if available, then mark as loaded
            if let browseId = detail.songsBrowseId {
                self.logger.info("Fetching additional songs: \(browseId)")
                do {
                    let moreSongs = try await client.getArtistSongs(
                        browseId: browseId,
                        params: detail.songsParams
                    )
                    if !moreSongs.isEmpty {
                        self.allSongs = moreSongs
                        self.logger.info("Fetched \(moreSongs.count) total songs")
                    }
                } catch {
                    self.logger.warning("Failed to fetch additional songs: \(error.localizedDescription)")
                }
            }

            self.loadingState = .loaded
        } catch is CancellationError {
            // Task was cancelled (e.g., user navigated away) — reset to idle so it can retry
            self.logger.debug("Artist detail load cancelled")
            self.loadingState = .idle
        } catch {
            self.logger.error("Failed to load artist: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Refreshes the artist details.
    func refresh() async {
        self.artistDetail = nil
        self.showAllSongs = false
        await self.load()
    }

    /// Toggles subscription status for the artist.
    func toggleSubscription() async {
        guard let detail = artistDetail,
              let channelId = detail.channelId
        else {
            self.logger.warning("Cannot toggle subscription: missing channel ID")
            return
        }

        self.isSubscribing = true
        defer { isSubscribing = false }

        do {
            if detail.isSubscribed {
                try await self.client.unsubscribeFromArtist(channelId: channelId)
                self.artistDetail?.isSubscribed = false
                self.logger.info("Unsubscribed from artist: \(detail.name)")
            } else {
                try await self.client.subscribeToArtist(channelId: channelId)
                self.artistDetail?.isSubscribed = true
                self.logger.info("Subscribed to artist: \(detail.name)")
            }
        } catch {
            self.logger.error("Failed to toggle subscription: \(error.localizedDescription)")
        }
    }

    /// All available songs - prefers fetched allSongs, falls back to artistDetail.songs.
    private var availableSongs: [Song] {
        if let allSongs {
            return allSongs
        }
        return artistDetail?.songs ?? []
    }

    /// The songs to display based on showAllSongs state.
    var displayedSongs: [Song] {
        let songs = availableSongs
        if songs.isEmpty { return [] }
        if self.showAllSongs {
            return songs
        }
        return Array(songs.prefix(Self.previewSongCount))
    }

    /// Whether there are more songs to show (either loaded or available via API).
    var hasMoreSongs: Bool {
        guard let detail = artistDetail else { return false }
        // Show chevron if we have more songs than currently displayed
        let displayedCount = displayedSongs.count
        let totalLoaded = allSongs?.count ?? detail.songs.count
        return totalLoaded > displayedCount || detail.hasMoreSongs
    }

    /// The album sections to display.
    var displayedAlbumSections: [AlbumSection] {
        artistDetail?.albumSections ?? []
    }

    /// Returns the albums to display for a section (limited to preview count).
    func albumsToDisplay(for section: AlbumSection) -> [Album] {
        Array(section.albums.prefix(Self.previewAlbumCount))
    }

    /// Whether there are more albums in the given section.
    func hasMoreAlbums(in section: AlbumSection) -> Bool {
        // Show chevron if we're truncating locally, or if the carousel is full and has a "more" endpoint
        section.albums.count > Self.previewAlbumCount ||
            (section.hasMore && section.albums.count >= Self.previewAlbumCount)
    }

    /// All songs for the artist (fetched on demand).
    private(set) var allSongs: [Song]?

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

    /// Fetches all songs for the artist if not already loaded.
    /// Returns all songs for queue playback.
    func getAllSongs() async -> [Song] {
        // If we already have all songs cached, return them
        if let allSongs {
            return allSongs
        }

        // If there's no browse ID, we already have all the songs
        guard let detail = artistDetail,
              let browseId = detail.songsBrowseId
        else {
            return availableSongs
        }

        self.logger.info("Fetching all artist songs for queue: \(browseId)")

        do {
            let songs = try await client.getArtistSongs(
                browseId: browseId,
                params: detail.songsParams
            )

            if !songs.isEmpty {
                self.allSongs = songs
                return songs
            }
        } catch {
            self.logger.warning("Failed to fetch all songs: \(error.localizedDescription)")
        }

        // Fallback to existing songs
        return availableSongs
    }
}

import Foundation
import Observation
import FactoryKit
import SwiftUINavigation
import os

/// View model for the AllAlbumsView.
@MainActor
@Observable
final class AllAlbumsViewModel: HashableObject {
    /// Player service for playback.
    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    /// Delegate for navigation events.
    @ObservationIgnored
    weak var delegate: CoordinatableDelegate?

    /// The album section to display.
    let section: AlbumSection

    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    private let logger = DiagnosticsLogger.api

    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// All fetched albums (nil if not yet fetched).
    private var fetchedAlbums: [Album]?

    var asyncTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }

    /// All albums in this section (fetched or initial).
    var albums: [Album] {
        fetchedAlbums ?? section.albums
    }

    /// The section title for display.
    var title: String {
        section.title
    }

    init(section: AlbumSection) {
        self.section = section
        // Fetch all albums if there's a browse endpoint
        if section.hasMore {
            asyncTask = Task {
                await load()
            }
        }
    }

    /// Loads all albums from the browse endpoint.
    func load() async {
        guard let browseId = section.moreBrowseId else { return }
        guard loadingState != .loading else { return }

        loadingState = .loading
        logger.info("Loading all albums for section: \(self.section.title)")

        do {
            let albums = try await client.getArtistAlbums(
                browseId: browseId,
                params: section.moreParams
            )
            if !albums.isEmpty {
                self.fetchedAlbums = albums
                logger.info("Loaded \(albums.count) albums for section: \(self.section.title)")
            }
            loadingState = .loaded
        } catch is CancellationError {
            loadingState = .idle
        } catch {
            logger.error("Failed to load albums: \(error.localizedDescription)")
            loadingState = .error(LoadingError(from: error))
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

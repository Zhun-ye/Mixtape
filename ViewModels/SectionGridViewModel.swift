import Foundation
import Observation
import FactoryKit
import SwiftUINavigation

@MainActor
@Observable
final class SectionGridViewModel: HashableObject {
    /// Player service for playback.
    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    /// Delegate for navigation events.
    weak var delegate: CoordinatableDelegate?

    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// The section to display.
    let section: HomeSection

    /// Items to display in the grid.
    private(set) var items: [HomeSectionItem] = []

    /// The API client.
    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    var asyncTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }

    init(section: HomeSection) {
        self.section = section
    }

    // MARK: - Navigation Actions

    func didSelectPlaylist(_ playlist: Playlist) {
        delegate?.didSelectPlaylist(playlist)
    }

    func didSelectArtist(_ artist: Artist) {
        delegate?.didSelectArtist(artist)
    }

    func didSelectAlbum(_ album: Album) {
        delegate?.didSelectAlbum(album)
    }

    /// Loads section items.
    func load() async {
        guard self.loadingState != .loading else { return }

        self.loadingState = .loading

        // Simulate loading - in reality, items are already in the section
        self.items = section.items
        self.loadingState = .loaded
    }

    /// Refreshes section items.
    func refresh() {
        items = []
        asyncTask = Task {
            await load()
        }
    }

    // MARK: - Play Actions

    func playPlaylist(_ playlist: Playlist) async {
        do {
            let detail = try await self.client.getPlaylist(id: playlist.id)
            guard !detail.tracks.isEmpty else { return }
            await playerManager.playQueue(detail.tracks, startingAt: 0, from: playlist)
        } catch {
            // Silently fail - user can tap to navigate and play from detail view
        }
    }

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
            // Silently fail - user can tap to navigate and play from detail view
        }
    }
}

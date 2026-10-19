import Foundation
import Observation
import SwiftUINavigation
import FactoryKit
import os

/// View model for a moods/genres category detail view.
@MainActor
@Observable
final class MoodCategoryViewModel: HashableObject {
    /// Player service for playback.
    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    /// Delegate for navigation events.
    weak var delegate: CoordinatableDelegate?

    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Sections of content for this category.
    private(set) var sections: [HomeSection] = []

    /// The category being displayed.
    let category: MoodCategory

    /// The API client.
    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    private let logger = DiagnosticsLogger.api

    init(category: MoodCategory) {
        self.category = category
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

    func didSelectSection(_ section: HomeSection) {
        delegate?.didSelectSection(section)
    }

    /// Loads the category content.
    func load() async {
        guard self.loadingState != .loading else { return }

        self.loadingState = .loading
        let title = self.category.title
        self.logger.info("Loading mood category: \(title)")

        do {
            let response = try await client.getMoodCategory(
                browseId: self.category.browseId,
                params: self.category.params
            )
            self.sections = response.sections
            self.loadingState = .loaded
            let sectionCount = self.sections.count
            self.logger.info("Mood category '\(title)' loaded: \(sectionCount) sections")
        } catch is CancellationError {
            self.logger.debug("Mood category load cancelled")
            self.loadingState = .idle
        } catch {
            self.logger.error("Failed to load mood category: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Refreshes the category content.
    func refresh() async {
        self.sections = []
        await self.load()
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

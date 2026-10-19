import Foundation
import Observation
import FactoryKit
import SwiftUI
import SwiftUINavigation
import os

/// View model for the Explore view.
@MainActor
@Observable
final class DiscoveryViewModel: HashableObject {
    /// Player service for playback.
    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    /// Delegate for navigation events.
    weak var delegate: CoordinatableDelegate?

    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Explore sections to display.
    private(set) var sections: [HomeSection] = []

    /// The client.
    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    @ObservationIgnored
    @Injected(\.networkMonitor) private var networkMonitor

    private let logger = DiagnosticsLogger.api

    var asyncTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }

    init() {
        asyncTask = Task { await load() }
        observeConnectivity()
    }

    private func observeConnectivity() {
        withObservationTracking {
            _ = networkMonitor.isConnected
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.networkMonitor.isConnected else {
                    self?.observeConnectivity()
                    return
                }
                self.refresh()
                self.observeConnectivity()
            }
        }
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
        // If this is a mood/genre section, navigate to dedicated moods & genres view
        if isMoodGenreSection(section) {
            delegate?.didSelectMoodsAndGenres()
        } else {
            delegate?.didSelectSection(section)
        }
    }
  
    func didRequestSettings() {
        delegate?.didRequestSettings()
    }

    /// Loads explore content.
    func load() async {
        guard networkMonitor.isConnected else {
            if sections.isEmpty {
                loadingState = .error(.offline)
            }
            return
        }
        do {
            let allSections = try await client.getExplore()
            let chartsResponse = try? await client.getCharts()

            // Filter out Charts section from explore (keep mood/genre so user can tap "all")
            let exploreSections = allSections.filter { !isChartsSection($0) }
            let chartsSections = chartsResponse?.sections ?? []

            withAnimation {
                sections = exploreSections + chartsSections
            }
            loadingState = .loaded
        } catch is CancellationError {
            logger.debug("Explore load cancelled")
            loadingState = .idle
        } catch {
            logger.error("Failed to load explore: \(error.localizedDescription)")
            loadingState = .error(LoadingError(from: error))
        }
    }

    /// Refreshes explore content.
    func refresh() {
        guard networkMonitor.isConnected else { return }
        withAnimation {
            sections = []
        }
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

    // MARK: - Private Helpers

    /// Determines if a section is a Charts section (which should be filtered out).
    private func isChartsSection(_ section: HomeSection) -> Bool {
        section.title.lowercased() == "charts"
    }

    /// Determines if a section contains mood/genre playlists (which we replace with dedicated endpoint data).
    private func isMoodGenreSection(_ section: HomeSection) -> Bool {
        section.items.contains { item in
            if case let .playlist(playlist) = item {
                return playlist.isMoodOrGenreCategory
            }
            return false
        }
    }
}

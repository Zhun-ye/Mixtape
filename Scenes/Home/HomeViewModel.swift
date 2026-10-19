import Foundation
import Observation
import FactoryKit
import SwiftUI
import SwiftUINavigation
import os

/// View model for the Home view.
@MainActor
@Observable
final class HomeViewModel: HashableObject {

    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    @ObservationIgnored
    @Injected(\.networkMonitor) private var networkMonitor

    /// Continuation state for loading more sections.
    private var continuation: HomeResponse.Continuation?

    weak var delegate: CoordinatableDelegate?

    private(set) var loadingState: LoadingState = .idle

    /// Whether more sections can be loaded.
    var hasMoreSections: Bool { continuation != nil }

    /// Whether more sections are currently being loaded.
    private(set) var isLoadingMore: Bool = false

    /// Home sections to display.
    private(set) var sections: [HomeSection] = []

    private let logger = DiagnosticsLogger.api

    var asyncTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }

    /// Task for loading additional sections.
    private var loadMoreTask: Task<Void, Never>?

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

    func didRequestSettings() {
        delegate?.didRequestSettings()
    }

    init() {
        asyncTask = Task {
            await load()
        }
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

    /// Loads home content with fast initial load.
    func load() async {
        guard networkMonitor.isConnected else {
            if sections.isEmpty {
                loadingState = .error(.offline)
            }
            return
        }
        self.logger.info("Loading home content")

        do {
            let response = try await client.getHome()
            withAnimation {
                self.sections = response.sections
            }
            self.continuation = response.continuation
            self.loadingState = .loaded
            self.logger.info("Home content loaded: \(response.sections.count) sections, hasMore: \(response.hasMore)")
        } catch is CancellationError {
            // Task was cancelled (e.g., user navigated away) — reset to idle so it can retry
            self.logger.debug("Home load cancelled")
            self.loadingState = .idle
        } catch {
            self.logger.error("Failed to load home: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Loads more sections when user scrolls near the end.
    /// Called by `onScrollTargetVisibilityChange` with currently visible section IDs.
    func loadMoreIfNeeded(visibleSectionIDs: Set<HomeSection.ID>) {
        // Check if any of the last 2 sections are visible
        guard sections.count >= 2 else { return }
        let lastIDs = Set(sections.suffix(2).map(\.id))
        guard !lastIDs.isDisjoint(with: visibleSectionIDs) else { return }

        // Don't load if already loading, no more sections, or not in loaded state
        guard !isLoadingMore, hasMoreSections, loadingState == .loaded else { return }

        logger.info("Triggering load more sections (visible: \(visibleSectionIDs.count), total: \(self.sections.count))")
        isLoadingMore = true
        loadMoreTask = Task { [weak self] in
            await self?.loadMoreSections()
        }
    }

    /// Loads additional sections from continuation.
    private func loadMoreSections() async {
        guard let currentContinuation = continuation else {
            logger.info("No continuation available")
            isLoadingMore = false
            return
        }

        logger.info("Loading more home sections...")

        do {
            let response = try await client.getHomeContinuation(currentContinuation)
            let existingIDs = Set(sections.map(\.id))
            let newSections = response.sections.filter { !existingIDs.contains($0.id) }
            withAnimation {
                sections.append(contentsOf: newSections)
            }
            continuation = response.continuation
            logger.info("Loaded \(newSections.count) new sections (\(response.sections.count - newSections.count)), hasMore: \(response.hasMore)")
        } catch is CancellationError {
            logger.debug("Load more cancelled")
        } catch {
            logger.warning("Failed to load more sections: \(error.localizedDescription)")
        }

        isLoadingMore = false
    }

    /// Minimum number of sections to accept from a refresh response.
    /// The YouTube Music API returns ~3 sections per batch; fewer suggests a server-side inconsistency.
    private static let minimumSectionCount = 3

    /// Refreshes home content, keeping existing data if the API returns a suspiciously small response.
    func refresh() {
        guard networkMonitor.isConnected else { return }
        loadMoreTask?.cancel()
        asyncTask = Task {
            do {
                let response = try await client.getHome()
                let isReasonableResponse = response.sections.count >= Self.minimumSectionCount
                    || response.sections.count >= sections.count

                if sections.isEmpty || isReasonableResponse {
                    withAnimation {
                        self.sections = response.sections
                    }
                    self.continuation = response.continuation
                } else {
                    logger.warning("Refresh returned only \(response.sections.count) sections, keeping existing \(self.sections.count)")
                }
                self.loadingState = .loaded
            } catch is CancellationError {
                self.logger.debug("Home refresh cancelled")
            } catch {
                self.logger.error("Failed to refresh home: \(error.localizedDescription)")
            }
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

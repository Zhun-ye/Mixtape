import Foundation
import Observation
import os
import SwiftUINavigation
import FactoryKit

/// View model for the Charts view.
@MainActor
@Observable
final class ChartsViewModel: HashableObject {
    /// Player service for playback.
    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    /// Delegate for navigation events.
    weak var delegate: CoordinatableDelegate?

    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Chart sections to display.
    private(set) var sections: [HomeSection] = []

    /// Whether more sections are available to load.
    private(set) var hasMoreSections: Bool = true

    /// The API client.
    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    private let logger = DiagnosticsLogger.api

    /// Task for background loading of additional sections.
    private var backgroundLoadTask: Task<Void, Never>?

    /// Number of background continuations loaded.
    private var continuationsLoaded = 0

    /// Maximum continuations to load in background.
    private static let maxContinuations = 4

    var asyncTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }

    init() {}

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

    /// Loads charts content with fast initial load.
    func load() async {
        guard self.loadingState != .loading else { return }

        self.loadingState = .loading
        self.logger.info("Loading charts content")

        do {
            let response = try await client.getCharts()
            self.sections = response.sections
            self.hasMoreSections = self.client.hasMoreChartsSections
            self.loadingState = .loaded
            self.continuationsLoaded = 0
            let sectionCount = self.sections.count
            self.logger.info("Charts content loaded: \(sectionCount) sections")

            // Start background loading of additional sections
            self.startBackgroundLoading()
        } catch is CancellationError {
            // Task was cancelled (e.g., user navigated away) — reset to idle so it can retry
            self.logger.debug("Charts load cancelled")
            self.loadingState = .idle
        } catch {
            self.logger.error("Failed to load charts: \(error.localizedDescription)")
            self.loadingState = .error(LoadingError(from: error))
        }
    }

    /// Loads more sections in the background progressively.
    private func startBackgroundLoading() {
        self.backgroundLoadTask?.cancel()
        self.backgroundLoadTask = Task { [weak self] in
            guard let self else { return }

            // Brief delay to let the UI settle
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else { return }

            await self.loadMoreSections()
        }
    }

    /// Loads additional sections from continuations progressively.
    private func loadMoreSections() async {
        while self.hasMoreSections, self.continuationsLoaded < Self.maxContinuations {
            guard self.loadingState == .loaded else { break }

            do {
                if let additionalSections = try await client.getChartsContinuation() {
                    self.sections.append(contentsOf: additionalSections)
                    self.continuationsLoaded += 1
                    self.hasMoreSections = self.client.hasMoreChartsSections
                    let continuationNum = self.continuationsLoaded
                    self.logger.info("Background loaded \(additionalSections.count) more sections (continuation \(continuationNum))")
                } else {
                    self.hasMoreSections = false
                    break
                }
            } catch is CancellationError {
                self.logger.debug("Background loading cancelled")
                break
            } catch {
                self.logger.warning("Background section load failed: \(error.localizedDescription)")
                break
            }
        }

        let totalCount = self.sections.count
        self.logger.info("Background section loading completed, total sections: \(totalCount)")
    }

    /// Refreshes charts content.
    func refresh() {
        backgroundLoadTask?.cancel()
        sections = []
        hasMoreSections = true
        continuationsLoaded = 0
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

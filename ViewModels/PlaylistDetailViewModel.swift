import Foundation
import FoundationModels
import Observation
import SwiftUI
import SwiftUINavigation
import FactoryKit
import os

/// View model for the PlaylistDetailView.
@MainActor
@Observable
final class PlaylistDetailViewModel: HashableObject {
    /// Player service for playback.
    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    /// Library repository for checking library status.
    @ObservationIgnored
    @Injected(\.libraryRepository) private var libraryRepository

    /// Download manager for offline playback.
    @ObservationIgnored
    @Injected(\.downloadManager) private var downloadManager

    /// Network monitor for offline detection.
    @ObservationIgnored
    @Injected(\.networkMonitor) private var networkMonitor

    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// The loaded playlist detail.
    private(set) var playlistDetail: PlaylistDetail?

    /// The playlist being displayed.
    let playlist: Playlist

    // MARK: - Library State

    /// Tracks whether this playlist has been added to library in this session.
    var isAddedToLibrary: Bool = false

    /// Whether the playlist/album is in the user's library.
    var isInLibrary: Bool {
        if playlist.isAlbum {
            return libraryRepository.isAlbumInLibrary(albumId: playlist.id)
        }
        return libraryRepository.isInLibrary(playlistId: playlist.id)
    }

    /// Combined check for library status.
    var isCurrentlyInLibrary: Bool {
        isInLibrary || isAddedToLibrary
    }

    // MARK: - Artwork Color Palette

    /// Dynamic color palette extracted from artwork.
    var colorPalette: ColorExtractor.ColorPalette = .default

    private var colorExtractionTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    // MARK: - AI Refine State

    /// Whether the refine playlist sheet is visible.
    var showRefineSheet: Bool = false

    /// AI-generated playlist changes.
    var playlistChanges: PlaylistChanges?

    /// Whether AI is processing the refine request.
    var isRefining: Bool = false

    /// Error message from refine operation.
    var refineError: String?

    // MARK: - Private

    @ObservationIgnored
    @Injected(\.ytMusicClient) private var client

    private let logger = DiagnosticsLogger.api
    private let aiLogger = DiagnosticsLogger.ai

    var asyncTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }

    // MARK: - Initialization

    init(playlist: Playlist) {
        self.playlist = playlist

        asyncTask = Task {
            await load()
        }
    }

    // MARK: - Loading

    /// Loads the playlist details including tracks.
    func load() async {
        let playlistTitle = playlist.title
        logger.info("Loading playlist: \(playlistTitle)")

        if !networkMonitor.isConnected {
            if let offlineDetail = buildOfflineDetail() {
                playlistDetail = offlineDetail
                loadingState = .loaded
            } else {
                loadingState = .error(LoadingError(
                    title: "You're Offline",
                    message: "This content isn't available offline.",
                    isRetryable: false,
                    isOffline: true
                ))
            }
            return
        }

        do {
            var detail = try await client.getPlaylist(id: playlist.id)

            // Determine the best thumbnail to use:
            // 1. API response header thumbnail
            // 2. Original playlist thumbnail (from navigation)
            // 3. First track's thumbnail as fallback
            let resolvedThumbnailURL = detail.thumbnailURL
                ?? playlist.thumbnailURL
                ?? detail.tracks.first?.thumbnailURL

            // Check if we need to merge with original playlist info
            let needsMerge = detail.title == "Unknown Playlist" && playlist.title != "Unknown Playlist"
            let thumbnailMissing = detail.thumbnailURL == nil && resolvedThumbnailURL != nil

            if needsMerge || thumbnailMissing {
                // Merge with original playlist info or add fallback thumbnail
                let mergedPlaylist = Playlist(
                    id: playlist.id,
                    title: needsMerge ? playlist.title : detail.title,
                    description: detail.description ?? playlist.description,
                    thumbnailURL: resolvedThumbnailURL,
                    trackCount: detail.tracks.count,
                    author: detail.author ?? playlist.author,
                    playlistId: detail.playlistId
                )
                detail = PlaylistDetail(
                    playlist: mergedPlaylist,
                    tracks: detail.tracks,
                    duration: detail.duration,
                    playlistId: detail.playlistId
                )
            }

            playlistDetail = detail
            loadingState = .loaded
            let trackCount = detail.tracks.count
            logger.info("Playlist loaded: \(trackCount) tracks")
        } catch is CancellationError {
            logger.debug("Playlist detail load cancelled")
            loadingState = .idle
        } catch {
            logger.error("Failed to load playlist: \(error.localizedDescription)")
            loadingState = .error(LoadingError(from: error))
        }
    }

    /// Builds a PlaylistDetail from locally downloaded data, if available.
    private func buildOfflineDetail() -> PlaylistDetail? {
        guard let downloaded = downloadManager.playlists.first(where: { $0.id == playlist.id }) else {
            return nil
        }
        let tracks = downloaded.songIds.compactMap { videoId in
            downloadManager.downloads.first(where: { $0.id == videoId })?.song
        }
        let offlinePlaylist = Playlist(
            id: downloaded.id,
            title: downloaded.title,
            description: nil,
            thumbnailURL: downloaded.thumbnailURL,
            trackCount: tracks.count,
            author: downloaded.author
        )
        return PlaylistDetail(playlist: offlinePlaylist, tracks: tracks)
    }

    /// Refreshes the playlist.
    func refresh() {
        asyncTask = Task {
            await load()
        }
    }

    /// Extracts a color palette from the playlist artwork.
    func extractArtworkPalette() {
        let thumbnailURL = playlistDetail?.thumbnailURL ?? playlist.thumbnailURL
        colorExtractionTask = Task {
            guard let url = thumbnailURL?.miniThumbnailURL else {
                return
            }

            guard let (data, _) = try? await URLSession.shared.data(from: url) else {
                return
            }

            guard !Task.isCancelled else { return }

            let palette = await ColorExtractor.extractPalette(from: data)

            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.5)) {
                colorPalette = palette
            }
        }
    }

    // MARK: - Playback State

    /// Whether playback is currently active.
    var isPlaying: Bool {
        playerManager.isPlaying
    }

    /// The currently playing track.
    var currentTrack: Song? {
        playerManager.currentTrack
    }

    /// Checks if the given track is the currently playing track.
    func isCurrentTrack(_ track: Song) -> Bool {
        playerManager.currentTrack?.videoId == track.videoId
    }

    // MARK: - Playback Actions

    /// Plays a track within the playlist queue.
    func playTrack(at index: Int) {
        guard let tracks = playlistDetail?.tracks, !tracks.isEmpty else { return }
        Task {
            await playerManager.playQueue(tracks, startingAt: index, from: playlist)
        }
    }

    /// Plays a specific track, or toggles play/pause if it's already current.
    func playOrToggle(_ track: Song) {
        guard let tracks = playlistDetail?.tracks else { return }

        if isCurrentTrack(track) {
            // Toggle play/pause for current track
            Task {
                if isPlaying {
                    await playerManager.pause()
                } else {
                    await playerManager.resume()
                }
            }
        } else {
            // Play the selected track
            let index = tracks.firstIndex(of: track) ?? 0
            playTrack(at: index)
        }
    }

    /// Plays all tracks from the beginning.
    func playAll() {
        guard let tracks = playlistDetail?.tracks, !tracks.isEmpty else { return }
        Task {
            await playerManager.playQueue(tracks, startingAt: 0, from: playlist)
        }
    }

    /// Shuffles and plays all tracks.
    func shuffleAll() {
        guard let tracks = playlistDetail?.tracks, !tracks.isEmpty else { return }
        let shuffled = tracks.shuffled()
        Task {
            await playerManager.playQueue(shuffled, startingAt: 0, from: playlist)
        }
    }

    // MARK: - Download Actions

    /// Downloads all tracks in the playlist, saving playlist metadata.
    func downloadAll() async {
        guard let tracks = playlistDetail?.tracks, !tracks.isEmpty else { return }
        let downloadManager = Container.shared.downloadManager()
        await downloadManager.downloadPlaylist(playlist, songs: tracks)
    }

    /// Whether all tracks in the playlist are downloaded.
    var allTracksDownloaded: Bool {
        guard let tracks = playlistDetail?.tracks, !tracks.isEmpty else { return false }
        let downloadManager = Container.shared.downloadManager()
        return tracks.allSatisfy { downloadManager.isDownloaded(videoId: $0.videoId) }
    }

    /// Whether any tracks are currently downloading.
    var isDownloadingTracks: Bool {
        guard let tracks = playlistDetail?.tracks else { return false }
        let downloadManager = Container.shared.downloadManager()
        return tracks.contains { song in
            let state = downloadManager.downloadState(for: song.videoId)
            return state == .pending || state == .fetchingURL || state == .downloading
        }
    }

    /// Overall download progress (0.0–1.0) across all tracks.
    var downloadProgress: Double {
        guard let tracks = playlistDetail?.tracks, !tracks.isEmpty else { return 0 }
        let downloadManager = Container.shared.downloadManager()
        let total = Double(tracks.count)
        let progress = tracks.reduce(0.0) { sum, song in
            if downloadManager.isDownloaded(videoId: song.videoId) {
                return sum + 1.0
            }
            return sum + downloadManager.progress(for: song.videoId)
        }
        return progress / total
    }

    /// Cancels all active downloads for this playlist.
    func cancelDownloads() {
        guard let tracks = playlistDetail?.tracks else { return }
        let downloadManager = Container.shared.downloadManager()
        for song in tracks {
            let state = downloadManager.downloadState(for: song.videoId)
            if state == .pending || state == .fetchingURL || state == .downloading {
                downloadManager.cancel(videoId: song.videoId)
            }
        }
    }

    /// Removes all downloaded files for this playlist.
    func removeDownloads() {
        let downloadManager = Container.shared.downloadManager()
        downloadManager.deletePlaylist(playlistId: playlist.id)
    }

    /// Removes from library and deletes downloaded files.
    func removeFromLibraryAndDownloads() {
        removeDownloads()
        if isCurrentlyInLibrary {
            toggleLibrary()
        }
    }

    // MARK: - Song Actions

    /// Likes the given song.
    func likeSong(_ song: Song) {
        Task {
            await playerManager.playAndLike(song: song)
        }
    }

    /// Dislikes the given song.
    func dislikeSong(_ song: Song) {
        Task {
            await playerManager.playAndDislike(song: song)
        }
    }

    /// Adds the given song to library.
    func addSongToLibrary(_ song: Song) {
        Task {
            await playerManager.playAndAddToLibrary(song: song)
        }
    }

    // MARK: - Sharing

    /// YouTube Music URL for sharing this playlist or album.
    var shareURL: URL? {
        if playlist.isAlbum {
            URL(string: "https://music.youtube.com/browse/\(playlist.id)")
        } else {
            URL(string: "https://music.youtube.com/playlist?list=\(playlist.id)")
        }
    }

    // MARK: - Library Actions

    /// Toggles the playlist/album library status.
    func toggleLibrary() {
        Task {
            var playlistForLibrary = playlist
            playlistForLibrary.playlistId = playlistDetail?.playlistId

            do {
                if isCurrentlyInLibrary {
                    try await libraryRepository.removeFromLibrary(playlistForLibrary)
                    isAddedToLibrary = false
                } else {
                    try await libraryRepository.addToLibrary(playlistForLibrary)
                    isAddedToLibrary = true
                }
            } catch {
                logger.error("Failed to toggle library: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - AI Refine

    /// Refines the playlist using AI based on user prompt.
    func refinePlaylist(prompt: String) async {
        guard let tracks = playlistDetail?.tracks else { return }

        isRefining = true
        refineError = nil
        playlistChanges = nil

        aiLogger.info("Refining playlist with prompt: \(prompt)")

        let instructions = """
        You are a music playlist curator. Analyze songs and suggest changes based on the request.

        IMPORTANT RULES:
        - A "duplicate" means the EXACT same video ID appears twice. Different versions/covers
          of a song by different artists are NOT duplicates.
        - "Last Christmas" by Wham! and "Last Christmas" by Jimmy Eat World are DIFFERENT songs.
        - Only suggest removing tracks that truly don't fit the user's criteria.
        - When in doubt, keep the song.
        """

        guard let session = FoundationModelsService.shared.createAnalysisSession(instructions: instructions) else {
            refineError = "Apple Intelligence is not available"
            isRefining = false
            return
        }

        // Build track list - limit to 25 to reduce content filter issues
        let trackLimit = min(tracks.count, 25)
        let trackList = tracks.prefix(trackLimit).enumerated().map { index, track in
            let safeTitle = track.title.prefix(50)
            let safeArtist = track.artistsDisplay.prefix(30)
            return "\(index + 1). \(safeTitle) - \(safeArtist) [id:\(track.videoId)]"
        }.joined(separator: "\n")

        let userPrompt = """
        Playlist (\(tracks.count) songs, showing \(trackLimit)):

        \(trackList)

        Request: \(prompt)
        """

        do {
            let response = try await session.respond(to: userPrompt, generating: PlaylistChanges.self)
            playlistChanges = response.content
            aiLogger.info("Got playlist changes: \(response.content.removals.count) removals")
        } catch {
            if let message = AIErrorHandler.handleAndMessage(error, context: "playlist refinement") {
                refineError = message
            }
        }

        isRefining = false
    }

    /// Clears the refine state for retry.
    func clearRefineState() {
        playlistChanges = nil
        refineError = nil
    }

    /// Applies the AI-suggested changes (placeholder for future implementation).
    func applyRefineChanges() {
        // Playlist modification via API not yet implemented
        showRefineSheet = false
    }
}

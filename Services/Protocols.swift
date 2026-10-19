import AVFoundation
import Combine
import Foundation

// MARK: - WebKitManagerProtocol

/// Protocol defining the interface for WebKit cookie and data management.
/// Enables dependency injection and mocking for tests.
@MainActor
protocol WebKitManagerProtocol: AnyObject, Sendable {
    /// Retrieves all cookies from the HTTP cookie store.
    func getAllCookies() async -> [HTTPCookie]

    /// Gets cookies for a specific domain.
    func getCookies(for domain: String) async -> [HTTPCookie]

    /// Builds a Cookie header string for the given domain.
    func cookieHeader(for domain: String) async -> String?

    /// Retrieves the SAPISID cookie value used for authentication.
    func getSAPISID() async -> String?

    /// Checks if the required authentication cookies exist.
    func hasAuthCookies() async -> Bool

    /// Clears all website data (cookies, cache, etc.).
    func clearAllData() async

    /// Forces an immediate backup of all YouTube/Google cookies.
    func forceBackupCookies() async

    /// Logs all authentication-related cookies for debugging.
    func logAuthCookies() async
}

// MARK: - YTMusicClientProtocol

/// Protocol defining the interface for API operations.
/// Enables dependency injection and mocking for tests.
@MainActor
protocol YTMusicClientProtocol: Sendable {
    /// Fetches the home page content (initial sections only for fast display).
    func getHome() async throws -> HomeResponse

    /// Fetches the next batch of home sections via continuation.
    func getHomeContinuation(_ continuation: HomeResponse.Continuation) async throws -> HomeResponse

    /// Fetches the explore page content.
    /// Note: Explore page doesn't have continuation/pagination unlike home.
    func getExplore() async throws -> [HomeSection]

    /// Fetches the charts page content (initial sections only for fast display).
    func getCharts() async throws -> HomeResponse

    /// Fetches the next batch of charts sections via continuation.
    func getChartsContinuation() async throws -> [HomeSection]?

    /// Whether more charts sections are available to load.
    var hasMoreChartsSections: Bool { get }

    /// Fetches the moods and genres page content (initial sections only for fast display).
    func getMoodsAndGenres() async throws -> HomeResponse

    /// Fetches the next batch of moods and genres sections via continuation.
    func getMoodsAndGenresContinuation() async throws -> [HomeSection]?

    /// Whether more moods and genres sections are available to load.
    var hasMoreMoodsAndGenresSections: Bool { get }

    /// Fetches the new releases page content (initial sections only for fast display).
    func getNewReleases() async throws -> HomeResponse

    /// Fetches the next batch of new releases sections via continuation.
    func getNewReleasesContinuation() async throws -> [HomeSection]?

    /// Whether more new releases sections are available to load.
    var hasMoreNewReleasesSections: Bool { get }

    /// Fetches the podcasts page content (initial sections only for fast display).
    func getPodcasts() async throws -> HomeResponse

    /// Fetches the next batch of podcasts sections via continuation.
    func getPodcastsContinuation() async throws -> [HomeSection]?

    /// Whether more podcasts sections are available to load.
    var hasMorePodcastsSections: Bool { get }

    /// Searches for content.
    func search(query: String) async throws -> SearchResponse

    /// Searches for songs only (filtered search, excludes videos/podcasts/episodes).
    func searchSongs(query: String) async throws -> [Song]

    /// Fetches search suggestions for autocomplete.
    func getSearchSuggestions(query: String) async throws -> [SearchSuggestion]

    /// Fetches the user's library playlists.
    func getLibraryPlaylists() async throws -> [Playlist]

    /// Fetches the user's library artists.
    func getLibraryArtists() async throws -> [Artist]

    /// Fetches the user's library albums.
    func getLibraryAlbums() async throws -> [Album]

    /// Fetches the user's liked songs.
    func getLikedSongs() async throws -> [Song]

    /// Fetches playlist details including tracks.
    func getPlaylist(id: String) async throws -> PlaylistDetail

    /// Fetches artist details including their songs and albums.
    func getArtist(id: String) async throws -> ArtistDetail

    /// Fetches all songs for an artist using the songs browse endpoint.
    func getArtistSongs(browseId: String, params: String?) async throws -> [Song]

    /// Fetches all albums for an artist section using the browse endpoint.
    func getArtistAlbums(browseId: String, params: String?) async throws -> [Album]

    /// Rates a song (like/dislike/indifferent).
    func rateSong(videoId: String, rating: LikeStatus) async throws

    /// Adds or removes a song from the user's library.
    func editSongLibraryStatus(feedbackTokens: [String]) async throws

    /// Adds a playlist to the user's library.
    func subscribeToPlaylist(playlistId: String) async throws

    /// Removes a playlist from the user's library.
    func unsubscribeFromPlaylist(playlistId: String) async throws

    /// Subscribes to an artist (adds to library).
    func subscribeToArtist(channelId: String) async throws

    /// Unsubscribes from an artist (removes from library).
    func unsubscribeFromArtist(channelId: String) async throws

    /// Fetches lyrics for a song.
    func getLyrics(videoId: String) async throws -> Lyrics

    /// Fetches song metadata by video ID.
    func getSong(videoId: String) async throws -> Song

    /// Fetches a radio queue (similar songs) based on a video ID.
    /// Returns an array of songs that form a "radio" playlist based on the seed track.
    func getRadioQueue(videoId: String) async throws -> [Song]

    /// Fetches content for a moods/genres category page.
    /// Returns sections of songs/playlists for the category.
    func getMoodCategory(browseId: String, params: String?) async throws -> HomeResponse

    /// Fetches the logged-in user's account information including profile image.
    func getAccountInfo() async throws -> AccountInfo?

    // MARK: - Native Player API

    /// Fetches the signature timestamp from YouTube Music page.
    /// Required for WEB_REMIX client to access Premium streams.
    func getSignatureTimestamp() async throws -> Int

    /// Fetches player data for a video, returning stream URLs and metadata.
    func getPlayer(videoId: String, playlistId: String?, client: YouTubeClient?, signatureTimestamp: Int?) async throws -> PlayerResponse

    /// Gets the best audio stream URL for a video.
    func getAudioStreamURL(videoId: String, playlistId: String?) async throws -> URL
}

// MARK: - AuthServiceProtocol

/// Protocol defining the interface for authentication operations.
/// Enables dependency injection and mocking for tests.
@MainActor
protocol AuthServiceProtocol: AnyObject, Sendable {
    /// Current authentication state.
    var state: AuthService.State { get }

    /// Publisher for authentication state changes. Emits current value on subscription.
    var statePublisher: AnyPublisher<AuthService.State, Never> { get }

    /// Flag indicating whether re-authentication is needed.
    var needsReauth: Bool { get set }

    /// Starts the login flow by presenting the login sheet.
    func startLogin()

    /// Checks if the user is logged in based on existing cookies.
    func checkLoginStatus() async

    /// Called when a session expires (e.g., 401/403 from API).
    func sessionExpired()

    /// Signs out the user by clearing all cookies and data.
    func signOut() async

    /// Called when login completes successfully.
    func completeLogin(sapisid: String)
}

// MARK: - PlayerManagerProtocol

/// Protocol defining the interface for playback control.
/// Enables dependency injection and mocking for tests.
@MainActor
protocol PlayerManagerProtocol: AnyObject, Sendable {
    /// Current playback state.
    var state: PlayerManager.PlaybackState { get }

    /// Currently playing track.
    var currentTrack: Song? { get }

    /// Whether playback is active.
    var isPlaying: Bool { get }

    /// Current playback position in seconds.
    var progress: TimeInterval { get }

    /// Total duration of current track in seconds.
    var duration: TimeInterval { get }

    /// Current volume (0.0 - 1.0).
    var volume: Double { get }

    /// Whether audio is currently muted.
    var isMuted: Bool { get }

    /// Whether shuffle mode is enabled.
    var shuffleEnabled: Bool { get }

    /// Current repeat mode.
    var repeatMode: PlayerManager.RepeatMode { get }

    /// Playback queue.
    var queue: [Song] { get }

    /// Index of current track in queue.
    var currentIndex: Int { get }

    /// Source playlist for the current queue (if playing from a playlist).
    var sourcePlaylist: Playlist? { get }

    /// Whether the mini player should be shown.
    var showMiniPlayer: Bool { get set }

    /// Like status of the current track.
    var currentTrackLikeStatus: LikeStatus { get }

    /// Whether the current track is in the user's library.
    var currentTrackInLibrary: Bool { get }

    // MARK: - Playback Control

    /// Plays a track by video ID.
    func play(videoId: String) async

    /// Plays a song.
    func play(song: Song) async

    /// Toggles play/pause.
    func playPause() async

    /// Pauses playback.
    func pause() async

    /// Resumes playback.
    func resume() async

    /// Skips to next track.
    func next() async

    /// Goes to previous track.
    func previous() async

    /// Seeks to a specific time.
    func seek(to time: TimeInterval) async

    /// Sets the volume.
    func setVolume(_ value: Double) async

    /// Toggles mute state.
    func toggleMute() async

    /// Toggles shuffle mode.
    func toggleShuffle()

    /// Cycles through repeat modes.
    func cycleRepeatMode()

    /// Stops playback and clears state.
    func stop() async

    /// Plays a queue of songs starting at the specified index.
    /// - Parameters:
    ///   - songs: The songs to play.
    ///   - index: The index to start playing from.
    ///   - sourcePlaylist: The playlist these songs came from (for navigation back to it).
    func playQueue(_ songs: [Song], startingAt index: Int, from sourcePlaylist: Playlist?) async

    /// Plays a song and fetches similar songs (radio queue) in the background.
    /// The queue will be populated with similar songs from the radio feature.
    func playWithRadio(song: Song) async

    // MARK: - Like/Library Actions

    /// Plays a song and likes it.
    func playAndLike(song: Song) async

    /// Plays a song and dislikes it.
    func playAndDislike(song: Song) async

    /// Plays a song and adds it to the library.
    func playAndAddToLibrary(song: Song) async

    /// Likes the current track.
    func likeCurrentTrack()

    /// Dislikes the current track.
    func dislikeCurrentTrack()

    /// Toggles the library status of the current track.
    func toggleLibraryStatus()

    // MARK: - State Updates

    /// Called when the mini player confirms playback has started.
    func confirmPlaybackStarted()

    /// Called when the mini player is dismissed.
    func miniPlayerDismissed()

    /// Updates playback state from the WebView observer.
    func updatePlaybackState(isPlaying: Bool, progress: Double, duration: Double)

    /// Updates track metadata when track changes.
    func updateWebTrackMetadata(title: String, artist: String, thumbnailUrl: String)

    /// Updates the like status from WebView observation.
    func updateLikeStatus(_ status: LikeStatus)
}

// MARK: - SongLikeStatusManagerProtocol

/// Protocol defining the interface for song like status management.
/// Enables dependency injection and mocking for tests.
@MainActor
protocol SongLikeStatusManagerProtocol: AnyObject, Sendable {
    /// Gets the cached like status for a song by video ID.
    func status(for videoId: String) -> LikeStatus?

    /// Gets the like status for a song, using the song's own status as fallback.
    func status(for song: Song) -> LikeStatus?

    /// Checks if a song is liked.
    func isLiked(_ song: Song) -> Bool

    /// Checks if a song is disliked.
    func isDisliked(_ song: Song) -> Bool

    /// Likes a song.
    func like(_ song: Song) async

    /// Unlikes a song (removes rating).
    func unlike(_ song: Song) async

    /// Dislikes a song.
    func dislike(_ song: Song) async

    /// Undislikes a song (removes rating).
    func undislike(_ song: Song) async

    /// Updates the cache with a known status (e.g., from API response).
    func setStatus(_ status: LikeStatus, for videoId: String)

    /// Clears all cached statuses.
    func clearCache()
}

// MARK: - LibraryRepositoryProtocol

/// Protocol defining the interface for library data management.
/// Centralizes library data (playlists, artists, albums) and provides lookup methods.
@MainActor
protocol LibraryRepositoryProtocol: AnyObject, Sendable {
    /// Loading state for playlists.
    var playlistsLoadingState: LoadingState { get }

    /// Loading state for artists.
    var artistsLoadingState: LoadingState { get }

    /// Loading state for albums.
    var albumsLoadingState: LoadingState { get }

    /// User's playlists.
    var playlists: [Playlist] { get }

    /// User's artists.
    var artists: [Artist] { get }

    /// User's albums.
    var albums: [Album] { get }

    /// Set of playlist IDs in the user's library (for quick lookup).
    var libraryPlaylistIds: Set<String> { get }

    /// Set of album IDs in the user's library (for quick lookup).
    var libraryAlbumIds: Set<String> { get }

    /// Callback invoked when library data changes.
    var onDataChanged: (() -> Void)? { get set }

    /// Starts loading library data (playlists first, then artists/albums after delay).
    func load() async

    /// Refreshes all library data.
    func refresh() async

    /// Checks if a playlist is in the user's library.
    func isInLibrary(playlistId: String) -> Bool

    /// Adds a playlist ID to the library set.
    func addToLibrarySet(playlistId: String)

    /// Removes a playlist ID from the library set.
    func removeFromLibrarySet(playlistId: String)

    /// Checks if an album is in the user's library.
    func isAlbumInLibrary(albumId: String) -> Bool

    /// Adds an album ID to the library set.
    func addAlbumToLibrarySet(albumId: String)

    /// Removes an album ID from the library set.
    func removeAlbumFromLibrarySet(albumId: String)

    // MARK: - Library Mutations

    /// Adds a playlist or album to the user's library.
    /// Performs optimistic update and schedules a delayed refresh.
    func addToLibrary(_ playlist: Playlist) async throws

    /// Removes a playlist or album from the user's library.
    /// Performs optimistic update and schedules a delayed refresh.
    func removeFromLibrary(_ playlist: Playlist) async throws
}

// MARK: - DownloadManagerProtocol

/// Protocol defining the interface for offline download management.
/// Enables dependency injection and mocking for tests.
@MainActor
protocol DownloadManagerProtocol: AnyObject, Sendable {
    /// Completed downloads available for offline playback.
    var downloads: [DownloadedSong] { get }

    /// Active and pending download tasks.
    var activeTasks: [DownloadTaskInfo] { get }

    /// Whether any download is currently in progress.
    var isDownloading: Bool { get }

    /// Checks if a song is available offline.
    func isDownloaded(videoId: String) -> Bool

    /// Gets the download state for a song.
    func downloadState(for videoId: String) -> DownloadTaskInfo.DownloadState?

    /// Gets the download progress for a song (0.0–1.0).
    func progress(for videoId: String) -> Double

    /// Gets the local AVURLAsset for offline playback (AAC files).
    func localAsset(for videoId: String) -> AVURLAsset?

    /// Gets the local file URL for offline playback (any format).
    func localFileURL(for videoId: String) -> URL?

    /// Downloads a single song.
    func download(song: Song) async

    /// Downloads multiple songs (batch).
    func downloadAll(songs: [Song]) async

    /// Downloads all songs in a playlist/album, saving playlist metadata.
    func downloadPlaylist(_ playlist: Playlist, songs: [Song]) async

    /// Saved playlists/albums with downloaded songs.
    var playlists: [DownloadedPlaylist] { get }

    /// Songs not associated with any downloaded playlist.
    var looseSongs: [DownloadedSong] { get }

    /// Cancels a download in progress.
    func cancel(videoId: String)

    /// Retries a failed download.
    func retry(videoId: String) async

    /// Deletes a downloaded song and its assets.
    func deleteDownload(videoId: String)

    /// Deletes a downloaded playlist and all its songs (that aren't in other playlists).
    func deletePlaylist(playlistId: String)

    /// Deletes all downloads, playlists, and cancels active tasks.
    func deleteAllDownloads()

    /// Formatted total download size string.
    var totalDownloadSizeDisplay: String { get }
}

// MARK: - Default Implementations

extension PlayerManagerProtocol {
    /// Plays a queue of songs starting at the specified index (without source playlist).
    func playQueue(_ songs: [Song], startingAt index: Int) async {
        await playQueue(songs, startingAt: index, from: nil)
    }
}

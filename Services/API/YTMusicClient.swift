@preconcurrency import Alamofire
import CryptoKit
import Foundation
import os

/// Client for making authenticated requests to the internal API.
@MainActor
final class YTMusicClient: YTMusicClientProtocol {
    private let authService: AuthService
    private let webKitManager: WebKitManager
    private let session: Session
    private let logger = DiagnosticsLogger.api

    /// API base URL.
    private static let baseURL = "https://music.youtube.com/youtubei/v1"

    /// Client version for WEB_REMIX.
    private static let clientVersion = "1.20250310.01.00"

    // MARK: - Sync State

    private(set) var isSyncingPlaylists = false
    private(set) var isSyncingArtists = false
    private(set) var isSyncingAlbums = false

    // MARK: - Signature Timestamp Cache

    private var cachedSignatureTimestamp: Int?
    private var signatureTimestampFetchTime: Date?

    init(authService: AuthService, webKitManager: WebKitManager) {
        self.authService = authService
        self.webKitManager = webKitManager
        self.session = YTMusicSession.create(webKitManager: webKitManager, authService: authService)
    }

    /// Fetches the home page content (initial sections only for fast display).
    /// Call `getHomeContinuation` to load additional sections progressively.
    func getHome() async throws -> HomeResponse {
        self.logger.info("🌐 Fetching home page from API")

        let body: [String: Any] = [
            "browseId": "FEmusic_home",
        ]

        let data = try await request("browse", body: body)

        let sections = HomeResponseParser.parse(data).sections
        let token = HomeResponseParser.extractContinuationToken(from: data)
        let continuation = token.map { HomeResponse.Continuation(token: $0) }

        self.logger.info("Home page loaded: \(sections.count) initial sections, hasMore: \(token != nil)")
        return HomeResponse(sections: sections, continuation: continuation)
    }

    /// Fetches the next batch of home sections via continuation.
    /// Returns HomeResponse with new sections and next continuation.
    func getHomeContinuation(_ continuation: HomeResponse.Continuation) async throws -> HomeResponse {
        self.logger.info("🌐 Fetching home continuation from API")

        let continuationData = try await requestContinuation(continuation.token)

        let sections = HomeResponseParser.parseContinuation(continuationData)
        let nextToken = HomeResponseParser.extractContinuationTokenFromContinuation(continuationData)
        let nextContinuation = nextToken.map { HomeResponse.Continuation(token: $0) }

        self.logger.info("Home continuation loaded: \(sections.count) sections, hasMore: \(nextToken != nil)")
        return HomeResponse(sections: sections, continuation: nextContinuation)
    }

    /// Fetches the explore page content.
    /// Note: Explore page doesn't have continuation/pagination unlike home.
    func getExplore() async throws -> [HomeSection] {
        self.logger.info("🌐 Fetching explore page from API")

        let body: [String: Any] = [
            "browseId": "FEmusic_explore",
        ]

        let data = try await request("browse", body: body)

        let sections = HomeResponseParser.parse(data).sections
        self.logger.info("Explore page loaded: \(sections.count) sections")
        return sections
    }

    // MARK: - Charts

    /// Internal storage for charts continuation token.
    private var _chartsContinuationToken: String?

    /// Fetches the charts page content (initial sections only for fast display).
    func getCharts() async throws -> HomeResponse {
        self.logger.info("Fetching charts page")

        let body: [String: Any] = [
            "browseId": "FEmusic_charts",
        ]

        let data = try await request("browse", body: body)
        let response = HomeResponseParser.parse(data)

        // Store continuation token for progressive loading
        let token = HomeResponseParser.extractContinuationToken(from: data)
        self._chartsContinuationToken = token

        self.logger.info("Charts page loaded: \(response.sections.count) initial sections, hasMore: \(token != nil)")
        return response
    }

    /// Fetches the next batch of charts sections via continuation.
    func getChartsContinuation() async throws -> [HomeSection]? {
        guard let token = _chartsContinuationToken else {
            self.logger.debug("No charts continuation token available")
            return nil
        }

        self.logger.info("Fetching charts continuation")

        do {
            let continuationData = try await requestContinuation(token)
            let additionalSections = HomeResponseParser.parseContinuation(continuationData)
            self._chartsContinuationToken = HomeResponseParser.extractContinuationTokenFromContinuation(continuationData)
            let hasMore = self._chartsContinuationToken != nil

            self.logger.info("Charts continuation loaded: \(additionalSections.count) sections, hasMore: \(hasMore)")
            return additionalSections
        } catch {
            self.logger.warning("Failed to fetch charts continuation: \(error.localizedDescription)")
            self._chartsContinuationToken = nil
            throw error
        }
    }

    /// Whether more charts sections are available to load.
    var hasMoreChartsSections: Bool {
        self._chartsContinuationToken != nil
    }

    // MARK: - Moods and Genres

    /// Internal storage for moods and genres continuation token.
    private var _moodsAndGenresContinuationToken: String?

    /// Fetches the moods and genres page content (initial sections only for fast display).
    func getMoodsAndGenres() async throws -> HomeResponse {
        self.logger.info("Fetching moods and genres page")

        let body: [String: Any] = [
            "browseId": "FEmusic_moods_and_genres",
        ]

        let data = try await request("browse", body: body)
        let response = HomeResponseParser.parse(data)

        // Store continuation token for progressive loading
        let token = HomeResponseParser.extractContinuationToken(from: data)
        self._moodsAndGenresContinuationToken = token

        self.logger.info("Moods and genres page loaded: \(response.sections.count) initial sections, hasMore: \(token != nil)")
        return response
    }

    /// Fetches the next batch of moods and genres sections via continuation.
    func getMoodsAndGenresContinuation() async throws -> [HomeSection]? {
        guard let token = _moodsAndGenresContinuationToken else {
            self.logger.debug("No moods and genres continuation token available")
            return nil
        }

        self.logger.info("Fetching moods and genres continuation")

        do {
            let continuationData = try await requestContinuation(token)
            let additionalSections = HomeResponseParser.parseContinuation(continuationData)
            self._moodsAndGenresContinuationToken = HomeResponseParser.extractContinuationTokenFromContinuation(continuationData)
            let hasMore = self._moodsAndGenresContinuationToken != nil

            self.logger.info("Moods and genres continuation loaded: \(additionalSections.count) sections, hasMore: \(hasMore)")
            return additionalSections
        } catch {
            self.logger.warning("Failed to fetch moods and genres continuation: \(error.localizedDescription)")
            self._moodsAndGenresContinuationToken = nil
            throw error
        }
    }

    /// Whether more moods and genres sections are available to load.
    var hasMoreMoodsAndGenresSections: Bool {
        self._moodsAndGenresContinuationToken != nil
    }

    // MARK: - New Releases

    /// Internal storage for new releases continuation token.
    private var _newReleasesContinuationToken: String?

    /// Fetches the new releases page content (initial sections only for fast display).
    func getNewReleases() async throws -> HomeResponse {
        self.logger.info("Fetching new releases page")

        let body: [String: Any] = [
            "browseId": "FEmusic_new_releases",
        ]

        let data = try await request("browse", body: body)
        let response = HomeResponseParser.parse(data)

        // Store continuation token for progressive loading
        let token = HomeResponseParser.extractContinuationToken(from: data)
        self._newReleasesContinuationToken = token

        self.logger.info("New releases page loaded: \(response.sections.count) initial sections, hasMore: \(token != nil)")
        return response
    }

    /// Fetches the next batch of new releases sections via continuation.
    func getNewReleasesContinuation() async throws -> [HomeSection]? {
        guard let token = _newReleasesContinuationToken else {
            self.logger.debug("No new releases continuation token available")
            return nil
        }

        self.logger.info("Fetching new releases continuation")

        do {
            let continuationData = try await requestContinuation(token)
            let additionalSections = HomeResponseParser.parseContinuation(continuationData)
            self._newReleasesContinuationToken = HomeResponseParser.extractContinuationTokenFromContinuation(continuationData)
            let hasMore = self._newReleasesContinuationToken != nil

            self.logger.info("New releases continuation loaded: \(additionalSections.count) sections, hasMore: \(hasMore)")
            return additionalSections
        } catch {
            self.logger.warning("Failed to fetch new releases continuation: \(error.localizedDescription)")
            self._newReleasesContinuationToken = nil
            throw error
        }
    }

    /// Whether more new releases sections are available to load.
    var hasMoreNewReleasesSections: Bool {
        self._newReleasesContinuationToken != nil
    }

    // MARK: - Podcasts

    /// Internal storage for podcasts continuation token.
    private var _podcastsContinuationToken: String?

    /// Fetches the podcasts page content (initial sections only for fast display).
    func getPodcasts() async throws -> HomeResponse {
        self.logger.info("Fetching podcasts page")

        let body: [String: Any] = [
            "browseId": "FEmusic_podcasts",
        ]

        let data = try await request("browse", body: body)
        let response = HomeResponseParser.parse(data)

        // Store continuation token for progressive loading
        let token = HomeResponseParser.extractContinuationToken(from: data)
        self._podcastsContinuationToken = token

        self.logger.info("Podcasts page loaded: \(response.sections.count) initial sections, hasMore: \(token != nil)")
        return response
    }

    /// Fetches the next batch of podcasts sections via continuation.
    func getPodcastsContinuation() async throws -> [HomeSection]? {
        guard let token = _podcastsContinuationToken else {
            self.logger.debug("No podcasts continuation token available")
            return nil
        }

        self.logger.info("Fetching podcasts continuation")

        do {
            let continuationData = try await requestContinuation(token)
            let additionalSections = HomeResponseParser.parseContinuation(continuationData)
            self._podcastsContinuationToken = HomeResponseParser.extractContinuationTokenFromContinuation(continuationData)
            let hasMore = self._podcastsContinuationToken != nil

            self.logger.info("Podcasts continuation loaded: \(additionalSections.count) sections, hasMore: \(hasMore)")
            return additionalSections
        } catch {
            self.logger.warning("Failed to fetch podcasts continuation: \(error.localizedDescription)")
            self._podcastsContinuationToken = nil
            throw error
        }
    }

    /// Whether more podcasts sections are available to load.
    var hasMorePodcastsSections: Bool {
        self._podcastsContinuationToken != nil
    }

    /// Makes a continuation request.
    private func requestContinuation(_ token: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "continuation": token,
        ]
        return try await self.request("browse", body: body)
    }

    /// Searches for content.
    func search(query: String) async throws -> SearchResponse {
        self.logger.info("Searching for: \(query)")

        let body: [String: Any] = [
            "query": query,
        ]

        let data = try await request("search", body: body)
        let response = SearchResponseParser.parse(data)
        self.logger.info("Search found \(response.songs.count) songs, \(response.albums.count) albums, \(response.artists.count) artists, \(response.playlists.count) playlists")
        return response
    }

    /// Searches for songs only (filtered search).
    func searchSongs(query: String) async throws -> [Song] {
        self.logger.info("Searching songs only for: \(query)")

        // API params for songs filter
        // Derived from: EgWKAQ (filtered) + II (songs) + AWoMEA4QChADEAQQCRAF (no spelling correction)
        let songsFilterParams = "EgWKAQIIAWoMEA4QChADEAQQCRAF"

        let body: [String: Any] = [
            "query": query,
            "params": songsFilterParams,
        ]

        let data = try await request("search", body: body)
        let songs = SearchResponseParser.parseSongsOnly(data)
        self.logger.info("Songs search found \(songs.count) songs")
        return songs
    }

    /// Fetches search suggestions for autocomplete.
    func getSearchSuggestions(query: String) async throws -> [SearchSuggestion] {
        guard !query.isEmpty else {
            return []
        }

        self.logger.debug("Fetching search suggestions for: \(query)")

        let body: [String: Any] = [
            "input": query,
        ]

        // No caching for suggestions - they're ephemeral
        let data = try await request("music/get_search_suggestions", body: body)
        let suggestions = SearchSuggestionsParser.parse(data)
        self.logger.debug("Found \(suggestions.count) suggestions")
        return suggestions
    }

    /// Fetches the user's library playlists.
    func getLibraryPlaylists() async throws -> [Playlist] {
        self.isSyncingPlaylists = true
        defer { self.isSyncingPlaylists = false }

        self.logger.info("Fetching library playlists")

        let body: [String: Any] = [
            "browseId": "FEmusic_liked_playlists",
        ]

        let data = try await request("browse", body: body)
        let playlists = PlaylistParser.parseLibraryPlaylists(data)
        self.logger.info("Parsed \(playlists.count) library playlists")
        return playlists
    }

    /// Fetches the user's library artists.
    func getLibraryArtists() async throws -> [Artist] {
        self.isSyncingArtists = true
        defer { self.isSyncingArtists = false }

        self.logger.info("Fetching library artists")

        let body: [String: Any] = [
            "browseId": "FEmusic_library_corpus_artists",
        ]

        let data = try await request("browse", body: body)
        let artists = ArtistParser.parseLibraryArtists(data)
        self.logger.info("Parsed \(artists.count) library artists")
        return artists
    }

    /// Fetches the user's library albums.
    func getLibraryAlbums() async throws -> [Album] {
        self.isSyncingAlbums = true
        defer { self.isSyncingAlbums = false }

        self.logger.info("Fetching library albums")

        let body: [String: Any] = [
            "browseId": "FEmusic_liked_albums",
        ]

        let data = try await request("browse", body: body)
        let albums = ArtistParser.parseLibraryAlbums(data)
        self.logger.info("Parsed \(albums.count) library albums")
        return albums
    }

    /// Fetches the user's liked songs.
    func getLikedSongs() async throws -> [Song] {
        self.logger.info("Fetching liked songs")

        let body: [String: Any] = [
            "browseId": "FEmusic_liked_videos",
        ]

        let data = try await request("browse", body: body)
        let detail = PlaylistParser.parsePlaylistDetail(data, playlistId: "LM")
        self.logger.info("Parsed \(detail.tracks.count) liked songs")
        return detail.tracks
    }

    /// Fetches playlist details including tracks.
    func getPlaylist(id: String) async throws -> PlaylistDetail {
        // Handle different ID formats:
        // - VL... = playlist (already has prefix)
        // - PL... = playlist (needs VL prefix)
        // - RD... = radio/mix playlist (needs VL prefix)
        // - RDCLAK... = album radio playlist (needs VL prefix)
        // - OLAK... = album browse ID (use as-is, no prefix)
        // - MPRE... = album browse ID (use as-is, no prefix)
        // - UC... = channel browse ID (use as-is, no prefix)
        let browseId: String = if id.hasPrefix("VL") {
            id
        } else if id.hasPrefix("OLAK") || id.hasPrefix("MPRE") || id.hasPrefix("UC") {
            id
        } else {
            "VL\(id)"
        }

        self.logger.info("🌐 Fetching playlist: \(id)")

        let body: [String: Any] = [
            "browseId": browseId,
        ]

        let data = try await request("browse", body: body)

        let detail = PlaylistParser.parsePlaylistDetail(data, playlistId: id)
        self.logger.info("Parsed playlist '\(detail.title)' with \(detail.tracks.count) tracks")
        return detail
    }

    /// Fetches artist details including their songs and albums.
    func getArtist(id: String) async throws -> ArtistDetail {
        self.logger.info("🌐 Fetching artist: \(id)")

        let body: [String: Any] = [
            "browseId": id,
        ]

        let data = try await request("browse", body: body)

        let detail = ArtistParser.parseArtistDetail(data, artistId: id)
        let totalAlbums = detail.albumSections.reduce(0) { $0 + $1.albums.count }
        self.logger.info("Parsed artist '\(detail.artist.name)' with \(detail.songs.count) songs and \(totalAlbums) albums")
        return detail
    }

    /// Fetches all songs for an artist using the songs browse endpoint.
    func getArtistSongs(browseId: String, params: String?) async throws -> [Song] {
        self.logger.info("Fetching artist songs: \(browseId)")

        var body: [String: Any] = [
            "browseId": browseId,
        ]

        if let params {
            body["params"] = params
        }

        let data = try await request("browse", body: body)

        let songs = ArtistParser.parseArtistSongs(data)
        self.logger.info("Parsed \(songs.count) artist songs")
        return songs
    }

    /// Fetches all albums for an artist section using the browse endpoint.
    func getArtistAlbums(browseId: String, params: String?) async throws -> [Album] {
        self.logger.info("Fetching artist albums: \(browseId)")

        var body: [String: Any] = [
            "browseId": browseId,
        ]

        if let params {
            body["params"] = params
        }

        let data = try await request("browse", body: body)

        let albums = ArtistParser.parseArtistAlbums(data)
        self.logger.info("Parsed \(albums.count) artist albums")
        return albums
    }

    // MARK: - Lyrics

    /// Fetches lyrics for a song by video ID.
    /// - Parameter videoId: The video ID of the song
    /// - Returns: Lyrics if available, or Lyrics.unavailable if not
    func getLyrics(videoId: String) async throws -> Lyrics {
        self.logger.info("🌐 Fetching lyrics for: \(videoId)")

        // Step 1: Get the lyrics browse ID from the "next" endpoint
        let nextBody: [String: Any] = [
            "videoId": videoId,
            "enablePersistentPlaylistPanel": true,
            "isAudioOnly": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
        ]

        let nextData = try await request("next", body: nextBody)

        guard let lyricsBrowseId = LyricsParser.extractLyricsBrowseId(from: nextData) else {
            self.logger.info("No lyrics available for: \(videoId)")
            return .unavailable
        }

        // Step 2: Fetch the actual lyrics using the browse ID
        let browseBody: [String: Any] = [
            "browseId": lyricsBrowseId,
        ]

        let browseData = try await request("browse", body: browseBody)

        let lyrics = LyricsParser.parse(from: browseData)
        self.logger.info("Fetched lyrics for \(videoId): \(lyrics.isAvailable ? "available" : "unavailable")")
        return lyrics
    }

    // MARK: - Radio Queue

    /// Fetches a radio queue (similar songs) based on a video ID.
    /// Uses the "next" endpoint with a radio playlist ID (RDAMVM prefix).
    /// - Parameter videoId: The seed video ID to base the radio on
    /// - Returns: An array of songs forming the radio queue
    func getRadioQueue(videoId: String) async throws -> [Song] {
        self.logger.info("Fetching radio queue for: \(videoId)")

        // Use RDAMVM prefix to request a radio mix based on the song
        let body: [String: Any] = [
            "videoId": videoId,
            "playlistId": "RDAMVM\(videoId)",
            "enablePersistentPlaylistPanel": true,
            "isAudioOnly": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
        ]

        let data = try await request("next", body: body)
        let songs = RadioQueueParser.parse(from: data)
        self.logger.info("Fetched radio queue with \(songs.count) songs")
        return songs
    }

    // MARK: - Song Metadata

    /// Fetches full song metadata including feedbackTokens for library management.
    /// Uses the `next` endpoint to get track details with library status.
    /// - Parameter videoId: The video ID of the song
    /// - Returns: A Song with full metadata including feedbackTokens and inLibrary status
    func getSong(videoId: String) async throws -> Song {
        self.logger.info("Fetching song metadata: \(videoId)")

        // Use the "next" endpoint which returns track info with feedbackTokens
        let body: [String: Any] = [
            "videoId": videoId,
            "enablePersistentPlaylistPanel": true,
            "isAudioOnly": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
        ]

        let data = try await request("next", body: body)
        let song = try SongMetadataParser.parse(data, videoId: videoId)
        self.logger.info("Parsed song '\(song.title)' - inLibrary: \(song.isInLibrary ?? false), hasTokens: \(song.feedbackTokens != nil)")
        return song
    }

    // MARK: - Mood/Genre Category

    /// Fetches content for a moods/genres category page.
    /// These are browse pages that return sections of songs/playlists, not playlist tracks.
    /// - Parameters:
    ///   - browseId: The browse ID (e.g., "FEmusic_moods_and_genres_category")
    ///   - params: Optional params for the category (extracted from navigation button)
    /// - Returns: HomeResponse with sections for the category
    func getMoodCategory(browseId: String, params: String?) async throws -> HomeResponse {
        self.logger.info("🌐 Fetching mood category: \(browseId)")

        var body: [String: Any] = [
            "browseId": browseId,
        ]

        if let params {
            body["params"] = params
        }

        let data = try await request("browse", body: body)

        let response = HomeResponseParser.parse(data)
        self.logger.info("Mood category loaded: \(response.sections.count) sections")
        return response
    }

    // MARK: - Like/Library Actions

    /// Rates a song (like/dislike/indifferent).
    /// - Parameters:
    ///   - videoId: The video ID of the song to rate
    ///   - rating: The rating to apply (like, dislike, or indifferent to remove rating)
    func rateSong(videoId: String, rating: LikeStatus) async throws {
        self.logger.info("Rating song \(videoId) with \(rating.rawValue)")

        let body: [String: Any] = [
            "target": ["videoId": videoId],
        ]

        // Endpoint varies by rating type
        let endpoint = switch rating {
        case .like:
            "like/like"
        case .dislike:
            "like/dislike"
        case .indifferent:
            "like/removelike"
        }

        _ = try await self.request(endpoint, body: body)
        self.logger.info("Successfully rated song \(videoId)")

        // Invalidate mutation-affected caches in a single pass
    }

    /// Adds or removes a song from the user's library.
    /// - Parameter feedbackTokens: Tokens obtained from song metadata (use add token to add, remove token to remove)
    func editSongLibraryStatus(feedbackTokens: [String]) async throws {
        guard !feedbackTokens.isEmpty else {
            self.logger.warning("No feedback tokens provided for library edit")
            return
        }

        self.logger.info("Editing song library status with \(feedbackTokens.count) tokens")

        let body: [String: Any] = [
            "feedbackTokens": feedbackTokens,
        ]

        _ = try await self.request("feedback", body: body)
        self.logger.info("Successfully edited library status")

        // Invalidate mutation-affected caches in a single pass
    }

    /// Adds a playlist to the user's library using the like/like endpoint.
    /// This is equivalent to the "Add to Library" action.
    /// - Parameter playlistId: The playlist ID to add to library
    func subscribeToPlaylist(playlistId: String) async throws {
        self.logger.info("Adding playlist to library: \(playlistId)")

        // Remove VL prefix if present for the API call
        let cleanId = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId

        let body: [String: Any] = [
            "target": ["playlistId": cleanId],
        ]

        _ = try await self.request("like/like", body: body)
        self.logger.info("Successfully added playlist \(playlistId) to library")

        // Invalidate library cache so UI updates
    }

    /// Removes a playlist from the user's library using the like/removelike endpoint.
    /// This is equivalent to the "Remove from Library" action.
    /// - Parameter playlistId: The playlist ID to remove from library
    func unsubscribeFromPlaylist(playlistId: String) async throws {
        self.logger.info("Removing playlist from library: \(playlistId)")

        // Remove VL prefix if present for the API call
        let cleanId = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId

        let body: [String: Any] = [
            "target": ["playlistId": cleanId],
        ]

        _ = try await self.request("like/removelike", body: body)
        self.logger.info("Successfully removed playlist \(playlistId) from library")

        // Invalidate library cache so UI updates
    }

    /// Subscribes to an artist by channel ID.
    /// This is equivalent to the "Subscribe" action.
    /// - Parameter channelId: The channel ID of the artist (e.g., UCxxxxx)
    func subscribeToArtist(channelId: String) async throws {
        self.logger.info("Subscribing to artist: \(channelId)")

        let body: [String: Any] = [
            "channelIds": [channelId],
        ]

        _ = try await self.request("subscription/subscribe", body: body)
        self.logger.info("Successfully subscribed to artist \(channelId)")

        // Invalidate artist cache so UI updates
    }

    /// Unsubscribes from an artist by channel ID.
    /// This is equivalent to the "Unsubscribe" action.
    /// - Parameter channelId: The channel ID of the artist (e.g., UCxxxxx)
    func unsubscribeFromArtist(channelId: String) async throws {
        self.logger.info("Unsubscribing from artist: \(channelId)")

        let body: [String: Any] = [
            "channelIds": [channelId],
        ]

        _ = try await self.request("subscription/unsubscribe", body: body)
        self.logger.info("Successfully unsubscribed from artist \(channelId)")

        // Invalidate artist cache so UI updates
    }

    // MARK: - Account

    /// Fetches the logged-in user's account information including profile image.
    /// - Returns: AccountInfo containing name, email, channel handle, and thumbnail URL
    func getAccountInfo() async throws -> AccountInfo? {
        self.logger.info("Fetching account info")

        let body: [String: Any] = [
            "deviceTheme": "DEVICE_THEME_SELECTED",
            "userInterfaceTheme": "USER_INTERFACE_THEME_DARK",
        ]

        let data = try await request("account/account_menu", body: body)
        let accountInfo = AccountMenuParser.parse(from: data)

        if let info = accountInfo {
            self.logger.info("Fetched account info for: \(info.name ?? "unknown")")
        } else {
            self.logger.warning("Failed to parse account info from response")
        }

        return accountInfo
    }

    // MARK: - Native Player API

    /// Fetches the signature timestamp from YouTube Music page.
    /// This is required for WEB_REMIX client to access Premium streams.
    /// Cached for 6 hours.
    func getSignatureTimestamp() async throws -> Int {
        // Return cached value if still valid
        if let cached = cachedSignatureTimestamp,
           let fetchTime = signatureTimestampFetchTime,
           Date().timeIntervalSince(fetchTime) < 6 * 60 * 60
        {
            return cached
        }

        self.logger.info("Fetching signature timestamp from YouTube Music")

        guard let url = URL(string: "https://music.youtube.com") else {
            throw YTMusicError.unknown(message: "Invalid YouTube Music URL")
        }

        var request = URLRequest(url: url)
        request.setValue(YouTubeClient.userAgentWeb, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw YTMusicError.parseError(message: "Failed to decode YouTube Music page")
        }

        // Extract signatureTimestamp from the page
        let patterns = [
            #""signatureTimestamp"\s*:\s*(\d+)"#,
            #"signatureTimestamp["\s]*[:=]\s*(\d+)"#,
            #"\bsts\s*[:=]\s*(\d+)"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html),
               let timestamp = Int(html[range])
            {
                self.cachedSignatureTimestamp = timestamp
                self.signatureTimestampFetchTime = Date()
                self.logger.info("Signature timestamp extracted: \(timestamp)")
                return timestamp
            }
        }

        // Fallback: try to extract from player.js URL
        if let playerJsMatch = html.range(of: #"/s/player/[^"]+/player_ias\.vflset/[^"]+/base\.js"#, options: .regularExpression) {
            let playerJsPath = String(html[playerJsMatch])
            let playerJsUrl = "https://www.youtube.com\(playerJsPath)"

            self.logger.debug("Fetching player.js from: \(playerJsUrl)")

            if let jsUrl = URL(string: playerJsUrl) {
                var jsRequest = URLRequest(url: jsUrl)
                jsRequest.setValue(YouTubeClient.userAgentWeb, forHTTPHeaderField: "User-Agent")

                let (jsData, _) = try await URLSession.shared.data(for: jsRequest)
                if let jsContent = String(data: jsData, encoding: .utf8) {
                    for pattern in patterns {
                        if let regex = try? NSRegularExpression(pattern: pattern),
                           let match = regex.firstMatch(in: jsContent, range: NSRange(jsContent.startIndex..., in: jsContent)),
                           let range = Range(match.range(at: 1), in: jsContent),
                           let timestamp = Int(jsContent[range])
                        {
                            self.cachedSignatureTimestamp = timestamp
                            self.signatureTimestampFetchTime = Date()
                            self.logger.info("Signature timestamp extracted from player.js: \(timestamp)")
                            return timestamp
                        }
                    }
                }
            }
        }

        self.logger.warning("Could not extract signature timestamp, using default")
        return 20117
    }

    /// Fetches player data for a video, returning stream URLs and metadata.
    /// - Parameters:
    ///   - videoId: The video ID to get player data for
    ///   - playlistId: Optional playlist ID for context
    ///   - client: The YouTube client to use (defaults to iOS)
    ///   - signatureTimestamp: Optional signature timestamp for WEB_REMIX client
    /// - Returns: PlayerResponse containing stream URLs and video metadata
    func getPlayer(
        videoId: String,
        playlistId: String? = nil,
        client: YouTubeClient? = nil,
        signatureTimestamp: Int? = nil
    ) async throws -> PlayerResponse {
        let client = client ?? .ios
        self.logger.info("Fetching player data for: \(videoId) using \(client.clientName)")

        var body: [String: Any] = [
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]

        if let playlistId {
            body["playlistId"] = playlistId
        }

        // Add playbackContext with signatureTimestamp for clients that need it
        if client.useSignatureTimestamp, let sts = signatureTimestamp {
            body["playbackContext"] = [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS",
                    "signatureTimestamp": sts,
                ],
            ]
        }

        let data = try await requestWithClient("player", body: body, client: client, setLogin: client.loginSupported)

        // Parse response using Codable
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let response = try JSONDecoder().decode(PlayerResponse.self, from: jsonData)

        guard response.isPlayable else {
            self.logger.error("Video not playable: \(response.playabilityStatus.reason ?? response.playabilityStatus.status)")
            throw PlayerError(status: response.playabilityStatus.status, reason: response.playabilityStatus.reason)
        }

        // Debug logging for audio formats
        if let streamingData = response.streamingData {
            let allAdaptive = streamingData.adaptiveFormats
            let audioOnly = allAdaptive.filter { $0.isAudio }
            let withUrl = audioOnly.filter { $0.url != nil }
            let withCipher = audioOnly.filter { $0.signatureCipher != nil }
            self.logger.info("Player data: adaptiveFormats=\(allAdaptive.count), audio=\(audioOnly.count), withUrl=\(withUrl.count), withCipher=\(withCipher.count)")
        } else {
            self.logger.warning("Player data: streamingData is nil")
        }
        return response
    }

    /// Gets the best audio stream URL for a video.
    /// - Parameters:
    ///   - videoId: The video ID
    ///   - playlistId: Optional playlist ID for context
    /// - Returns: URL to the best quality audio stream
    func getAudioStreamURL(videoId: String, playlistId: String? = nil) async throws -> URL {
        let player = try await getPlayer(videoId: videoId, playlistId: playlistId)

        guard let format = player.bestHighQualityFormat(),
              let urlString = format.url,
              let url = URL(string: urlString)
        else {
            throw YTMusicError.playbackError(message: "No audio stream available")
        }

        self.logger.info("Audio stream URL obtained: itag=\(format.itag), bitrate=\(format.bitrate ?? 0)")
        return url
    }

    // MARK: - Private Methods

    /// Builds the standard context payload using WebKitManager constants.
    private func buildContext() -> [String: Any] {
        let settings = AppDefaults.shared

        return [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": Self.clientVersion,
                "hl": settings.contentLanguage.apiLanguageCode,
                "gl": settings.contentRegion.rawValue,
                "experimentIds": [],
                "experimentsToken": "",
                "browserName": "Safari",
                "browserVersion": WebKitManager.safariVersion,
                "osName": WebKitManager.osName,
                "osVersion": WebKitManager.osVersion,
                "platform": WebKitManager.platform,
                "userAgent": WebKitManager.userAgent,
                "utcOffsetMinutes": -TimeZone.current.secondsFromGMT() / 60,
            ],
            "user": [
                "lockedSafetyMode": false,
            ],
        ]
    }

    /// Makes an authenticated request to the API.
    /// Authentication headers and retry logic are handled by the session's interceptor.
    private func request(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        try await requestWithClient(endpoint, body: body, client: nil, setLogin: true)
    }

    /// Makes a request using a specific YouTube client configuration.
    /// - Parameters:
    ///   - endpoint: The API endpoint
    ///   - body: Request body
    ///   - client: Optional YouTube client config (uses default WEB_REMIX context if nil)
    ///   - setLogin: Whether to include auth headers
    private func requestWithClient(
        _ endpoint: String,
        body: [String: Any],
        client: YouTubeClient?,
        setLogin: Bool
    ) async throws -> [String: Any] {
        let urlString = "\(Self.baseURL)/\(endpoint)?prettyPrint=false"

        // Build request body with context
        var fullBody = body
        if let client {
            // Use the custom client's context
            fullBody["context"] = client.toContext()
        } else {
            fullBody["context"] = self.buildContext()
        }

        self.logger.debug("Making request to \(endpoint)")

        // Serialize body to JSON Data (Sendable) before async boundary
        let bodyData = try JSONSerialization.data(withJSONObject: fullBody)

        // Build URLRequest (Sendable) with all headers
        guard let url = URL(string: urlString) else {
            throw YTMusicError.apiError(message: "Invalid URL", code: nil)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = bodyData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(WebKitManager.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        urlRequest.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        urlRequest.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        urlRequest.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        urlRequest.setValue(Self.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")

        if let client {
            urlRequest.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
            urlRequest.setValue(client.clientId, forHTTPHeaderField: "X-YouTube-Client-Name")
            urlRequest.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        }

        // Add auth headers if login is supported and requested
        if setLogin {
            if let cookieHeader = await webKitManager.cookieHeader(for: "youtube.com") {
                urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            if let sapisid = await webKitManager.getSAPISID() {
                let timestamp = Int(Date().timeIntervalSince1970)
                let origin = WebKitManager.origin
                let hashInput = "\(timestamp) \(sapisid) \(origin)"
                let hash = Insecure.SHA1.hash(data: Data(hashInput.utf8))
                    .map { String(format: "%02x", $0) }
                    .joined()
                urlRequest.setValue("SAPISIDHASH \(timestamp)_\(hash)", forHTTPHeaderField: "Authorization")
                urlRequest.setValue(origin, forHTTPHeaderField: "Origin")
                urlRequest.setValue(origin, forHTTPHeaderField: "X-Origin")
            }
        }

        // Alamofire request with URLRequest (Sendable)
        let response = await self.session.request(urlRequest)
            .validate(statusCode: 200 ..< 300)
            .serializingData()
            .response

        switch response.result {
        case let .success(data):
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw YTMusicError.parseError(message: "Response is not a JSON object")
            }
            return json

        case let .failure(error):
            throw self.mapAlamofireError(error, response: response.response)
        }
    }

    /// Maps Alamofire errors to YTMusicError.
    private func mapAlamofireError(_ error: AFError, response: HTTPURLResponse?) -> YTMusicError {
        // Check for auth errors from status code first
        if let statusCode = response?.statusCode {
            if statusCode == 401 || statusCode == 403 {
                self.logger.error("Auth error: HTTP \(statusCode)")
                return .authExpired
            }
            if !(200 ..< 300).contains(statusCode) {
                self.logger.error("API error: HTTP \(statusCode)")
                return .apiError(message: "HTTP \(statusCode)", code: statusCode)
            }
        }

        // Handle AFError types
        switch error {
        case let .sessionTaskFailed(underlying):
            return .networkError(underlying: underlying)
        case let .responseValidationFailed(reason):
            if case let .unacceptableStatusCode(code) = reason {
                if code == 401 || code == 403 {
                    return .authExpired
                }
                return .apiError(message: "HTTP \(code)", code: code)
            }
            return .unknown(message: error.localizedDescription)
        case .responseSerializationFailed:
            return .parseError(message: error.localizedDescription)
        default:
            return .networkError(underlying: error)
        }
    }
}

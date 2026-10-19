import Foundation
import os

/// Parser for artist-related responses from the API.
enum ArtistParser {
    private static let logger = DiagnosticsLogger.api

    /// Parses library albums from browse response.
    static func parseLibraryAlbums(_ data: [String: Any]) -> [Album] {
        var albums: [Album] = []

        // Navigate to contents
        guard let contents = data["contents"] as? [String: Any],
              let singleColumnBrowseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumnBrowseResults["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            return []
        }

        for sectionData in sectionContents {
            // Try gridRenderer (most common for library albums)
            if let gridRenderer = sectionData["gridRenderer"] as? [String: Any],
               let items = gridRenderer["items"] as? [[String: Any]]
            {
                for itemData in items {
                    if let twoRowRenderer = itemData["musicTwoRowItemRenderer"] as? [String: Any],
                       let album = parseAlbumFromTwoRowRenderer(twoRowRenderer)
                    {
                        albums.append(album)
                    }
                }
            }

            // Try musicShelfRenderer (alternative format)
            if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
               let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
            {
                for shelfItem in shelfContents {
                    if let responsiveRenderer = shelfItem["musicResponsiveListItemRenderer"] as? [String: Any],
                       let album = parseAlbumFromResponsiveRenderer(responsiveRenderer)
                    {
                        albums.append(album)
                    }
                }
            }
        }

        return albums
    }

    /// Parses an album from musicResponsiveListItemRenderer.
    private static func parseAlbumFromResponsiveRenderer(_ data: [String: Any]) -> Album? {
        guard let navigationEndpoint = data["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String,
              browseId.hasPrefix("MPRE") || browseId.hasPrefix("OLAK")
        else {
            return nil
        }

        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }
        let title = ParsingHelpers.extractTitleFromFlexColumns(data) ?? "Unknown Album"

        // Extract artist from subtitle
        let artist = ParsingHelpers.extractSubtitleFromFlexColumns(data)

        return Album(
            id: browseId,
            title: title,
            artists: artist.map { [Artist(id: "", name: $0, thumbnailURL: nil)] },
            thumbnailURL: thumbnailURL,
            year: nil,
            trackCount: nil
        )
    }

    /// Parses library artists from browse response.
    static func parseLibraryArtists(_ data: [String: Any]) -> [Artist] {
        var artists: [Artist] = []

        // Navigate to contents
        guard let contents = data["contents"] as? [String: Any],
              let singleColumnBrowseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumnBrowseResults["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            return []
        }

        for sectionData in sectionContents {
            // Try gridRenderer (most common for library artists)
            if let gridRenderer = sectionData["gridRenderer"] as? [String: Any],
               let items = gridRenderer["items"] as? [[String: Any]]
            {
                for itemData in items {
                    if let twoRowRenderer = itemData["musicTwoRowItemRenderer"] as? [String: Any],
                       let artist = parseArtistFromTwoRowRenderer(twoRowRenderer)
                    {
                        artists.append(artist)
                    }
                }
            }

            // Try musicShelfRenderer (alternative format)
            if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
               let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
            {
                for shelfItem in shelfContents {
                    if let responsiveRenderer = shelfItem["musicResponsiveListItemRenderer"] as? [String: Any],
                       let artist = parseArtistFromResponsiveRenderer(responsiveRenderer)
                    {
                        artists.append(artist)
                    }
                }
            }
        }

        return artists
    }

    /// Parses artist detail from browse response.
    static func parseArtistDetail(_ data: [String: Any], artistId: String) -> ArtistDetail {
        var songs: [Song] = []
        var albumSections: [AlbumSection] = []
        var playlists: [Playlist] = []
        var hasMoreSongs = false
        var songsBrowseId: String?
        var songsParams: String?

        // Parse header
        let headerResult = self.parseArtistHeader(data, artistId: artistId)

        // Parse content sections for songs and albums
        if let contents = data["contents"] as? [String: Any],
           let singleColumnBrowseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumnBrowseResults["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
           let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        {
            for sectionData in sectionContents {
                // Parse songs from musicShelfRenderer
                if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
                   let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
                {
                    songs.append(contentsOf: self.parseTracksFromItems(shelfContents))

                    // Check if there are more songs available via bottomEndpoint
                    if let bottomEndpoint = shelfRenderer["bottomEndpoint"] as? [String: Any],
                       let browseEndpoint = bottomEndpoint["browseEndpoint"] as? [String: Any],
                       let browseId = browseEndpoint["browseId"] as? String
                    {
                        hasMoreSongs = true
                        songsBrowseId = browseId
                        songsParams = browseEndpoint["params"] as? String
                    } else if shelfRenderer["continuations"] != nil {
                        hasMoreSongs = true
                    }
                }

                // Parse album sections from musicCarouselShelfRenderer
                if let carouselRenderer = sectionData["musicCarouselShelfRenderer"] as? [String: Any],
                   let carouselContents = carouselRenderer["contents"] as? [[String: Any]]
                {
                    // Get the carousel section title and more endpoint from header
                    let sectionTitle = self.extractCarouselTitle(from: carouselRenderer)
                    let moreEndpoint = self.extractMoreEndpoint(from: carouselRenderer)

                    // Parse albums, songs, and playlists from this carousel
                    var albums: [Album] = []
                    var carouselSongs: [Song] = []
                    var carouselPlaylists: [Playlist] = []

                    for itemData in carouselContents {
                        if let twoRowRenderer = itemData["musicTwoRowItemRenderer"] as? [String: Any] {
                            // Try parsing as album first
                            if let album = parseAlbumFromTwoRowRenderer(twoRowRenderer) {
                                albums.append(album)
                            }
                            // Try parsing as playlist
                            else if let playlist = parsePlaylistFromTwoRowRenderer(twoRowRenderer) {
                                carouselPlaylists.append(playlist)
                            }
                            // Try parsing as song/video (for video-only channels)
                            else if let song = parseSongFromTwoRowRenderer(twoRowRenderer) {
                                carouselSongs.append(song)
                            }
                        }
                    }

                    // Add album section if it contains albums
                    if !albums.isEmpty {
                        albumSections.append(AlbumSection(
                            title: sectionTitle ?? "Albums",
                            albums: albums,
                            moreBrowseId: moreEndpoint?.browseId,
                            moreParams: moreEndpoint?.params
                        ))
                    }

                    // Add playlists from carousel
                    if !carouselPlaylists.isEmpty {
                        playlists.append(contentsOf: carouselPlaylists)
                    }

                    // Add songs from carousel to main songs list (for video-only channels)
                    if !carouselSongs.isEmpty {
                        songs.append(contentsOf: carouselSongs)
                    }
                }
            }
        }

        let artist = Artist(id: artistId, name: headerResult.name, thumbnailURL: headerResult.thumbnailURL)

        logger.info("Parsed artist '\(headerResult.name)': \(songs.count) songs, \(albumSections.count) album sections, \(playlists.count) playlists")

        return ArtistDetail(
            artist: artist,
            description: headerResult.description,
            songs: songs,
            albumSections: albumSections,
            playlists: playlists,
            thumbnailURL: headerResult.thumbnailURL,
            channelId: headerResult.channelId,
            isSubscribed: headerResult.isSubscribed,
            subscriberCount: headerResult.subscriberCount,
            hasMoreSongs: hasMoreSongs,
            songsBrowseId: songsBrowseId,
            songsParams: songsParams
        )
    }

    /// Extracts the title from a carousel shelf header.
    private static func extractCarouselTitle(from carouselRenderer: [String: Any]) -> String? {
        guard let header = carouselRenderer["header"] as? [String: Any],
              let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
              let title = basicHeader["title"] as? [String: Any],
              let runs = title["runs"] as? [[String: Any]],
              let firstRun = runs.first,
              let text = firstRun["text"] as? String
        else {
            return nil
        }
        return text
    }

    /// Extracts the "more" browse endpoint from a carousel shelf header.
    private static func extractMoreEndpoint(from carouselRenderer: [String: Any]) -> (browseId: String, params: String?)? {
        guard let header = carouselRenderer["header"] as? [String: Any],
              let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
              let moreButton = basicHeader["moreContentButton"] as? [String: Any],
              let buttonRenderer = moreButton["buttonRenderer"] as? [String: Any],
              let navEndpoint = buttonRenderer["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String
        else {
            return nil
        }
        let params = browseEndpoint["params"] as? String
        return (browseId, params)
    }

    // MARK: - Header Parsing

    /// Holds parsed header information for an artist.
    private struct HeaderParseResult {
        var name: String = "Unknown Artist"
        var description: String?
        var thumbnailURL: URL?
        var channelId: String?
        var isSubscribed: Bool = false
        var subscriberCount: String?
    }

    private static func parseArtistHeader(_ data: [String: Any], artistId: String) -> HeaderParseResult {
        var result = HeaderParseResult()
        result.channelId = artistId.hasPrefix("UC") ? artistId : nil

        // Try musicImmersiveHeaderRenderer (common for artist pages)
        if let header = data["header"] as? [String: Any],
           let immersiveHeader = header["musicImmersiveHeaderRenderer"] as? [String: Any]
        {
            if let text = ParsingHelpers.extractTitle(from: immersiveHeader) {
                result.name = text
            }

            if let descData = immersiveHeader["description"] as? [String: Any],
               let runs = descData["runs"] as? [[String: Any]]
            {
                result.description = runs.compactMap { $0["text"] as? String }.joined()
            }

            let thumbnails = ParsingHelpers.extractThumbnails(from: immersiveHeader)
            result.thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }

            // Parse subscription button for channel ID and subscription status
            self.parseSubscriptionButton(from: immersiveHeader, into: &result)
        }

        // Try musicVisualHeaderRenderer (alternative header format)
        if result.name == "Unknown Artist",
           let header = data["header"] as? [String: Any],
           let visualHeader = header["musicVisualHeaderRenderer"] as? [String: Any]
        {
            if let text = ParsingHelpers.extractTitle(from: visualHeader) {
                result.name = text
            }

            let thumbnails = ParsingHelpers.extractThumbnails(from: visualHeader)
            result.thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }

            // Parse subscription button for channel ID and subscription status
            self.parseSubscriptionButton(from: visualHeader, into: &result)
        }

        return result
    }

    // MARK: - Subscription Parsing

    private static func parseSubscriptionButton(from header: [String: Any], into result: inout HeaderParseResult) {
        // Look for subscriptionButton in header
        if let subscriptionButton = header["subscriptionButton"] as? [String: Any],
           let subscribeButtonRenderer = subscriptionButton["subscribeButtonRenderer"] as? [String: Any]
        {
            // Extract channel ID
            if let extractedChannelId = subscribeButtonRenderer["channelId"] as? String {
                result.channelId = extractedChannelId
            }

            // Check subscription status
            if let subscribed = subscribeButtonRenderer["subscribed"] as? Bool {
                result.isSubscribed = subscribed
            }

            // Extract subscriber count text
            if let subscriberCountText = subscribeButtonRenderer["subscriberCountText"] as? [String: Any],
               let runs = subscriberCountText["runs"] as? [[String: Any]]
            {
                result.subscriberCount = runs.compactMap { $0["text"] as? String }.joined()
            } else if let shortSubscriberCountText = subscribeButtonRenderer["shortSubscriberCountText"] as? [String: Any],
                      let runs = shortSubscriberCountText["runs"] as? [[String: Any]]
            {
                result.subscriberCount = runs.compactMap { $0["text"] as? String }.joined()
            }
        }

        // Alternative: look in menu for subscription status
        if let menu = header["menu"] as? [String: Any],
           let menuRenderer = menu["menuRenderer"] as? [String: Any],
           let items = menuRenderer["items"] as? [[String: Any]]
        {
            for item in items {
                if let toggleMenuItem = item["toggleMenuServiceItemRenderer"] as? [String: Any],
                   let defaultIcon = toggleMenuItem["defaultIcon"] as? [String: Any],
                   let iconType = defaultIcon["iconType"] as? String
                {
                    if iconType == "SUBSCRIBE" || iconType == "NOTIFICATION_OFF" {
                        result.isSubscribed = false
                    } else if iconType == "SUBSCRIBED" || iconType == "NOTIFICATION_ON" {
                        result.isSubscribed = true
                    }
                }
            }
        }
    }

    // MARK: - Content Parsing

    /// Parses songs from artist songs browse response.
    static func parseArtistSongs(_ data: [String: Any]) -> [Song] {
        var songs: [Song] = []

        // Try parsing from musicShelfRenderer in sectionListRenderer
        if let contents = data["contents"] as? [String: Any],
           let singleColumnBrowseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumnBrowseResults["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
           let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        {
            for sectionData in sectionContents {
                if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
                   let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
                {
                    songs.append(contentsOf: self.parseTracksFromItems(shelfContents))
                }
            }
        }

        // Try parsing from musicPlaylistShelfRenderer (alternative format)
        if songs.isEmpty,
           let contents = data["contents"] as? [String: Any],
           let singleColumnBrowseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumnBrowseResults["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
           let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        {
            for sectionData in sectionContents {
                if let playlistRenderer = sectionData["musicPlaylistShelfRenderer"] as? [String: Any],
                   let playlistContents = playlistRenderer["contents"] as? [[String: Any]]
                {
                    songs.append(contentsOf: self.parseTracksFromItems(playlistContents))
                }
            }
        }

        return songs
    }

    /// Parses albums from artist albums browse response.
    static func parseArtistAlbums(_ data: [String: Any]) -> [Album] {
        var albums: [Album] = []

        // Navigate to sectionListRenderer contents
        guard let contents = data["contents"] as? [String: Any],
              let singleColumnBrowseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumnBrowseResults["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let tabContent = tabRenderer["content"] as? [String: Any],
              let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        else {
            return []
        }

        for sectionData in sectionContents {
            // Try gridRenderer (common for album grids)
            if let gridRenderer = sectionData["gridRenderer"] as? [String: Any],
               let items = gridRenderer["items"] as? [[String: Any]]
            {
                for itemData in items {
                    if let twoRowRenderer = itemData["musicTwoRowItemRenderer"] as? [String: Any],
                       let album = parseAlbumFromTwoRowRenderer(twoRowRenderer)
                    {
                        albums.append(album)
                    }
                }
            }

            // Try musicCarouselShelfRenderer (alternative format)
            if let carouselRenderer = sectionData["musicCarouselShelfRenderer"] as? [String: Any],
               let carouselContents = carouselRenderer["contents"] as? [[String: Any]]
            {
                for itemData in carouselContents {
                    if let twoRowRenderer = itemData["musicTwoRowItemRenderer"] as? [String: Any],
                       let album = parseAlbumFromTwoRowRenderer(twoRowRenderer)
                    {
                        albums.append(album)
                    }
                }
            }
        }

        return albums
    }

    private static func parseTracksFromItems(_ items: [[String: Any]], fallbackThumbnailURL: URL? = nil) -> [Song] {
        var tracks: [Song] = []

        for itemData in items {
            guard let responsiveRenderer = itemData["musicResponsiveListItemRenderer"] as? [String: Any] else {
                continue
            }

            guard let videoId = ParsingHelpers.extractVideoId(from: responsiveRenderer) else {
                continue
            }

            let title = ParsingHelpers.extractTitleFromFlexColumns(responsiveRenderer) ?? "Unknown"
            let artists = ParsingHelpers.extractArtistsFromFlexColumns(responsiveRenderer)
            let thumbnails = ParsingHelpers.extractThumbnails(from: responsiveRenderer)
            let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) } ?? fallbackThumbnailURL
            let duration = ParsingHelpers.extractDurationFromFlexColumns(responsiveRenderer)
            let videoType = ParsingHelpers.extractVideoType(from: responsiveRenderer)

            let track = Song(
                id: videoId,
                title: title,
                artists: artists,
                album: nil,
                duration: duration,
                thumbnailURL: thumbnailURL,
                videoId: videoId,
                videoType: videoType
            )
            tracks.append(track)
        }

        return tracks
    }

    /// Parses a playlist from musicTwoRowItemRenderer.
    private static func parsePlaylistFromTwoRowRenderer(_ data: [String: Any]) -> Playlist? {
        // Playlists have a browseEndpoint with browseId starting with "VL" or "PL"
        guard let navigationEndpoint = data["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String,
              browseId.hasPrefix("VL") || browseId.hasPrefix("PL")
        else {
            return nil
        }

        let title = ParsingHelpers.extractTitle(from: data) ?? "Unknown Playlist"
        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }

        // Extract author from subtitle
        var author: String?
        if let subtitleData = data["subtitle"] as? [String: Any],
           let runs = subtitleData["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String
        {
            author = text
        }

        // Remove "VL" prefix if present for the ID
        let playlistId = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId

        return Playlist(
            id: playlistId,
            title: title,
            description: nil,
            thumbnailURL: thumbnailURL,
            trackCount: nil,
            author: author
        )
    }

    /// Parses a song/video from musicTwoRowItemRenderer (used for video-only channels).
    private static func parseSongFromTwoRowRenderer(_ data: [String: Any]) -> Song? {
        // Videos/songs have a watchEndpoint with videoId
        guard let navigationEndpoint = data["navigationEndpoint"] as? [String: Any],
              let watchEndpoint = navigationEndpoint["watchEndpoint"] as? [String: Any],
              let videoId = watchEndpoint["videoId"] as? String
        else {
            return nil
        }

        let title = ParsingHelpers.extractTitle(from: data) ?? "Unknown"
        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }

        // Extract artist from subtitle
        var artists: [Artist] = []
        if let subtitleData = data["subtitle"] as? [String: Any],
           let runs = subtitleData["runs"] as? [[String: Any]]
        {
            for run in runs {
                if let text = run["text"] as? String,
                   let navEndpoint = run["navigationEndpoint"] as? [String: Any],
                   let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                   let browseId = browseEndpoint["browseId"] as? String,
                   browseId.hasPrefix("UC")
                {
                    artists.append(Artist(id: browseId, name: text, thumbnailURL: nil))
                }
            }
            // Fallback: use first text run as artist name if no browse endpoint
            if artists.isEmpty, let firstRun = runs.first, let text = firstRun["text"] as? String {
                artists.append(Artist(id: "", name: text, thumbnailURL: nil))
            }
        }

        let videoType = ParsingHelpers.extractVideoType(from: data)

        return Song(
            id: videoId,
            title: title,
            artists: artists,
            album: nil,
            duration: nil,
            thumbnailURL: thumbnailURL,
            videoId: videoId,
            videoType: videoType
        )
    }

    private static func parseAlbumFromTwoRowRenderer(_ data: [String: Any]) -> Album? {
        guard let navigationEndpoint = data["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String,
              browseId.hasPrefix("MPRE") || browseId.hasPrefix("OLAK")
        else {
            return nil
        }

        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }
        let title = ParsingHelpers.extractTitle(from: data) ?? "Unknown Album"

        var year: String?
        if let subtitleData = data["subtitle"] as? [String: Any],
           let runs = subtitleData["runs"] as? [[String: Any]]
        {
            // Year is typically the last item in subtitle
            year = runs.last?["text"] as? String
        }

        return Album(
            id: browseId,
            title: title,
            artists: nil,
            thumbnailURL: thumbnailURL,
            year: year,
            trackCount: nil
        )
    }

    // MARK: - Artist List Item Parsing

    /// Parses an artist from musicTwoRowItemRenderer (used in grid views).
    private static func parseArtistFromTwoRowRenderer(_ data: [String: Any]) -> Artist? {
        guard let navigationEndpoint = data["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String
        else {
            return nil
        }

        // Verify this is an artist (browseId typically starts with UC for channels/artists)
        guard browseId.hasPrefix("UC") || browseId.hasPrefix("FE") else {
            return nil
        }

        let name = ParsingHelpers.extractTitle(from: data) ?? "Unknown Artist"
        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }

        return Artist(id: browseId, name: name, thumbnailURL: thumbnailURL)
    }

    /// Parses an artist from musicResponsiveListItemRenderer (used in list views).
    private static func parseArtistFromResponsiveRenderer(_ data: [String: Any]) -> Artist? {
        guard let navigationEndpoint = data["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String
        else {
            return nil
        }

        // Verify this is an artist
        guard browseId.hasPrefix("UC") || browseId.hasPrefix("FE") else {
            return nil
        }

        let name = ParsingHelpers.extractTitleFromFlexColumns(data) ?? "Unknown Artist"
        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }

        return Artist(id: browseId, name: name, thumbnailURL: thumbnailURL)
    }
}

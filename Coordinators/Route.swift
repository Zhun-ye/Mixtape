//
//  Route.swift
//  Mixtape
//

enum Route {
    case loading
    case signIn
    case signInRedirector
    case home
    case search
    case discovery
    case library
    case playlist(Playlist)
    case artist(Artist)
    case moodCategory(MoodCategory)
    case topSongs(TopSongsDestination)
    case allAlbums(AlbumSection)
    case sectionGrid(HomeSection)
    case moods
    case downloads
}

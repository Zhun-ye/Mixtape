//
//  Coordinatable.swift
//  Mixtape
//

import SwiftUI
@preconcurrency import SwiftUINavigation

// MARK: - HashableObject (nonisolated)

/// Nonisolated HashableObject for coordinators.
/// Provides identity-based equality and hashing for class types.
/// Not MainActor-isolated since Hashable requirements are nonisolated.
protocol CoordinatorHashable: AnyObject, Hashable {}

extension CoordinatorHashable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// MARK: - Protocols

/// Delegate for child coordinators to communicate with AppCoordinator.
@MainActor
protocol AppCoordinatorDelegate: AnyObject {
    func didRequestSettings()
    func didRequestSwitchToHome()
}

/// Delegate for ViewModels to request navigation from their Coordinator.
@MainActor
protocol CoordinatableDelegate: AnyObject {
    func didSelectPlaylist(_ playlist: Playlist)
    func didSelectArtist(_ artist: Artist)
    func didSelectAlbum(_ album: Album)
    func didSelectSection(_ section: HomeSection)
    func didSelectTopSongs(_ destination: TopSongsDestination)
    func didSelectAllAlbums(_ section: AlbumSection)
    func didSelectMoodsAndGenres()
    func didSelectDownloads()
    func didRequestSettings()
}

/// Core protocol for navigation coordinators.
@MainActor
protocol Coordinatable: CoordinatorHashable,
    CoordinatableDelegate,
    SignInRedirectorViewModelDelegate {

    var path: [Destination] { get set }
    var root: Destination { get set }
    var delegate: AppCoordinatorDelegate? { get }

    func makeDestination(for route: Route) -> Destination
}

// MARK: - Navigation

extension Coordinatable {
    func navigate(to route: Route) {
        let destination = makeDestination(for: route)
        path.append(destination)
    }

    func setRoot(to route: Route) {
        let destination = makeDestination(for: route)
        root = destination
    }

    func popToRoot() {
        path.removeAll()
    }
}

// MARK: - CoordinatableDelegate

extension Coordinatable {
    func didSelectPlaylist(_ playlist: Playlist) {
        if MoodCategory.isMoodCategory(playlist.id),
           let parsed = MoodCategory.parseId(playlist.id) {
            let category = MoodCategory(
                browseId: parsed.browseId,
                params: parsed.params,
                title: playlist.title
            )
            navigate(to: .moodCategory(category))
        } else {
            navigate(to: .playlist(playlist))
        }
    }

    func didSelectArtist(_ artist: Artist) {
        navigate(to: .artist(artist))
    }

    func didSelectAlbum(_ album: Album) {
        let playlist = Playlist(
            id: album.id,
            title: album.title,
            description: nil,
            thumbnailURL: album.thumbnailURL,
            trackCount: album.trackCount,
            author: album.artistsDisplay
        )
        navigate(to: .playlist(playlist))
    }

    func didSelectSection(_ section: HomeSection) {
        navigate(to: .sectionGrid(section))
    }

    func didSelectTopSongs(_ destination: TopSongsDestination) {
        navigate(to: .topSongs(destination))
    }

    func didSelectAllAlbums(_ section: AlbumSection) {
        navigate(to: .allAlbums(section))
    }

    func didSelectMoodsAndGenres() {
        navigate(to: .moods)
    }

    func didSelectDownloads() {
        navigate(to: .downloads)
    }

    func didRequestSettings() {
        delegate?.didRequestSettings()
    }
}

// MARK: - SignInRedirectorViewModelDelegate

extension Coordinatable {
    func didRequestSignIn() {
        delegate?.didRequestSwitchToHome()
    }
}

// MARK: - Destination Factory

extension Coordinatable {
    func makeDestination(for route: Route) -> Destination {
        switch route {
        case .loading:
            return .loading
        case .signIn:
            return .signIn
        case .signInRedirector:
            let vm = SignInRedirectorViewModel()
            vm.delegate = self
            return .signInRedirector(vm)
        case .home:
            let vm = HomeViewModel()
            vm.delegate = self
            return .home(vm)
        case .discovery:
            let vm = DiscoveryViewModel()
            vm.delegate = self
            return .discovery(vm)
        case .moods:
            let vm = MoodsAndGenresViewModel()
            vm.delegate = self
            return .moods(vm)
        case .search, .library:
            return .loading // These use stored view models, set root directly
        case .playlist(let playlist):
            return .playlist(PlaylistDetailViewModel(playlist: playlist))
        case .artist(let artist):
            let vm = ArtistDetailViewModel(artist: artist)
            vm.delegate = self
            return .artist(vm)
        case .moodCategory(let category):
            let vm = MoodCategoryViewModel(category: category)
            vm.delegate = self
            return .moodCategory(vm)
        case .topSongs(let destination):
            return .topSongs(TopSongsViewModel(destination: destination))
        case .allAlbums(let section):
            let vm = AllAlbumsViewModel(section: section)
            vm.delegate = self
            return .allAlbums(vm)
        case .sectionGrid(let section):
            let vm = SectionGridViewModel(section: section)
            vm.delegate = self
            return .sectionGrid(vm)
        case .downloads:
            let vm = DownloadsViewModel()
            vm.delegate = self
            return .downloads(vm)
        }
    }
}

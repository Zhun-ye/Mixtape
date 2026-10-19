//
//  Destination.swift
//  Mixtape
//

import CasePaths
import SwiftUI

/// Navigation destination for coordinators.
@CasePathable
enum Destination: Hashable {
    // MARK: - Root Views

    case signIn
    case signInRedirector(SignInRedirectorViewModel)
    case home(HomeViewModel)
    case search(SearchViewModel)
    case library(LibraryViewModel)
    case libraryArtists(LibraryViewModel)
    case libraryAlbums(LibraryViewModel)
    case discovery(DiscoveryViewModel)
    case charts(ChartsViewModel)
    case moods(MoodsAndGenresViewModel)
    case newReleases(NewReleasesViewModel)

    // MARK: - Detail Views

    case playlist(PlaylistDetailViewModel)
    case artist(ArtistDetailViewModel)
    case moodCategory(MoodCategoryViewModel)
    case topSongs(TopSongsViewModel)
    case allAlbums(AllAlbumsViewModel)
    case sectionGrid(SectionGridViewModel)
    case downloads(DownloadsViewModel)

    // MARK: - Empty

    case loading
    case none
}

// MARK: - View

extension Destination {
    @ViewBuilder
    func view(focusTrigger: Binding<Bool>) -> some View {
        switch self {
        case .search(let viewModel):
            SearchContentView(viewModel: viewModel, focusTrigger: focusTrigger)
        default:
            view()
        }
    }

    @ViewBuilder
    func view() -> some View {
        switch self {
        case .loading:
            LoadingView()
        case .none:
            EmptyView()
        case .signIn:
            SignInView()
        case .signInRedirector(let viewModel):
            SignInRedirectorView(viewModel: viewModel)
        case .home(let viewModel):
            HomeContentView(viewModel: viewModel)
        case .search(let viewModel):
            SearchContentView(viewModel: viewModel, focusTrigger: .constant(false))
        case .library(let viewModel):
            LibraryContentView(viewModel: viewModel)
        case .libraryArtists(let viewModel):
            LibraryArtistsView(viewModel: viewModel)
        case .libraryAlbums(let viewModel):
            LibraryAlbumsView(viewModel: viewModel)
        case .discovery(let viewModel):
            DiscoveryContentView(viewModel: viewModel)
        case .charts(let viewModel):
            ChartsContentView(viewModel: viewModel)
        case .moods(let viewModel):
            MoodsAndGenresContentView(viewModel: viewModel)
        case .newReleases(let viewModel):
            NewReleasesContentView(viewModel: viewModel)
        case .playlist(let viewModel):
            PlaylistDetailView(viewModel: viewModel)
        case .artist(let viewModel):
            ArtistDetailView(viewModel: viewModel)
        case .moodCategory(let viewModel):
            MoodCategoryView(viewModel: viewModel)
        case .topSongs(let viewModel):
            TopSongsView(viewModel: viewModel)
        case .allAlbums(let viewModel):
            AllAlbumsView(viewModel: viewModel)
        case .sectionGrid(let viewModel):
            SectionGridView(viewModel: viewModel)
        case .downloads(let viewModel):
            DownloadsView(viewModel: viewModel)
        }
    }
}

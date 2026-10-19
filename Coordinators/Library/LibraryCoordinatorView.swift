//
//  LibraryCoordinatorView.swift
//  Mixtape
//
//  Provides NavigationStack views for Library tabs.
//

import SwiftUI

struct LibraryCoordinatorView: View {
    @Bindable var coordinator: LibraryCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.root.view()
                .navigationDestination(for: Destination.self) { destination in
                    destination.view()
                }
                .navigationDestination(for: Playlist.self) { playlist in
                    PlaylistDetailView(viewModel: PlaylistDetailViewModel(playlist: playlist))
                }
                .navigationDestination(for: TopSongsDestination.self) { destination in
                    TopSongsView(viewModel: TopSongsViewModel(destination: destination))
                }
        }
    }
}

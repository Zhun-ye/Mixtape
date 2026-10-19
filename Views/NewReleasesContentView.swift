//
//  NewReleasesContentView.swift
//  Mixtape
//
//  Content view for New Releases tab, used with DiscoverCoordinator.
//

import SwiftUI

struct NewReleasesContentView: View {
    @Bindable var viewModel: NewReleasesViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(viewModel.sections) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .scrollClipDisabled()
        }
        .loading(viewModel.loadingState, message: "Loading new releases...") {
            viewModel.refresh()
        }
        .navigationTitle("New Releases")
        .onAppear {
            if viewModel.loadingState == .idle {
                Task {
                    await viewModel.load()
                }
            }
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    private func sectionView(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: .sectionItemSpacing) {
                    ForEach(section.items) { item in
                        self.itemCard(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemCard(item: HomeSectionItem) -> some View {
        switch item {
        case let .song(song):
            Button {
                Task { await viewModel.playerManager.playWithRadio(song: song) }
            } label: {
                SongCard(song: song)
            }
            .buttonStyle(.interactiveCard)
        case let .playlist(playlist):
            Button {
                self.viewModel.didSelectPlaylist(playlist)
            } label: {
                PlaylistCard(playlist: playlist)
            }
            .buttonStyle(.interactiveCard)
            .hoverPlay {
                Task { await self.viewModel.playPlaylist(playlist) }
            }
        case let .album(album):
            Button {
                self.viewModel.didSelectAlbum(album)
            } label: {
                AlbumCard(album: album)
            }
            .buttonStyle(.interactiveCard)
            .hoverPlay {
                Task { await self.viewModel.playAlbum(album) }
            }
        case let .artist(artist):
            Button {
                self.viewModel.didSelectArtist(artist)
            } label: {
                ArtistCard(artist: artist)
            }
            .buttonStyle(.interactiveCard)
        }
    }
}

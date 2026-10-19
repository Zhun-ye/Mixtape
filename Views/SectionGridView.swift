//
//  SectionGridView.swift
//  Mixtape
//
//  Grid view for displaying a HomeSection's items in a grid layout.
//

import SwiftUI

struct SectionGridView: View {
    @Bindable var viewModel: SectionGridViewModel

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: .adaptiveGridMinimum, maximum: .adaptiveGridMaximum), spacing: .sectionItemSpacing)],
                spacing: 32
            ) {
                ForEach(viewModel.items) { item in
                    itemCard(item: item)
                }
            }
            .padding(24)
            .contentMargins(.bottom, 60)
            .scrollClipDisabled()
        }
        .loading(viewModel.loadingState, message: "Loading...") {
            viewModel.refresh()
        }
        .navigationTitle(viewModel.section.title)
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
            .if(!playlist.isMoodOrGenreCategory) { view in
                view.hoverPlay {
                    Task { await self.viewModel.playPlaylist(playlist) }
                }
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

//
//  ExploreContentView.swift
//  Mixtape
//
//  Content view for Explore tab, used with DiscoverCoordinator.
//  This view does not include NavigationStack - that's provided by the coordinator.
//

import SwiftUI

struct DiscoveryContentView: View {
    @Bindable var viewModel: DiscoveryViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(viewModel.sections) { section in
                    sectionView(section)
                }
            }
            .padding(.vertical, 24)
            .scrollClipDisabled()
        }
        .loading(viewModel.loadingState) {
            await viewModel.load()
        }
    #if os(iOS)
        .inlineLargeTitle("Discovery") {
            Button {
                self.viewModel.didRequestSettings()
            } label: {
                UserProfileView(imageSize: 40)
            }
        }
    #else
        .navigationTitle("Discovery")
    #endif
        .refreshable {
            viewModel.refresh()
        }
    }

    private func sectionView(_ section: HomeSection) -> some View {
        SectionGroup(
            section: section,
            onNavigate: { self.viewModel.didSelectSection(section) }
        ) { item in
            self.itemCard(item: item)
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

#Preview {
    NavigationStack {
        DiscoveryContentView(viewModel: DiscoveryViewModel())
    }
}

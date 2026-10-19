//
//  HomeContentView.swift
//  Mixtape
//
//  Content view for Home tab, used with HomeCoordinator.
//  This view does not include NavigationStack - that's provided by the coordinator.
//

import SwiftUI

/// Home content view displaying personalized content sections.
/// Used by HomeCoordinator - navigation is handled via NavigationLink(value:).
struct HomeContentView: View {
    @Bindable var viewModel: HomeViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(self.viewModel.sections) { section in
                    self.sectionView(section)
                }

                if self.viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 24)
            .scrollClipDisabled()
        }
        .onScrollTargetVisibilityChange(idType: HomeSection.ID.self, threshold: 0.2) { visibleIDs in
            self.viewModel.loadMoreIfNeeded(visibleSectionIDs: Set(visibleIDs))
        }
        .loading(viewModel.loadingState) {
            await viewModel.load()
        }
    #if os(iOS)
        .inlineLargeTitle("Home") {
            Button {
                self.viewModel.didRequestSettings()
            } label: {
                UserProfileView(imageSize: 40)
            }
        }
    #else
        .navigationTitle("Home")
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

#Preview {
    NavigationStack {
        HomeContentView(viewModel: HomeViewModel())
    }
}

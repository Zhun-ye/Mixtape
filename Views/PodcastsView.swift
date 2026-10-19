import SwiftUI

/// Podcasts view for podcast discovery.
struct PodcastsView: View {
    @Bindable var viewModel: PodcastsViewModel
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.sections.isEmpty {
                    ContentUnavailableView(
                        "No Podcasts Available",
                        systemImage: "mic.slash",
                        description: Text("Podcasts may not be available in your region.")
                    )
                } else {
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
                }
            }
            .loading(viewModel.loadingState, message: "Loading podcasts...") {
                viewModel.refresh()
            }
            .navigationTitle("Podcasts")
        }
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
                self.navigationPath.append(playlist)
            } label: {
                PlaylistCard(playlist: playlist)
            }
            .buttonStyle(.interactiveCard)
            .hoverPlay {
                Task { await self.viewModel.playPlaylist(playlist) }
            }
        case let .album(album):
            Button {
                let playlist = Playlist(
                    id: album.id,
                    title: album.title,
                    description: nil,
                    thumbnailURL: album.thumbnailURL,
                    trackCount: album.trackCount,
                    author: album.artistsDisplay
                )
                self.navigationPath.append(playlist)
            } label: {
                AlbumCard(album: album)
            }
            .buttonStyle(.interactiveCard)
            .hoverPlay {
                Task { await self.viewModel.playAlbum(album) }
            }
        case let .artist(artist):
            Button {
                self.navigationPath.append(artist)
            } label: {
                ArtistCard(artist: artist)
            }
            .buttonStyle(.interactiveCard)
        }
    }
}

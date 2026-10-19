import SwiftUI

// MARK: - MoodCategoryDetailView

/// Detail view for a moods/genres category page.
/// Displays sections of songs and playlists for the selected mood/genre.
/// Note: This view is pushed onto an existing NavigationStack, so it uses NavigationLink
/// to leverage the parent's navigation context.
struct MoodCategoryView: View {
    @Bindable var viewModel: MoodCategoryViewModel

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
        .navigationTitle(viewModel.category.title)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private func sectionView(_ section: HomeSection) -> some View {
        SectionGroup(
            section: section,
            onNavigate: { self.viewModel.didSelectSection(section) }
        ) { item in
            self.itemView(item)
        }
    }

    /// Creates navigation-aware item views.
    @ViewBuilder
    private func itemView(_ item: HomeSectionItem) -> some View {
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

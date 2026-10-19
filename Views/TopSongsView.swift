import SwiftUI

/// View displaying all top songs for an artist.
struct TopSongsView: View {
    @Bindable var viewModel: TopSongsViewModel

    var body: some View {
        Group {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                if self.viewModel.songs.isEmpty {
                    LoadingView("Loading songs...")
                } else {
                    // Show existing songs while loading more
                    self.songsListView
                        .overlay(alignment: .top) {
                            if self.viewModel.loadingState == .loading {
                                ProgressView()
                                    .controlSize(.regular)
                                    .frame(width: 20, height: 20)
                                    .padding()
                            }
                        }
                }
            case .loaded, .loadingMore, .error:
                self.songsListView
            }
        }
        .navigationTitle("Top songs")
        .toolbarBackgroundVisibility(.hidden, for: .automatic)
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
    }

    // MARK: - Views

    private var songsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(self.viewModel.songs.enumerated()), id: \.element.id) { index, song in
                    self.songRow(song, index: index)

                    if index < self.viewModel.songs.count - 1 {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Song Row

    private func songRow(_ song: Song, index: Int) -> some View {
        let isCurrentTrack = viewModel.playerManager.currentTrack?.videoId == song.videoId
        let isPlaying = viewModel.playerManager.isPlaying

        return TopSongRowView(
            song: song,
            isCurrentTrack: isCurrentTrack,
            isPlaying: isPlaying
        ) {
            self.playSongInQueue(startingAt: index)
        }
        .contextMenu {
            Button {
                self.playSongInQueue(startingAt: index)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Divider()

            Button {
                Task { await viewModel.playerManager.playAndLike(song: song) }
            } label: {
                Label("Like", systemImage: "hand.thumbsup")
            }

            Button {
                Task { await viewModel.playerManager.playAndDislike(song: song) }
            } label: {
                Label("Dislike", systemImage: "hand.thumbsdown")
            }

            Divider()

            Button {
                Task { await viewModel.playerManager.playAndAddToLibrary(song: song) }
            } label: {
                Label("Add to Library", systemImage: "plus.circle")
            }

            // Go to Album - show if album has valid browse ID
            if let album = song.album, album.hasNavigableId {
                Divider()

                let playlist = Playlist(
                    id: album.id,
                    title: album.title,
                    description: nil,
                    thumbnailURL: album.thumbnailURL,
                    trackCount: album.trackCount,
                    author: album.artistsDisplay
                )
                NavigationLink(value: playlist) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
        }
    }

    // MARK: - Actions

    private func playSongInQueue(startingAt index: Int) {
        Task {
            await viewModel.playerManager.playQueue(self.viewModel.songs, startingAt: index)
        }
    }
}

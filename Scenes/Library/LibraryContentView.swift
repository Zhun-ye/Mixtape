//
//  LibraryContentView.swift
//  Mixtape
//
//  Content view for Library (Playlists) tab, used with LibraryCoordinator.
//

import SwiftUI

struct LibraryContentView: View {
    @Bindable var viewModel: LibraryViewModel

    private let gridColumns = [GridItem(.adaptive(minimum: .adaptiveGridMinimum - 40, maximum: .adaptiveGridMaximum), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                playlistsSection
                albumsSection
                artistsSection
                downloadsSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .loading(viewModel.loadingState) {
            viewModel.refresh()
        }
    #if os(iOS)
        .inlineLargeTitle("Library") {
            Button {
                self.viewModel.didRequestSettings()
            } label: {
                UserProfileView(imageSize: 40)
            }
        }
    #else
        .navigationTitle("Library")
    #endif
        .task {
            viewModel.refresh()
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    @ViewBuilder
    private var downloadsSection: some View {
        if viewModel.hasDownloads {
            Button {
                viewModel.didSelectDownloads()
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Downloads")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    downloadsThumbnailRow

                    HStack(spacing: 4) {
                        Text("\(viewModel.downloadCount) songs")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Text(viewModel.downloadSizeDisplay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if viewModel.activeDownloadCount > 0 {
                            Text("·")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text("\(viewModel.activeDownloadCount) downloading")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var downloadsThumbnailRow: some View {
        let thumbnails = viewModel.recentDownloadThumbnails
        if !thumbnails.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, url in
                    RemoteImage(url: url) {
                        Rectangle().fill(.quaternary)
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var playlistsSection: some View {
        sectionHeader("Playlists")
        if viewModel.playlists.isEmpty {
            emptyStateView(icon: "music.note.list", title: "No playlists yet", message: "Create playlists on \(ytmDisplayName) to see them here.")
        } else {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(viewModel.playlists) { playlist in
                    Button {
                        viewModel.didSelectPlaylist(playlist)
                    } label: {
                        PlaylistCard(playlist: playlist)
                    }
                    .buttonStyle(.interactiveCard)
                    .hoverPlay {
                        Task { await viewModel.playPlaylist(playlist) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var albumsSection: some View {
        sectionHeader("Albums")
        if viewModel.albums.isEmpty {
            emptyStateView(icon: "square.stack", title: "No albums yet", message: "Save albums on \(ytmDisplayName) to see them here.")
        } else {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(viewModel.albums) { album in
                    Button {
                        let playlist = Playlist(
                            id: album.id,
                            title: album.title,
                            description: nil,
                            thumbnailURL: album.thumbnailURL,
                            trackCount: album.trackCount,
                            author: album.artistsDisplay
                        )
                        viewModel.didSelectPlaylist(playlist)
                    } label: {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.interactiveCard)
                    .hoverPlay {
                        Task { await viewModel.playAlbum(album) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var artistsSection: some View {
        sectionHeader("Artists")
        if viewModel.artists.isEmpty {
            emptyStateView(icon: "person.2", title: "No artists yet", message: "Subscribe to artists on \(ytmDisplayName) to see them here.")
        } else {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(viewModel.artists) { artist in
                    Button {
                        viewModel.didSelectArtist(artist)
                    } label: {
                        ArtistCard(artist: artist)
                    }
                    .buttonStyle(.interactiveCard)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

}

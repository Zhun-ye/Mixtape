//
//  LibraryAlbumsView.swift
//  Mixtape
//
//  Displays the user's library albums in a grid.
//

import SwiftUI

struct LibraryAlbumsView: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        Group {
            if viewModel.albums.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: .adaptiveGridMinimum, maximum: .adaptiveGridMaximum), spacing: .sectionItemSpacing),
                    ], spacing: .sectionItemSpacing) {
                        ForEach(viewModel.albums) { album in
                            albumCard(album)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .scrollClipDisabled()
                }
            }
        }
        .loading(viewModel.loadingState, message: "Loading albums...") {
            viewModel.refresh()
        }
        .navigationTitle("Albums")
        .refreshable {
            viewModel.refresh()
        }
    }

    @ViewBuilder
    private func albumCard(_ album: Album) -> some View {
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
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No albums yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Save albums on \(ytmDisplayName) to see them here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

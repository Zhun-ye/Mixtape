//
//  SearchContentView.swift
//  Mixtape
//
//  Content view for Search tab, used with SearchCoordinator.
//

import SwiftUI

struct SearchContentView: View {
    @Bindable var viewModel: SearchViewModel
    @Binding var focusTrigger: Bool

    @FocusState private var isSearchFocused: Bool

    // MARK: - Layout Constants

    private enum Layout {
        static let horizontalPadding: CGFloat = 24
        static let thumbnailSize: CGFloat = 48
        static let cornerRadius: CGFloat = 6
        static let dividerLeading: CGFloat = 72
    }

    var body: some View {
        ScrollView {
            self.contentView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            switch self.viewModel.loadingState {
            case .idle:
                ContentUnavailableView(
                    "Search for your favorite music",
                    systemImage: "magnifyingglass",
                    description: Text("Find songs, albums, artists, and playlists")
                )
            case .loading, .loadingMore:
                ProgressView("Searching")
            case .loaded where self.viewModel.filteredItems.isEmpty:
                ContentUnavailableView.search(text: self.viewModel.query)
            default:
                EmptyView()
            }
        }
        .animation(.none, value: self.viewModel.loadingState)
        .contentTransition(.identity)
        .safeAreaBar(edge: .top) {
            if !self.viewModel.results.isEmpty {
                self.filterChips()
                    .padding(.horizontal, Layout.horizontalPadding)
                    .padding(.vertical, 10)
            }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.immediately)
        .searchable(text: self.$viewModel.query, placement: .navigationBarDrawer, prompt: "Songs, albums, artists...")
        .inlineLargeTitle("Search") {
            Button {
                self.viewModel.didRequestSettings()
            } label: {
                UserProfileView(imageSize: 40)
            }
        }
        #else
        .searchable(text: self.$viewModel.query, placement: .toolbarPrincipal, prompt: "Songs, albums, artists...")
        #endif
        .searchFocused(self.$isSearchFocused)
        .searchSuggestions {
            if self.viewModel.showSuggestions {
                ForEach(self.viewModel.suggestions.prefix(7)) { suggestion in
                    Label(suggestion.query, systemImage: "magnifyingglass")
                        .searchCompletion(suggestion.query)
                }
            }
        }
        .onSubmit(of: .search) {
            self.viewModel.search()
        }
        .onChange(of: self.viewModel.query) { _, _ in
            self.viewModel.fetchSuggestions()
        }
        .onChange(of: self.focusTrigger) { _, newValue in
            if newValue {
                self.isSearchFocused = true
                self.focusTrigger = false
            }
        }
        .onAppear {
            self.isSearchFocused = true
        }
    }

    // MARK: - Filter Chips

    @ViewBuilder
    private func filterChips() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchViewModel.SearchFilter.allCases) { filter in
                    self.filterChip(filter)
                }
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func filterChip(_ filter: SearchViewModel.SearchFilter) -> some View {
        Button {
            self.viewModel.selectedFilter = filter
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(self.viewModel.selectedFilter == filter ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundStyle(self.viewModel.selectedFilter == filter ? .white : .primary)
                .clipShape(.capsule)
        }
        .buttonStyle(.chip(isSelected: self.viewModel.selectedFilter == filter))
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView() -> some View {
        switch self.viewModel.loadingState {
        case .loaded:
            self.resultsView()
        case let .error(error):
            ErrorView(title: error.title, message: error.message) {
                self.viewModel.search()
            }
            .padding(.top, 40)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func resultsView() -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(self.viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                self.resultRow(item, index: index)
                Divider()
                    .padding(.leading, Layout.dividerLeading)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func resultRow(_ item: SearchResultItem, index: Int) -> some View {
        Button {
            self.handleItemTap(item)
        } label: {
            self.resultRowContent(item)
        }
        .buttonStyle(.interactiveRow(cornerRadius: Layout.cornerRadius))
        .contextMenu {
            self.contextMenuItems(for: item)
        }
    }

    private func handleItemTap(_ item: SearchResultItem) {
        switch item {
        case let .song(song):
            Task { await viewModel.playerManager.playWithRadio(song: song) }
        case let .artist(artist):
            viewModel.didSelectArtist(artist)
        case let .album(album):
            viewModel.didSelectAlbum(album)
        case let .playlist(playlist):
            viewModel.didSelectPlaylist(playlist)
        }
    }

    @ViewBuilder
    private func resultRowContent(_ item: SearchResultItem) -> some View {
        HStack(spacing: 14) {
            RemoteImage(url: item.thumbnailURL?.cardThumbnailURL) {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: self.iconForItem(item))
                            .foregroundStyle(.secondary)
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: Layout.thumbnailSize, height: Layout.thumbnailSize)
            .clipShape(.rect(cornerRadius: self.thumbnailCornerRadius(for: item)))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)

                Text(self.subtitleText(for: item))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func thumbnailCornerRadius(for item: SearchResultItem) -> CGFloat {
        switch item {
        case .artist:
            Layout.thumbnailSize / 2
        case .song, .album, .playlist:
            Layout.cornerRadius
        }
    }

    private func subtitleText(for item: SearchResultItem) -> String {
        if let subtitle = item.subtitle {
            "\(item.resultType) · \(subtitle)"
        } else {
            item.resultType
        }
    }

    @ViewBuilder
    private func contextMenuItems(for item: SearchResultItem) -> some View {
        switch item {
        case let .song(song):
            self.songContextMenu(for: song)
        case let .playlist(playlist):
            self.playlistContextMenu(for: playlist)
        case .album, .artist:
            EmptyView()
        }
    }

    @ViewBuilder
    private func songContextMenu(for song: Song) -> some View {
        Button {
            Task { await viewModel.playerManager.play(song: song) }
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
    }

    @ViewBuilder
    private func playlistContextMenu(for playlist: Playlist) -> some View {
        Button {
            Task { try? await viewModel.libraryRepository.addToLibrary(playlist) }
        } label: {
            Label("Add to Library", systemImage: "plus.circle")
        }
    }

    // MARK: - Helpers

    private func iconForItem(_ item: SearchResultItem) -> String {
        switch item {
        case .song: "music.note"
        case .album: "square.stack"
        case .artist: "person"
        case .playlist: "music.note.list"
        }
    }
}

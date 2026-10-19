import SwiftUI
import FactoryKit

/// Detail view for an artist showing their songs and albums.
struct ArtistDetailView: View {
    @Bindable var viewModel: ArtistDetailViewModel

    private var artist: Artist { viewModel.artist }

    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        Group {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                LoadingView("Loading artist...")
            case .loaded, .loadingMore:
                if let detail = viewModel.artistDetail {
                    self.contentView(detail)
                } else {
                    ErrorView(title: "Unable to load artist", message: "Artist not found") {
                        Task { await self.viewModel.load() }
                    }
                }
            case let .error(error):
                ErrorView(title: error.title, message: error.message) {
                    Task { await self.viewModel.load() }
                }
            }
        }
#if os(macOS)
        .navigationTitle(self.artist.name)
#else
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let detail = viewModel.artistDetail, detail.channelId != nil {
                    subscribeToolbarButton(detail)
                }
            }
        }
#endif
    }

    // MARK: - Views

    private func contentView(_ detail: ArtistDetail) -> some View {
        #if os(macOS)
        macOSContentView(detail)
        #else
        iOSContentView(detail)
        #endif
    }

    #if os(macOS)
    private func macOSContentView(_ detail: ArtistDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                self.headerView(detail)

                Divider()

                if !detail.songs.isEmpty {
                    self.songsSection()
                }

                ForEach(self.viewModel.displayedAlbumSections) { section in
                    self.albumSection(section)
                }

                if !detail.playlists.isEmpty {
                    self.playlistsSection(detail.playlists)
                }
            }
            .padding(24)
        }
    }
    #endif

    #if !os(macOS)
    private func iOSContentView(_ detail: ArtistDetail) -> some View {
        GeometryReader { geometry in
            let heroHeight: CGFloat = 320
            let safeTop = geometry.safeAreaInsets.top

            ZStack(alignment: .top) {
                // Hero image (behind ScrollView)
                heroImageSection(detail: detail, width: geometry.size.width, heroHeight: heroHeight, safeTop: safeTop)

                // ScrollView with content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Spacer for hero, minus space for metadata overlay
                        Color.clear
                            .frame(height: heroHeight - 140)

                        // Metadata and buttons (part of scroll content, appears over hero)
                        VStack(spacing: 16) {
                            VStack(spacing: 6) {
                                Text(detail.name)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                                if let subscriberCount = detail.subscriberCount {
                                    Text(subscriberCount)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }

                            HStack(spacing: 12) {
                                Button {
                                    self.shuffleAll(detail.songs)
                                } label: {
                                    Label("Shuffle", systemImage: "shuffle")
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                                .disabled(detail.songs.isEmpty)

                                Button {
                                    self.playAll(detail.songs)
                                } label: {
                                    Label("Mix", systemImage: "play.circle")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(detail.songs.isEmpty)
                            }
                        }
                        .frame(height: 140)

                        // Main content
                        VStack(alignment: .leading, spacing: 24) {
                            // Songs section
                            if !detail.songs.isEmpty {
                                self.songsSection()
                            }

                            // Album sections (Albums, Singles & EPs, etc.)
                            ForEach(self.viewModel.displayedAlbumSections) { section in
                                self.albumSection(section)
                            }

                            // Playlists section
                            if !detail.playlists.isEmpty {
                                self.playlistsSection(detail.playlists)
                            }

                            // Description section
                            if let description = detail.description, !description.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("About")
                                        .font(.title2)
                                        .fontWeight(.semibold)

                                    Text(description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = newValue
                }
            }
        }
    }

    /// Hero image with stretchy effect and parallax
    @ViewBuilder
    private func heroImageSection(detail: ArtistDetail, width: CGFloat, heroHeight: CGFloat, safeTop: CGFloat) -> some View {
        let baseHeight = heroHeight + safeTop
        let stretchAmount = max(0, -scrollOffset)
        let frameHeight = baseHeight + stretchAmount
        // Parallax: image moves up at 0.6x speed
        let parallaxOffset = min(scrollOffset * 0.6, baseHeight)
        // Fade out after scrolling 70% - stays at 1.0 until 70%, then fades to 0
        let fadeStartPoint = heroHeight * 0.7
        let fadeRange = heroHeight - fadeStartPoint
        let opacity: CGFloat = scrollOffset < fadeStartPoint ? 1.0 : max(0, 1.0 - ((scrollOffset - fadeStartPoint) / fadeRange))

        ZStack(alignment: .bottom) {
            // Background image with parallax offset
            RemoteImage(url: detail.thumbnailURL?.heroThumbnailURL, placeholder: {
                Rectangle()
                    .fill(.quaternary)
            })
            .aspectRatio(contentMode: .fill)
            .offset(y: scrollOffset > 0 ? -parallaxOffset : 0)
            .opacity(opacity)

            // Gradient for text readability
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .opacity(opacity)
        }
        .frame(width: width, height: frameHeight)
        .clipped()
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
    #endif

    #if !os(macOS)
    @ViewBuilder
    private func subscribeToolbarButton(_ detail: ArtistDetail) -> some View {
        Button {
            Task {
                await self.viewModel.toggleSubscription()
            }
        } label: {
            if self.viewModel.isSubscribing {
                ProgressView()
                    .controlSize(.small)
            } else if detail.isSubscribed {
                Image(systemName: "star.fill")
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "star")
                    .foregroundStyle(.white)
            }
        }
        .disabled(self.viewModel.isSubscribing)
    }
    #endif

    #if os(macOS)
    private func headerView(_ detail: ArtistDetail) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Thumbnail
            RemoteImage(url: detail.thumbnailURL?.cardThumbnailURL) {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 180, height: 180)
            .clipShape(.circle)

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Text(detail.name)
                    .font(.title)
                    .fontWeight(.bold)

                // Subscriber count
                if let subscriberCount = detail.subscriberCount {
                    Text(subscriberCount)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let description = detail.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer()

                HStack(spacing: 12) {
                    // Shuffle button
                    Button {
                        self.shuffleAll(detail.songs)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(detail.songs.isEmpty)

                    // Play all button (Mix)
                    Button {
                        self.playAll(detail.songs)
                    } label: {
                        Label("Mix", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(detail.songs.isEmpty)

                    // Subscribe button
                    if detail.channelId != nil {
                        self.subscribeButton(detail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #endif


    /// Returns the text for the subscribe button.
    private func subscribeButtonText(_ detail: ArtistDetail) -> String {
        if detail.isSubscribed {
            return "Subscribed"
        }
        // Format subscriber count (e.g., "Subscribe 34.6M")
        if let count = detail.subscriberCount {
            // Extract just the number part if it contains "subscribers"
            let numberPart = count
                .replacingOccurrences(of: " subscribers", with: "")
                .replacingOccurrences(of: " subscriber", with: "")
            return "Subscribe \(numberPart)"
        }
        return "Subscribe"
    }

    @ViewBuilder
    private func subscribeButton(_ detail: ArtistDetail) -> some View {
        if detail.isSubscribed {
            Button {
                Task {
                    await self.viewModel.toggleSubscription()
                }
            } label: {
                if self.viewModel.isSubscribing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Text(self.subscribeButtonText(detail))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(self.viewModel.isSubscribing)
        } else {
            Button {
                Task {
                    await self.viewModel.toggleSubscription()
                }
            } label: {
                if self.viewModel.isSubscribing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Text(self.subscribeButtonText(detail))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(self.viewModel.isSubscribing)
        }
    }

    private func songsSection() -> some View {
        let songsPerPage = 4
        let songs = self.viewModel.displayedSongs
        let pageCount = (songs.count + songsPerPage - 1) / songsPerPage

        return VStack(alignment: .leading, spacing: 12) {
            // Header matching SectionGroup style
            if self.viewModel.hasMoreSongs {
                Button {
                    self.viewModel.showTopSongs()
                } label: {
                    HStack {
                        Text("Top songs")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Top songs")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            // Paged horizontal scroll with 4 songs per page, showing peek of next page
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(0..<pageCount, id: \.self) { pageIndex in
                        let startIndex = pageIndex * songsPerPage
                        let endIndex = min(startIndex + songsPerPage, songs.count)
                        let pageSongs = Array(songs[startIndex..<endIndex])

                        self.songPageView(pageSongs, startIndex: startIndex)
                            #if os(macOS)
                            .frame(width: 400)
                            #else
                            .containerRelativeFrame(.horizontal) { width, _ in
                                width - 40 // Leave space for peek
                            }
                            #endif
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    /// A single page of songs (up to 4 songs per page).
    private func songPageView(_ songs: [Song], startIndex: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                self.topSongRow(song, index: startIndex + index)

                if index < songs.count - 1 {
                    Divider()
                        .padding(.leading, 60)
                }
            }
        }
    }

    /// Song row for top songs section - fetches all songs and plays as queue.
    private func topSongRow(_ song: Song, index: Int) -> some View {
        let isCurrentTrack = viewModel.playerManager.currentTrack?.videoId == song.videoId
        let isPlaying = viewModel.playerManager.isPlaying

        return TopSongRowView(
            song: song,
            isCurrentTrack: isCurrentTrack,
            isPlaying: isPlaying
        ) {
            // Fetch all songs and play as queue starting from the selected song
            Task {
                let allSongs = await self.viewModel.getAllSongs()
                // Find the index of the selected song in the full list
                let startIndex = allSongs.firstIndex(where: { $0.videoId == song.videoId }) ?? index
                await viewModel.playerManager.playQueue(allSongs, startingAt: startIndex)
            }
        }
        .contextMenu {
            Button {
                Task {
                    let allSongs = await self.viewModel.getAllSongs()
                    let startIndex = allSongs.firstIndex(where: { $0.videoId == song.videoId }) ?? index
                    await viewModel.playerManager.playQueue(allSongs, startingAt: startIndex)
                }
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

    @ViewBuilder
    private func albumSection(_ section: AlbumSection) -> some View {
        let albums = self.viewModel.albumsToDisplay(for: section)
        let hasMore = self.viewModel.hasMoreAlbums(in: section)

        VStack(alignment: .leading, spacing: 12) {
            // Header matching SectionGroup style
            if hasMore {
                Button {
                    self.viewModel.showAllAlbums(in: section)
                } label: {
                    HStack {
                        Text(section.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(section.title)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: .sectionItemSpacing) {
                    ForEach(albums) { album in
                        Button {
                            self.viewModel.didSelectAlbum(album)
                        } label: {
                            AlbumCard(album: album)
                                .frame(width: 140)
                        }
                        .buttonStyle(.interactiveCard)
                        .hoverPlay {
                            Task {
                                await self.viewModel.playAlbum(album)
                            }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func playlistFromAlbum(_ album: Album) -> Playlist {
        Playlist(
            id: album.id,
            title: album.title,
            description: nil,
            thumbnailURL: album.thumbnailURL,
            trackCount: album.trackCount,
            author: album.artistsDisplay
        )
    }

    @ViewBuilder
    private func playlistsSection(_ playlists: [Playlist]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playlists")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: .sectionItemSpacing) {
                    ForEach(playlists) { playlist in
                        Button {
                            self.viewModel.didSelectPlaylist(playlist)
                        } label: {
                            PlaylistCard(playlist: playlist)
                                .frame(width: 140)
                        }
                        .buttonStyle(.interactiveCard)
                        .hoverPlay {
                            Task {
                                await self.viewModel.playPlaylist(playlist)
                            }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Actions

    private func playAll(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        Task {
            await viewModel.playerManager.playQueue(songs, startingAt: 0)
        }
    }

    private func shuffleAll(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        Task {
            let shuffledSongs = songs.shuffled()
            await viewModel.playerManager.playQueue(shuffledSongs, startingAt: 0)
        }
    }
}

import SwiftUI

// MARK: - PlaylistDetailView

/// Detail view for a playlist showing its tracks.
struct PlaylistDetailView: View {
    @Bindable var viewModel: PlaylistDetailViewModel

    /// Selected tracks for context menu.
    @State private var selection = Set<Song>()

    /// Whether the full description sheet is shown.
    @State private var showDescriptionSheet = false

    /// Whether the remove downloads confirmation is shown.
    @State private var showRemoveDownloadsConfirmation = false

    #if os(iOS)
    @Environment(PlayerBarAppearance.self) private var playerBarAppearance
    #endif

    var body: some View {
        Group {
            switch viewModel.loadingState {
            case .idle, .loading:
                LoadingView("Loading playlist...")
            case .loaded, .loadingMore:
                if let detail = viewModel.playlistDetail {
                    contentView(detail)
                } else {
                    ErrorView(title: "Unable to load playlist", message: "Playlist not found") {
                        Task { await viewModel.load() }
                    }
                }
            case let .error(error):
                ErrorView(title: error.title, message: error.message) {
                    Task { await viewModel.load() }
                }
            }
        }
        .sheet(isPresented: $showDescriptionSheet) {
            if let detail = viewModel.playlistDetail,
               let description = detail.description {
                PlaylistDescriptionSheet(
                    title: detail.title,
                    author: detail.author,
                    description: description
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $viewModel.showRefineSheet) {
            if let detail = viewModel.playlistDetail {
                RefinePlaylistSheet(
                    tracks: detail.tracks,
                    isProcessing: $viewModel.isRefining,
                    changes: $viewModel.playlistChanges,
                    errorMessage: $viewModel.refineError,
                    onRefine: { prompt in
                        await viewModel.refinePlaylist(prompt: prompt)
                    },
                    onApply: {
                        viewModel.applyRefineChanges()
                    },
                    onClear: {
                        viewModel.clearRefineState()
                    }
                )
            }
        }
    }

    // MARK: - Views

    private func contentView(_ detail: PlaylistDetail) -> some View {
        List(selection: $selection) {
            Section {
                headerView(detail)
                    .listRowInsets(EdgeInsets(top: 24, leading: 24, bottom: 16, trailing: 24))
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(Array(detail.tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, index: index, isAlbum: detail.isAlbum)
                        .tag(track)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .contextMenu(forSelectionType: Song.self, menu: { selectedTracks in
            if let track = selectedTracks.first {
                Button {
                    viewModel.playOrToggle(track)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Divider()

                Button {
                    viewModel.likeSong(track)
                } label: {
                    Label("Like", systemImage: "hand.thumbsup")
                }

                Button {
                    viewModel.dislikeSong(track)
                } label: {
                    Label("Dislike", systemImage: "hand.thumbsdown")
                }

                Divider()

                Button {
                    viewModel.addSongToLibrary(track)
                } label: {
                    Label("Add to Library", systemImage: "plus.circle")
                }

                Divider()

                Divider()

                DownloadContextMenuItems(song: track)

                Divider()

                if let artist = track.artists.first(where: { !$0.id.isEmpty && $0.id != UUID().uuidString }) {
                    NavigationLink(value: artist) {
                        Label("Go to Artist", systemImage: "person")
                    }
                }

                if let album = track.album, album.hasNavigableId {
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
        }, primaryAction: { selectedTracks in
            if let track = selectedTracks.first {
                viewModel.playOrToggle(track)
            }
        })
        .refreshable {
            viewModel.refresh()
        }
        #if !os(macOS)
        .scrollContentBackground(.hidden)
        .background {
            LinearGradient(
                colors: [viewModel.colorPalette.primary, viewModel.colorPalette.secondary],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, viewModel.colorPalette.preferredColorScheme)
        .onAppear {
            viewModel.extractArtworkPalette()
            #if os(iOS)
            playerBarAppearance.colorSchemeOverride = viewModel.colorPalette.preferredColorScheme
            #endif
        }
        .onChange(of: viewModel.colorPalette) { _, newPalette in
            #if os(iOS)
            playerBarAppearance.colorSchemeOverride = newPalette.preferredColorScheme
            #endif
        }
        .onDisappear {
            #if os(iOS)
            playerBarAppearance.colorSchemeOverride = nil
            #endif
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let shareURL = viewModel.shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        #endif
    }

    private func headerView(_ detail: PlaylistDetail) -> some View {
        #if os(macOS)
        macOSHeader(detail)
        #else
        iOSHeader(detail)
        #endif
    }

    #if os(macOS)
    private func macOSHeader(_ detail: PlaylistDetail) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            RemoteImage(url: detail.thumbnailURL?.cardThumbnailURL, placeholder: {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
            })
            .aspectRatio(contentMode: .fill)
            .frame(width: 240, height: 240)
            .clipShape(.rect(cornerRadius: 8))
            .shadow(radius: 3)
            .fadeIn(duration: 0.3)

            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 30)

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.title)
                        .font(.title)
                        .fontWeight(.bold)

                    if let author = detail.author {
                        Text(author)
                            .font(.title2)
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 4) {
                        Text(detail.isAlbum ? "Album" : "Playlist")
                        if let duration = detail.duration {
                            Text("·")
                            Text(duration)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        viewModel.playAll()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(detail.tracks.isEmpty)

                    Button {
                        viewModel.shuffleAll()
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(detail.tracks.isEmpty)

                    Button {
                        viewModel.toggleLibrary()
                    } label: {
                        Label(
                            viewModel.isCurrentlyInLibrary ? "Added" : "Add",
                            systemImage: viewModel.isCurrentlyInLibrary ? "checkmark.circle.fill" : "plus.circle"
                        )
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if !detail.isAlbum {
                        Button {
                            viewModel.showRefineSheet = true
                        } label: {
                            Image(systemName: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .requiresIntelligence()
                    }
                }
                .frame(width: 400, height: 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 240)
    }
    #endif

    #if !os(macOS)
    private func iOSHeader(_ detail: PlaylistDetail) -> some View {
        VStack(spacing: 16) {
            RemoteImage(url: detail.thumbnailURL?.cardThumbnailURL, placeholder: {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
            })
            .aspectRatio(contentMode: .fill)
            .frame(width: 280, height: 280)
            .clipShape(.rect(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .fadeIn(duration: 0.3)

            VStack(spacing: 4) {
                Text(detail.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)

                if let author = detail.author {
                    Text(author)
                        .font(.subheadline)
                }

                HStack(spacing: 4) {
                    Text("\(detail.tracks.count) songs")
                    if let duration = detail.duration {
                        Text("·")
                        Text(duration)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                // Shuffle
                Button {
                    viewModel.shuffleAll()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .background(.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(detail.tracks.isEmpty)

                // Play
                Button {
                    viewModel.playAll()
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(viewModel.colorPalette.isLight ? .white : .black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(detail.tracks.isEmpty)

                // Add to Library / Download / Downloaded
                Button {
                    if viewModel.allTracksDownloaded {
                        showRemoveDownloadsConfirmation = true
                    } else if viewModel.isDownloadingTracks {
                        viewModel.cancelDownloads()
                    } else if viewModel.isCurrentlyInLibrary {
                        Task { await viewModel.downloadAll() }
                    } else {
                        viewModel.toggleLibrary()
                    }
                } label: {
                    Group {
                        if viewModel.allTracksDownloaded {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                        } else if viewModel.isDownloadingTracks {
                            ZStack {
                                Circle()
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 2.5)
                                Circle()
                                    .trim(from: 0, to: viewModel.downloadProgress)
                                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 13))
                            }
                        } else if viewModel.isCurrentlyInLibrary {
                            Image(systemName: "arrow.down")
                                .foregroundStyle(.primary)
                        } else {
                            Image(systemName: "plus")
                                .foregroundStyle(.primary)
                        }
                    }
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(detail.tracks.isEmpty)
                .confirmationDialog("Remove Downloads", isPresented: $showRemoveDownloadsConfirmation) {
                    Button("Remove Downloads", role: .destructive) {
                        viewModel.removeDownloads()
                    }
                    Button("Remove from Library", role: .destructive) {
                        viewModel.removeFromLibraryAndDownloads()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Downloaded files will be removed from this device.")
                }
            }

            if let description = detail.description, !description.isEmpty {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Button {
                        showDescriptionSheet = true
                    } label: {
                        Text("MORE")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }
    #endif

    private func trackRow(_ track: Song, index: Int, isAlbum: Bool) -> some View {
        TrackRowView(
            track: track,
            index: index,
            isAlbum: isAlbum,
            isCurrentTrack: viewModel.isCurrentTrack(track),
            isPlaying: viewModel.isPlaying
        )
    }
}

// MARK: - RefinePlaylistSheet

private struct RefinePlaylistSheet: View {
    let tracks: [Song]
    @Binding var isProcessing: Bool
    @Binding var changes: PlaylistChanges?
    @Binding var errorMessage: String?
    let onRefine: (String) async -> Void
    let onApply: () -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var promptText = ""
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Refine Playlist")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if isProcessing {
                loadingView
            } else if let changes {
                changesView(changes)
            } else {
                promptView
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 400)
        #endif
        .onAppear {
            isPromptFocused = true
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .frame(width: 20, height: 20)
            Text("Analyzing playlist...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What would you like to change?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("e.g., Remove slow songs, reorder by energy...", text: $promptText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3 ... 5)
                .focused($isPromptFocused)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                suggestionChip("Remove duplicates")
                suggestionChip("Make it more upbeat")
                suggestionChip("Better flow")
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Refine") {
                    Task {
                        await onRefine(promptText)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(promptText.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
    }

    private func changesView(_ changes: PlaylistChanges) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(changes.reasoning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !changes.removals.isEmpty {
                        Text("Suggested Removals")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)

                        ForEach(changes.removals, id: \.self) { videoId in
                            if let track = tracks.first(where: { $0.videoId == videoId }) {
                                HStack {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                    Text(track.title)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(track.artistsDisplay)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if changes.removals.isEmpty, changes.reorderedIds == nil {
                        Text("No changes suggested. The playlist looks good!")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .scrollClipDisabled()
            }

            Divider()

            HStack {
                Button("Try Again") {
                    onClear()
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Apply Changes") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .disabled(changes.removals.isEmpty && changes.reorderedIds == nil)
            }
            .padding()
        }
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            promptText = text
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PlaylistDescriptionSheet

private struct PlaylistDescriptionSheet: View {
    let title: String
    let author: String?
    let description: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Text(description)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - TrackRowView

private struct TrackRowView: View {
    let track: Song
    let index: Int
    let isAlbum: Bool
    let isCurrentTrack: Bool
    let isPlaying: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            if isAlbum {
                // Album: show index number, or equalizer when playing
                ZStack {
                    if isCurrentTrack && isPlaying {
                        EqualizerView(
                            isAnimating: true,
                            barCount: 3,
                            spacing: 2,
                            barWidth: 3,
                            cornerRadius: 1.5,
                            color: .primary
                        )
                        .frame(width: 14, height: 14)
                    } else {
                        Text("\(index + 1)")
                            .foregroundStyle(isCurrentTrack ? .primary : .secondary)
                    }
                }
                .frame(width: 20, height: 20)
            } else {
                RemoteImage(url: track.thumbnailURL, placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                })
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 4))
                .overlay {
                    if isCurrentTrack && isPlaying {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.black.opacity(0.4))
                        EqualizerView(
                            isAnimating: true,
                            barCount: 3,
                            spacing: 2,
                            barWidth: 3,
                            cornerRadius: 1.5,
                            color: .white
                        )
                        .frame(width: 14, height: 14)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !track.artistsDisplay.isEmpty {
                    Text(track.artistsDisplay)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.durationDisplay)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

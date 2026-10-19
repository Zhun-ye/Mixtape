import SwiftUI

/// Displays downloaded playlists, songs, and active download progress.
struct DownloadsView: View {
    @Bindable var viewModel: DownloadsViewModel
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                downloadsList
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !viewModel.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteAllConfirmation = true
                        } label: {
                            Label("Delete All Downloads", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .alert("Delete All Downloads?", isPresented: $showDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) {
                viewModel.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded songs, playlists, and cancel any active downloads. This action cannot be undone.")
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Downloads")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Downloaded songs will appear here for offline playback.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Downloads List

    @ViewBuilder
    private var downloadsList: some View {
        List {
            if viewModel.hasActiveTasks {
                activeDownloadsSection
            }

            if !viewModel.playlists.isEmpty {
                playlistsSection
            }

            if !viewModel.looseSongs.isEmpty {
                looseSongsSection
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Active Downloads

    @ViewBuilder
    private var activeDownloadsSection: some View {
        Section {
            ForEach(viewModel.activeTasks) { task in
                activeDownloadRow(task)
            }
        } header: {
            Text("Downloading")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private func activeDownloadRow(_ task: DownloadTaskInfo) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: task.song.thumbnailURL, placeholder: {
                Rectangle()
                    .fill(.quaternary)
            })
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(task.song.title)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(task.song.artistsDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if task.state == .failed, let error = task.error {
                        Text("· \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            downloadStateIndicator(task)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.cancelDownload(task)
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
        }
    }

    @ViewBuilder
    private func downloadStateIndicator(_ task: DownloadTaskInfo) -> some View {
        switch task.state {
        case .pending, .fetchingURL:
            Button {
                viewModel.cancelDownload(task)
            } label: {
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                    // Invisible tap target
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
        case .downloading:
            Button {
                viewModel.cancelDownload(task)
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: task.progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        case .failed:
            Button {
                viewModel.retryDownload(task)
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        case .paused:
            Image(systemName: "pause.circle")
                .foregroundStyle(.secondary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Playlists Section

    @ViewBuilder
    private var playlistsSection: some View {
        Section {
            ForEach(viewModel.playlists) { playlist in
                playlistRow(playlist)
            }
        } header: {
            Text("Playlists & Albums")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: DownloadedPlaylist) -> some View {
        Button {
            viewModel.selectPlaylist(playlist)
        } label: {
            HStack(spacing: 12) {
                RemoteImage(url: playlist.thumbnailURL, placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                })
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if let author = playlist.author {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        let progress = viewModel.playlistProgress(playlist)
                        if progress.downloaded == progress.total {
                            Text("\(progress.total) songs · \(viewModel.playlistSize(playlist))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(progress.downloaded)/\(progress.total) songs")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.deletePlaylist(playlist)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                viewModel.playPlaylist(playlist)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                viewModel.shufflePlaylist(playlist)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }

            Divider()

            Button(role: .destructive) {
                viewModel.deletePlaylist(playlist)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }

    // MARK: - Loose Songs

    @ViewBuilder
    private var looseSongsSection: some View {
        Section {
            ForEach(viewModel.looseSongs) { download in
                completedDownloadRow(download)
            }
        } header: {
            HStack {
                Text("Songs · \(viewModel.totalSizeDisplay)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(nil)

                Spacer()

                if viewModel.looseSongs.count > 1 {
                    Menu {
                        Button {
                            viewModel.playAll()
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                        }

                        Button {
                            viewModel.shuffleAll()
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func completedDownloadRow(_ download: DownloadedSong) -> some View {
        Button {
            viewModel.play(download.song)
        } label: {
            HStack(spacing: 12) {
                RemoteImage(url: download.song.thumbnailURL, placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                })
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(download.song.title)
                        .lineLimit(1)

                    Text(download.song.artistsDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: download.fileSize, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                viewModel.deleteDownload(download)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                viewModel.play(download.song)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Divider()

            Button(role: .destructive) {
                viewModel.deleteDownload(download)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }
}

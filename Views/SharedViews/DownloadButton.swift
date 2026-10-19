import FactoryKit
import SwiftUI

/// Reusable button that displays download state for a song.
/// Shows appropriate icon and interaction for each state:
/// - Not downloaded: download arrow
/// - Pending/fetching: spinner
/// - Downloading: circular progress ring
/// - Completed: checkmark
/// - Failed: error icon (tap to retry)
struct DownloadButton: View {
    let song: Song
    let style: Style
    @Injected(\.downloadManager) private var downloadManager

    enum Style {
        case icon       // Compact icon-only (for track rows, context menus)
        case circular   // Circle background (for playlist headers)
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            content
        }
        .buttonStyle(.plain)
        .disabled(state == .downloading || state == .fetchingURL)
    }

    // MARK: - State

    private var state: DownloadTaskInfo.DownloadState? {
        downloadManager.downloadState(for: song.videoId)
    }

    private var progress: Double {
        downloadManager.progress(for: song.videoId)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch style {
        case .icon:
            iconContent
        case .circular:
            circularContent
        }
    }

    @ViewBuilder
    private var iconContent: some View {
        switch state {
        case .none:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .pending, .fetchingURL:
            ProgressView()
                .controlSize(.small)
        case .downloading:
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .paused:
            Image(systemName: "pause.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var circularContent: some View {
        Group {
            switch state {
            case .none:
                Image(systemName: "arrow.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            case .pending, .fetchingURL:
                ProgressView()
                    .controlSize(.small)
            case .downloading:
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100))")
                        .font(.system(size: 10, weight: .medium))
                }
            case .completed:
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
            case .paused:
                Image(systemName: "pause")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
        .background(.primary.opacity(0.1), in: Circle())
    }

    // MARK: - Actions

    private func handleTap() {
        switch state {
        case .none:
            Task { await downloadManager.download(song: song) }
        case .failed:
            Task { await downloadManager.retry(videoId: song.videoId) }
        case .completed:
            downloadManager.deleteDownload(videoId: song.videoId)
        default:
            break
        }
    }
}

/// Context menu items for download actions on a song.
struct DownloadContextMenuItems: View {
    let song: Song
    @Injected(\.downloadManager) private var downloadManager

    var body: some View {
        let state = downloadManager.downloadState(for: song.videoId)

        switch state {
        case .none:
            Button {
                Task { await downloadManager.download(song: song) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        case .downloading, .pending, .fetchingURL:
            Button(role: .destructive) {
                downloadManager.cancel(videoId: song.videoId)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        case .completed:
            Button(role: .destructive) {
                downloadManager.deleteDownload(videoId: song.videoId)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        case .failed:
            Button {
                Task { await downloadManager.retry(videoId: song.videoId) }
            } label: {
                Label("Retry Download", systemImage: "arrow.clockwise")
            }
        case .paused:
            Button {
                Task { await downloadManager.retry(videoId: song.videoId) }
            } label: {
                Label("Resume Download", systemImage: "arrow.down.circle")
            }
        }
    }
}

import SwiftUI
import FactoryKit

// MARK: - QueueView

/// Right sidebar panel displaying the playback queue.
struct QueueView: View {
    @Injected(\.playerManager) private var playerManager
    @Environment(\.showCommandBar) private var showCommandBar

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Content
            contentView
        }
        #if os(macOS)
        .frame(minWidth: 280, maxWidth: 280)
        #endif
        .accessibilityIdentifier(AccessibilityID.Queue.container)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Continue playing")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // Clear queue button (only show if there are items beyond the current track)
            if playerManager.queue.count > 1 {
                Button {
                    playerManager.clearQueue()
                } label: {
                    Text("Clear")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.Queue.clearButton)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if playerManager.queue.isEmpty {
            emptyQueueView
        } else {
            queueListView
        }
    }

    private var emptyQueueView: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No Queue")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Play songs from a playlist or album to build your queue.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.Queue.emptyState)
    }

    private var queueListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(playerManager.queue.enumerated()), id: \.element.videoId) { index, song in
                    QueueRowView(
                        song: song,
                        isCurrentTrack: index == playerManager.currentIndex,
                        index: index,
                        onRemove: {
                            playerManager.removeFromQueue(videoIds: [song.videoId])
                        },
                        onTap: {
                            Task {
                                await playerManager.playFromQueue(at: index)
                            }
                        }
                    )
                    .accessibilityIdentifier(AccessibilityID.Queue.row(index: index))
                }
            }
            .padding(.vertical, 8)
            .scrollClipDisabled()
        }
        .accessibilityIdentifier(AccessibilityID.Queue.scrollView)
    }
}

// MARK: - QueueRowView

private struct QueueRowView: View {
    let song: Song
    let isCurrentTrack: Bool
    let index: Int
    let onRemove: () -> Void
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Now Playing indicator or track number
                leadingIndicator
                    .frame(width: 20)

                // Thumbnail
                RemoteImage(url: song.thumbnailURL?.cardThumbnailURL, placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .overlay {
                            Image(.appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .foregroundStyle(.secondary)
                        }
                })
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 13, weight: isCurrentTrack ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(isCurrentTrack ? .red : .primary)

                    Text(song.artistsDisplay.isEmpty ? "Unknown Artist" : song.artistsDisplay)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Duration
                if let duration = song.duration {
                    Text(formatDuration(duration))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            if !isCurrentTrack {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from Queue", systemImage: "minus.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if isCurrentTrack {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            Text("\(index + 1)")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private var backgroundColor: Color {
        if isCurrentTrack {
            return Color.red.opacity(0.1)
        } else if isHovering {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview("Queue View") {
    QueueView()
        .frame(height: 600)
}

#Preview("Queue View with Items") {
    QueueView()
        .frame(height: 600)
}

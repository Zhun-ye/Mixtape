import SwiftUI

/// A reusable song row view for top songs sections.
/// Shows thumbnail with play button on hover, title, and album/year info.
struct TopSongRowView: View {
    let song: Song
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    @State private var isHovering = false

    init(
        song: Song,
        isCurrentTrack: Bool = false,
        isPlaying: Bool = false,
        onPlay: @escaping () -> Void
    ) {
        self.song = song
        self.isCurrentTrack = isCurrentTrack
        self.isPlaying = isPlaying
        self.onPlay = onPlay
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail with play button overlay
            Button(action: onPlay) {
                thumbnailView
            }
            .buttonStyle(.plain)

            // Title and album/single info
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var thumbnailView: some View {
        RemoteImage(url: song.thumbnailURL?.cardThumbnailURL) {
            Rectangle()
                .fill(.quaternary)
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: 48, height: 48)
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            // Playing indicator
            if isCurrentTrack && isPlaying {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black.opacity(0.5))
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
            // Hover play button
            else if isHovering {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black.opacity(0.5))
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    /// Returns subtitle: "Album · Year" or "Single"
    private var subtitle: String {
        if let album = song.album {
            if let year = album.year, !year.isEmpty {
                return "\(album.title) · \(year)"
            }
            return album.title
        } else {
            return "Single"
        }
    }
}

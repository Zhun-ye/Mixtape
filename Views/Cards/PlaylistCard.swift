import SwiftUI

// MARK: - Playlist Extension

extension Playlist {
    var isMoodOrGenreCategory: Bool {
        id.contains("FEmusic_moods_and_genres_category")
    }

    var playlistColor: Color? {
        guard let hex = description, hex.hasPrefix("#") else { return nil }
        return Color(hex: hex)
    }

}

// MARK: - PlaylistCard

/// Card view for displaying a playlist.
struct PlaylistCard: View {
    @Environment(\.cardSize) private var cardSize
    @State private var isHovering = false
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail()
            if !playlist.isMoodOrGenreCategory {
                titleAndSubtitle
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func thumbnail() -> some View {
        Group {
            if playlist.isMoodOrGenreCategory {
                // Mood cards: use aspect ratio to fill grid columns properly
                moodGenreThumbnail
                    .squareFrame(size: cardSize)
            } else {
                // Regular cards: use fixed frame from environment
                RemoteImage(url: playlist.thumbnailURL?.cardThumbnailURL) {
                    placeholderGradient
                }
                .squareFrame(size: cardSize)
            }
        }
        .clipShape(.rect(cornerRadius: 8))
        .modifier(HoverPlayOverlay())
    }

    private var moodGenreThumbnail: some View {
        let baseColor = playlist.playlistColor ?? Self.colorForTitle(playlist.title)
        let hash = abs(playlist.id.hashValue)

        // Vary glow position by hash (4 corners)
        let glowPosition: UnitPoint = switch hash % 4 {
        case 0: .topLeading
        case 1: .topTrailing
        case 2: .bottomTrailing
        default: .bottomLeading
        }

        return baseColor
            .overlay {
                // Bright glow accent
                RadialGradient(
                    colors: [.white.opacity(0.5), .white.opacity(0.15), .clear],
                    center: glowPosition,
                    startRadius: 0,
                    endRadius: 180
                )
            }
            .overlay {
                // Glass material
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .opacity(0.3)
            }
            .aspectRatio(1, contentMode: .fill)
            .overlay(alignment: .bottomLeading) {
                Text(playlist.title)
                #if os(iOS)
                    .font(.title2)
                #else
                    .font(.largeTitle)
                #endif
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .shadow(radius: 0.1)
                    .padding(12)
            }
            .onHover { isHovering = $0 }
    }

    private var placeholderGradient: some View {
        let base = playlist.playlistColor ?? Self.colorForTitle(playlist.title)
        let hash = abs(playlist.id.hashValue)

        // All values derived from hash for consistency
        let spotX = Double(hash % 100) / 100.0
        let spotY = Double((hash / 100) % 30) / 100.0  // 0-0.3 (top area)

        return Rectangle()
            .fill(base)
            .overlay {
                RadialGradient(
                    colors: [.white.opacity(0.25), .clear],
                    center: UnitPoint(x: spotX, y: spotY),
                    startRadius: 10,
                    endRadius: 100
                )
            }
            .overlay {
                // Subtle black mask for text contrast
                LinearGradient(
                    colors: [.clear, .black.opacity(0.15)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    private static func colorForTitle(_ title: String) -> Color {
        let hash = abs(title.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.5)
    }

    private var titleAndSubtitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playlist.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            if let author = playlist.author {
                Text(author)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardSize, alignment: .leading)
    }

}

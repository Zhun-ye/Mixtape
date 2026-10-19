import SwiftUI

// MARK: - AlbumCard

/// Card view for displaying an album.
struct AlbumCard: View {
    @Environment(\.cardSize) private var cardSize
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            titleAndYear
        }
    }

    // MARK: - Components

    private var thumbnail: some View {
        RemoteImage(url: album.thumbnailURL?.cardThumbnailURL) {
            placeholderView
        }
        .squareFrame(size: cardSize)
        .clipShape(.rect(cornerRadius: 8))
        .modifier(HoverPlayOverlay())
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Self.gradientForTitle(album.title))
    }

    private var titleAndYear: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(album.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            if let year = album.year {
                Text(year)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: cardSize, alignment: .leading)
    }

    // MARK: - Helpers

    private static func gradientForTitle(_ title: String) -> LinearGradient {
        let hash = abs(title.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = (hue1 + 0.1).truncatingRemainder(dividingBy: 1.0)

        let color1 = Color(hue: hue1, saturation: 0.6, brightness: 0.5)
        let color2 = Color(hue: hue2, saturation: 0.7, brightness: 0.35)

        return LinearGradient(
            colors: [color1, color2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

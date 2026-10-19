import SwiftUI

// MARK: - SongCard

/// Card view for displaying a song.
struct SongCard: View {
    @Environment(\.cardSize) private var cardSize
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            titleAndSubtitle
        }
    }

    // MARK: - Components
    private var thumbnail: some View {
        ZStack {
            RemoteImage(url: song.thumbnailURL?.cardThumbnailURL) {
                placeholderView
            }
            .squareFrame(size: cardSize)

            Image(systemName: "play.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
                .shadow(radius: 6)
        }
        .clipShape(.rect(cornerRadius: 8))
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Self.gradientForTitle(song.title))
            .aspectRatio(1, contentMode: .fit)
    }

    private var titleAndSubtitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Text(song.artistsDisplay)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

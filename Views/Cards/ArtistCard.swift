import SwiftUI

// MARK: - ArtistCard

/// Card view for displaying an artist with circular thumbnail.
struct ArtistCard: View {
    @Environment(\.cardSize) private var cardSize
    let artist: Artist

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            thumbnail
            nameLabel
        }
    }

    // MARK: - Components

    private var thumbnail: some View {
        RemoteImage(url: artist.thumbnailURL?.cardThumbnailURL) {
            placeholderView
        }
        .squareFrame(size: cardSize)
        .clipShape(.circle)
        .modifier(HoverPlayOverlay())
    }

    private var placeholderView: some View {
        Circle()
            .fill(Self.gradientForName(artist.name))
    }

    private var nameLabel: some View {
        Text(artist.name)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(2, reservesSpace: true)
            .multilineTextAlignment(.center)
            .frame(width: cardSize)
    }

    // MARK: - Helpers

    private static func gradientForName(_ name: String) -> LinearGradient {
        let hash = abs(name.hashValue)
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

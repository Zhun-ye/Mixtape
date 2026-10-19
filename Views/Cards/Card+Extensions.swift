import SwiftUI

// MARK: - Card Size Environment

extension EnvironmentValues {
    /// The size to apply to cards. When nil, no size constraint is applied.
    @Entry var cardSize: CGFloat? = nil
}

// MARK: - Card Size

enum CardSize {
    case small
    case medium
    case large

    var value: CGFloat {
        switch self {
        #if os(iOS)
        case .small: return 120
        case .medium: return 160
        case .large: return 200
        #else
        case .small: return 140
        case .medium: return 180
        case .large: return 230
        #endif
        }
    }
}

extension View {
    /// Sets a predefined card size in the environment.
    func cardSize(_ size: CardSize) -> some View {
        environment(\.cardSize, size.value)
    }

    /// Sets a custom card size in the environment.
    func cardSize(_ size: CGFloat) -> some View {
        environment(\.cardSize, size)
    }
}

// MARK: - Square Frame

extension View {
    /// Applies a square frame with center-cropped content.
    /// When size is provided, uses fixed dimensions. When nil, fills available width.
    func squareFrame(size: CGFloat?) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .overlay {
                self.scaledToFill()
            }
            .clipped()
    }
}

import SwiftUI

// MARK: - FixedProgressView

/// A ProgressView wrapper with explicit frame sizing to prevent AppKit Auto Layout constraint warnings.
/// The standard ProgressView on macOS can produce spurious warnings like:
/// "has a maximum length that doesn't satisfy min <= max"
/// This wrapper provides a fixed frame to avoid these layout ambiguity issues.
struct FixedProgressView: View {
    let controlSize: ControlSize
    let scale: CGFloat

    init(controlSize: ControlSize = .regular, scale: CGFloat = 1.0) {
        self.controlSize = controlSize
        self.scale = scale
    }

    private var frameSize: CGFloat {
        switch self.controlSize {
        case .mini:
            return 12 * self.scale
        case .small:
            return 16 * self.scale
        case .regular:
            return 20 * self.scale
        case .large:
            return 24 * self.scale
        case .extraLarge:
            return 32 * self.scale
        @unknown default:
            return 20 * self.scale
        }
    }

    var body: some View {
        ProgressView()
            .controlSize(self.controlSize)
            .scaleEffect(self.scale)
            .frame(width: self.frameSize, height: self.frameSize)
    }
}

// MARK: - LoadingView

/// Reusable loading indicator view with optional message.
/// Includes a pulsing animation for visual feedback.
struct LoadingView: View {
    let message: String

    init(
        _ message: String = "Loading..."
    ) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(self.message)
                .foregroundStyle(.secondary)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

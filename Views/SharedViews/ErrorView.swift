import SwiftUI

// MARK: - ErrorView

/// Reusable error view with title, message, and retry action.
/// Uses native `ContentUnavailableView` for platform-consistent styling.
@available(macOS 14.0, *)
struct ErrorView: View {
    let title: String
    let message: String
    let retryAction: () -> Void

    init(
        title: String = "Unable to load content",
        message: String,
        retryAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
    }

    var body: some View {
        ContentUnavailableView {
            Label(self.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(self.message)
        } actions: {
            Button("Try Again") {
                self.retryAction()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ErrorView(message: "Something went wrong") {
        // No-op for preview
    }
}

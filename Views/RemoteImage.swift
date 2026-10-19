import Kingfisher
import SwiftUI

// MARK: - RemoteImage

/// A cached image view using Kingfisher's KFImage with fallback support.
struct RemoteImage<Placeholder: View, Fallback: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let fallback: () -> Fallback

    @State private var loadFailed = false

    var body: some View {
        KFImage(url)
            .placeholder { placeholder() }
            .onFailure { _ in
                loadFailed = true
            }
            .cancelOnDisappear(true)
            .resizable()
            .overlay {
                if loadFailed {
                    fallback()
                }
            }
    }
}

// MARK: - Convenience Initializers

extension RemoteImage where Placeholder == EmptyView, Fallback == EmptyView {
    /// Creates a RemoteImage with no placeholder or fallback.
    init(url: URL?) {
        self.url = url
        self.placeholder = { EmptyView() }
        self.fallback = { EmptyView() }
    }
}

extension RemoteImage where Fallback == EmptyView {
    /// Creates a RemoteImage with a placeholder but no fallback.
    init(url: URL?, placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        self.fallback = { EmptyView() }
    }
}

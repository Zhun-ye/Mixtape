import SwiftUI

/// A view that defers the creation of its content until rendered.
/// Useful for preventing eager initialization in TabView.
struct LazyView<Content: View>: View {
    let build: () -> Content

    init(_ build: @escaping () -> Content) {
        self.build = build
    }

    var body: some View {
        build()
    }
}

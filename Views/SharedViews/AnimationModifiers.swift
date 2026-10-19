import SwiftUI

// MARK: - HoverHighlightModifier

#if os(macOS)
/// A view modifier that adds a hover highlight effect to a view.
/// macOS only - has no effect on iOS.
struct HoverHighlightModifier: ViewModifier {
    var cornerRadius: CGFloat = 8
    var padding: CGFloat = 4

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(self.padding)
            .background(
                RoundedRectangle(cornerRadius: self.cornerRadius)
                    .fill(self.isHovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .padding(-self.padding)
            .animation(AppAnimation.quick, value: self.isHovering)
            .onHover { hovering in
                self.isHovering = hovering
            }
    }
}
#endif

extension View {
    /// Adds a hover highlight background effect.
    /// macOS only - returns self unchanged on iOS.
    /// - Parameters:
    ///   - cornerRadius: The corner radius of the highlight.
    ///   - padding: Internal padding for the highlight background.
    /// - Returns: A view with hover highlight effect on macOS, unchanged on iOS.
    func hoverHighlight(cornerRadius: CGFloat = 8, padding: CGFloat = 4) -> some View {
        #if os(macOS)
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius, padding: padding))
        #else
        self
        #endif
    }
}

// MARK: - FadeInModifier

/// A view modifier for smooth fade-in transitions.
struct FadeInModifier: ViewModifier {
    @State private var opacity: Double = 0

    let duration: Double
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(self.opacity)
            .onAppear {
                guard !shouldReduceMotion else {
                    self.opacity = 1
                    return
                }
                withAnimation(.easeIn(duration: self.duration).delay(self.delay)) {
                    self.opacity = 1
                }
            }
    }
}

extension View {
    /// Fades in the view when it appears.
    /// - Parameters:
    ///   - duration: The fade duration (default: 0.3).
    ///   - delay: Delay before starting the fade (default: 0).
    /// - Returns: A view with fade-in animation.
    func fadeIn(duration: Double = 0.3, delay: Double = 0) -> some View {
        modifier(FadeInModifier(duration: duration, delay: delay))
    }
}


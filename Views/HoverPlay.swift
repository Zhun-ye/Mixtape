import SwiftUI

// MARK: - Hover Play Environment

extension EnvironmentValues {
    @Entry var hoverPlayAction: (() -> Void)? = nil
}

// MARK: - Hover Play Modifier

extension View {
    /// Sets a play action in the environment for hover play behavior.
    func hoverPlay(_ action: (() -> Void)?) -> some View {
        environment(\.hoverPlayAction, action)
    }
}

// MARK: - Hover Play Overlay

/// A view modifier that shows a play button overlay on hover (macOS)
/// or context menu on long press (iOS).
/// Reads the play action from the environment.
struct HoverPlayOverlay: ViewModifier {
    @Environment(\.hoverPlayAction) private var playAction
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
        #if os(macOS)
            .overlay(alignment: .bottomTrailing) {
                if let playAction, self.isHovering {
                    Button {
                        playAction()
                    } label: {
                        Circle()
                            .fill(.regularMaterial)
                            .environment(\.colorScheme, .dark)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                self.isHovering = hovering
            }
        #else
            .contextMenu {
                if let playAction {
                    Button {
                        playAction()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                }
            }
        #endif
    }
}

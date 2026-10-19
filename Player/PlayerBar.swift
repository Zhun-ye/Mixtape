import SwiftUI

// MARK: - PlayerBarAppearance

/// Shared observable for views to communicate color scheme to the PlayerBar.
/// Injected via `.environment()` at the app level.
@Observable @MainActor
final class PlayerBarAppearance {
    /// When set, the PlayerBar uses this instead of the system color scheme.
    var colorSchemeOverride: ColorScheme?
}

// MARK: - PlayerBar (iOS)

#if os(iOS)
struct PlayerBar: View {
    @Bindable var viewModel: PlayerViewModel
    var actualColorScheme: ColorScheme = .dark
    @Binding var showFullscreenPlayer: Bool
    @Environment(PlayerBarAppearance.self) private var appearance

    private var effectiveColorScheme: ColorScheme {
        appearance.colorSchemeOverride ?? actualColorScheme
    }

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Tappable track info area - opens fullscreen player
            Button {
                showFullscreenPlayer = true
            } label: {
                HStack(spacing: 12) {
                    // Thumbnail
                    RemoteImage(url: viewModel.currentTrack?.thumbnailURL?.cardThumbnailURL, placeholder: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "music.note")
                                    .foregroundStyle(secondaryTextColor)
                            }
                    })
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Track info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.currentTrack?.title ?? "Not Playing")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(primaryTextColor)
                            .lineLimit(1)

                        if let display = viewModel.currentTrack?.artistsDisplay, !display.isEmpty {
                            Text(display)
                                .font(.caption)
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentTrack == nil)


            // Play/Pause
            Button {
                viewModel.playPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(primaryTextColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            // Next
            Button {
                viewModel.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(primaryTextColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}


#endif

import AVKit
import FactoryKit
import SwiftUI

// MARK: - PlayerBar (macOS)

#if os(macOS)
struct PlayerBar: View {
    @Bindable var viewModel: PlayerViewModel

    @Injected(\.webKitManager) private var webKitManager

    /// Show audio quality popover.
    @State private var showAudioQualityPopover = false

    /// Show volume popover.
    @State private var showVolumePopover = false

    /// Hover state for center section.
    @State private var isCenterHovered = false

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                playbackControls()
                Spacer()
                centerSection()
                Spacer()
                actionControls()
            }
            .overlay(alignment: .trailing) {
                volumePopover()
            }
            .padding(.horizontal, 20)
            .frame(width: 690, height: 54)
            .glassEffect(.regular, in: .capsule)
        }
        .background {
            keyboardShortcuts()
        }
        .onChange(of: viewModel.volume) { _, _ in
            viewModel.syncVolumeValue()
        }
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private func keyboardShortcuts() -> some View {
        Group {
            Button("") {
                viewModel.playPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)

            Button("") {
                viewModel.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .opacity(0)

            Button("") {
                viewModel.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .opacity(0)

            Button("") {
                viewModel.setVolume(min(1.0, viewModel.volume + 0.1))
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .opacity(0)

            Button("") {
                viewModel.setVolume(max(0.0, viewModel.volume - 0.1))
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .opacity(0)

            Button("") {
                viewModel.toggleMute()
            }
            .keyboardShortcut("m", modifiers: .command)
            .opacity(0)
        }
    }

    // MARK: - Center Section

    @ViewBuilder
    private func centerSection() -> some View {
        // Pick track based on player type
        let displayTrack: Song? = viewModel.currentPlayerType == .webView
            ? viewModel.currentWebTrack
            : viewModel.currentTrack

        HStack(spacing: 8) {
            if let track = displayTrack {
                RemoteImage(url: track.thumbnailURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            MarqueeText(text: track.title)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .frame(height: 16)

                            MarqueeText(text: track.artistsDisplay.isEmpty ? "Unknown Artist" : track.artistsDisplay)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(height: 12)
                        }

                        HStack(spacing: 8) {
                            if viewModel.audioQualityLabel != nil {
                                audioQualityIcon()
                            }
                            moreOptionsMenu()
                        }
                        .fixedSize()
                    }

                    Slider(value: viewModel.seekBinding, in: 0 ... 1) { editing in
                        if !editing {
                            viewModel.performSeek()
                        }
                    }
                    .tint(.gray)
                    .controlSize(.mini)
                    .sliderThumbVisibility(.hidden)
                    .frame(height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(alignment: .top) {
                        Color.clear
                            .frame(height: 16)
                            .offset(y: -2)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isCenterHovered = true
                                    }
                                }
                            }
                    }
                }
                .blur(radius: isCenterHovered ? 3 : 0)
                .opacity(isCenterHovered ? 0.3 : 1)
                .overlay(alignment: .leading) {
                    if isCenterHovered {
                        VStack(spacing: 1) {
                            HStack {
                                Text(viewModel.formatTime(viewModel.progress))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(viewModel.formatTime(viewModel.duration))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Slider(value: viewModel.seekBinding, in: 0 ... 1) { editing in
                                if !editing {
                                    viewModel.performSeek()
                                }
                            }
                            .sliderThumbVisibility(.automatic)
                            .tint(.gray)
                        }
                        .offset(y: 6)
                        .transition(.opacity)
                    }
                }
                .onHover { hovering in
                    if !hovering {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCenterHovered = false
                        }
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Playback Controls

    @ViewBuilder
    private func playbackControls() -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(viewModel.shuffleEnabled ? .red : .primary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Shuffle")
            .accessibilityValue(viewModel.shuffleEnabled ? "On" : "Off")

            Button {
                viewModel.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Previous track")

            Button {
                viewModel.playPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            .frame(width: 20)

            Button {
                viewModel.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Next track")

            Button {
                viewModel.cycleRepeatMode()
            } label: {
                Image(systemName: viewModel.repeatIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(viewModel.repeatMode != .off ? .red : .primary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Repeat")
            .accessibilityValue(viewModel.repeatAccessibilityValue)
        }
    }

    // MARK: - Volume Control

    @ViewBuilder
    private func actionControls() -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(AppAnimation.standard) {
                    viewModel.showLyrics.toggle()
                }
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(viewModel.showLyrics ? .red : .primary.opacity(0.85))
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier(AccessibilityID.PlayerBar.lyricsButton)
            .accessibilityLabel("Lyrics")
            .accessibilityValue(viewModel.showLyrics ? "Showing" : "Hidden")
            .disabled(viewModel.currentTrack == nil)

            Button {
                withAnimation(AppAnimation.standard) {
                    viewModel.showQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(viewModel.showQueue ? .red : .primary.opacity(0.85))
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier(AccessibilityID.PlayerBar.queueButton)
            .accessibilityLabel("Queue")
            .accessibilityValue(viewModel.showQueue ? "Showing" : "Hidden")

            AirPlayButton()
                .frame(width: 18, height: 18)
                .scaleEffect(1.2)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumePopover.toggle()
                }
            } label: {
                Image(systemName: viewModel.volumeIcon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 24)
            }
            .buttonStyle(.pressable)
        }
    }

    @ViewBuilder
    private func volumePopover() -> some View {
        if showVolumePopover {
            HStack(spacing: 8) {
                Slider(value: $viewModel.volumeValue, in: 0...1) { editing in
                    if editing {
                        viewModel.isAdjustingVolume = true
                    } else {
                        viewModel.performVolumeChange()
                    }
                }
                .frame(width: 120)
                .controlSize(.regular)
                .tint(.gray)
                .onChange(of: viewModel.volumeValue) { _, newValue in
                    if viewModel.isAdjustingVolume {
                        viewModel.setVolume(newValue)
                    }
                }

                Image(systemName: viewModel.volumeIcon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 20, height: 24)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 10))
            .glassEffect()
            .offset(x: 10)
            .onHover { hovering in
                if !hovering {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showVolumePopover = false
                    }
                }
            }
        }
    }

    // MARK: - More Options Menu

    @ViewBuilder
    private func moreOptionsMenu() -> some View {
        Menu {
            if let track = viewModel.currentTrack {
                Button {
                    viewModel.likeCurrentTrack()
                } label: {
                    Label(
                        viewModel.currentTrackLikeStatus == .like ? "Liked" : "Like",
                        systemImage: viewModel.currentTrackLikeStatus == .like ? "hand.thumbsup.fill" : "hand.thumbsup"
                    )
                }

                Button {
                    viewModel.dislikeCurrentTrack()
                } label: {
                    Label(
                        viewModel.currentTrackLikeStatus == .dislike ? "Disliked" : "Dislike",
                        systemImage: viewModel.currentTrackLikeStatus == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown"
                    )
                }

                Divider()

                Button {
                    viewModel.addToLibrary(track)
                } label: {
                    Label("Add to Library", systemImage: "plus.circle")
                }

                Divider()

                if let playlist = viewModel.sourcePlaylist {
                    Button {
                        NotificationCenter.default.post(
                            name: .navigateToPlaylist,
                            object: playlist
                        )
                    } label: {
                        Label("Go to \(playlist.title)", systemImage: "music.note.list")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 16)
        .disabled(viewModel.currentTrack == nil)
    }

    // MARK: - Audio Quality Icon

    @ViewBuilder
    private func audioQualityIcon() -> some View {
        Button {
            showAudioQualityPopover.toggle()
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showAudioQualityPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio Quality")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)

                if let label = viewModel.audioQualityLabel {
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - AirPlayButton

struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context _: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.isRoutePickerButtonBordered = false
        routePickerView.setRoutePickerButtonColor(NSColor(.primary), for: .normal)
        return routePickerView
    }

    func updateNSView(_: AVRoutePickerView, context _: Context) {}
}

// MARK: - Preview

#Preview {
    PlayerBar(viewModel: PlayerViewModel())
        .frame(width: 600)
        .padding()
        .background(Color.gray.opacity(0.2))
}
#endif

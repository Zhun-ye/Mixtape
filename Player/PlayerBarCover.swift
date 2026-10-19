import AVKit
import SwiftUI

// MARK: - PlayerBarCover (iOS)

#if os(iOS)
struct PlayerBarCover: View {
    @Bindable var viewModel: PlayerViewModel
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var trackInfoOpacity: Double = 1.0
    @Namespace private var animation

    /// Whether showing lyrics or queue inline (replaces artwork)
    private var isShowingPanel: Bool {
        viewModel.showLyrics || viewModel.showQueue
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary)
                .frame(width: 56, height: 5)
                .padding(.top, 6)

            // Content area
            ZStack(alignment: isShowingPanel ? .topLeading : .center) {
                // Single artwork that animates position/size
                HStack(spacing: isShowingPanel ? 12 : 0) {
                    artworkView()

                    // Inline track info when showing panel
                    if isShowingPanel {
                        trackInfoSection()
                            .opacity(trackInfoOpacity)
                    }
                }
                .padding(.top, isShowingPanel ? 8 : 36)
                .padding(.bottom, isShowingPanel ? 0 : 80)
                .frame(maxWidth: .infinity, alignment: isShowingPanel ? .leading : .center)

                // Track info below artwork (only when not showing panel)
                if !isShowingPanel {
                    VStack {
                        Spacer()
                        trackInfoSection()
                    }
                    .opacity(trackInfoOpacity)
                }

                // Panel content
                if isShowingPanel {
                    VStack {
                        Spacer()
                            .frame(height: 64)
                        panelContent()
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut, value: isShowingPanel)

            Spacer()
                .frame(height: 24)

            // Progress bar with times
            progressSection()

            Spacer()
                .frame(height: 42)

            // Playback controls
            playbackControls()

            Spacer()
                .frame(height: 42)

            // Volume slider
            volumeSection()

            Spacer()
                .frame(height: 24)

            // Bottom action buttons
            bottomActions()

            Spacer()
                .frame(height: 12)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            containerWidth = newWidth
        }
        .background {
            // Album art as full background with smooth crossfade on track change
            RemoteImage(url: viewModel.currentTrack?.thumbnailURL?.cardThumbnailURL, placeholder: {
                Color(.systemGray6)
            })
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blur(radius: 60)
            .scaleEffect(1.2) // Prevent blur edges from showing
            .clipped()
            .overlay(.regularMaterial)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: viewModel.currentTrack?.videoId)
        }
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.volume) { _, _ in
            viewModel.syncVolumeValue()
        }
        .onChange(of: isShowingPanel) { _, _ in
            // Fade out immediately, then fade in after geometry animation completes
            trackInfoOpacity = 0
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.2)) {
                        trackInfoOpacity = 1
                    }
                }
            }
        }
    }

    // MARK: - Artwork

    private var artworkSize: CGFloat {
        isShowingPanel ? 48 : containerWidth * 0.64
    }

    @ViewBuilder
    private func artworkView() -> some View {
        RemoteImage(
            url: viewModel.currentTrack?.thumbnailURL?.heroThumbnailURL,
            placeholder: {
                Color(.systemGray6)
            },
            fallback: {
                Color(.systemGray6)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: isShowingPanel ? 16 : 64))
                            .foregroundStyle(.secondary)
                    }
            }
        )
        .aspectRatio(contentMode: .fill)
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: isShowingPanel ? 6 : 8))
        .shadow(color: .black.opacity(isShowingPanel ? 0 : 0.2), radius: 20, x: 0, y: 10)
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent() -> some View {
        if viewModel.showLyrics {
            LyricsView()
                .environment(\.colorScheme, .dark)
        } else if viewModel.showQueue {
            QueueView()
                .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - Track Info Header

    @ViewBuilder
    private func trackInfoSection() -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.currentTrack?.title ?? "Not Playing")
                    .font(.system(size: isShowingPanel ? 17 : 20, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(height: isShowingPanel ? 22 : 26)
                    .matchedGeometryEffect(id: "title", in: animation)

                Text(viewModel.currentTrack?.artistsDisplay ?? "")
                    .font(.system(size: isShowingPanel ? 15 : 17))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: isShowingPanel ? 20 : 22)
                    .matchedGeometryEffect(id: "artist", in: animation)
            }

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                AirPlayButton()
                    .scaleEffect(1.2)
                    .frame(width: 30, height: 30)
                moreOptionsButton()
            }
            .matchedGeometryEffect(id: "menu", in: animation)
        }
    }

    @ViewBuilder
    private func moreOptionsButton() -> some View {
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

                if let playlist = viewModel.sourcePlaylist {
                    Divider()

                    Button {
                        onDismiss()
                        viewModel.onNavigateToPlaylist?()
                    } label: {
                        Label("Go to \(playlist.title)", systemImage: "music.note.list")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(.white, .white.opacity(0.1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // MARK: - Progress Section

    @ViewBuilder
    private func progressSection() -> some View {
        VStack(spacing: -2) {
            // Seek slider
            Slider(
                value: viewModel.seekBinding,
                in: 0 ... 1
            ) { editing in
                if !editing {
                    viewModel.performSeek()
                }
            }
            .tint(.primary)
            .sliderThumbVisibility(.hidden)

            // Time labels
            HStack {
                Text(viewModel.formatTime(viewModel.progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)

                Spacer()

                // Audio quality badge (fixed frame to prevent layout jumps)
                Text(viewModel.audioQualityLabel ?? "128kbps")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .opacity(viewModel.audioQualityLabel != nil ? 1 : 0)

                Spacer()

                Text(viewModel.formatRemainingTime(viewModel.progress, total: viewModel.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    // MARK: - Playback Controls

    @ViewBuilder
    private func playbackControls() -> some View {
        HStack(spacing: 48) {
            // Previous
            Button {
                viewModel.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            // Play/Pause
            Button {
                viewModel.playPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .frame(width: 64)

            // Next
            Button {
                viewModel.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Volume Section

    @ViewBuilder
    private func volumeSection() -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            MPVolumeSlider()

            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
        }
        .frame(height: 20)
    }

    // MARK: - Bottom Actions

    @ViewBuilder
    private func bottomActions() -> some View {
        HStack(spacing: 44) {
            // Shuffle
            Button {
                viewModel.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(viewModel.shuffleEnabled ? .white : .secondary)
                    .scaleEffect(y: viewModel.shuffleEnabled ? -1 : 1)
                    .frame(width: 30, height: 30)
                    .padding(4)
                    .background {
                        Circle()
                            .fill(.white.opacity(viewModel.shuffleEnabled ? 0.2 : 0))
                    }
                    .animation(.easeInOut(duration: 0.3), value: viewModel.shuffleEnabled)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shuffle")
            .accessibilityValue(viewModel.shuffleEnabled ? "On" : "Off")

            // Lyrics
            Button {
                withAnimation(.easeInOut) {
                    if viewModel.showLyrics {
                        viewModel.showLyrics = false
                    } else {
                        viewModel.showQueue = false
                        viewModel.showLyrics = true
                    }
                }
            } label: {
                Image(systemName: "quote.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(viewModel.showLyrics ? .white : .secondary)
                    .frame(width: 30, height: 30)
                    .padding(4)
                    .background {
                        Circle()
                            .fill(.white.opacity(viewModel.showLyrics ? 0.2 : 0))
                    }
                    .animation(.easeInOut, value: viewModel.showLyrics)
            }
            .disabled(viewModel.currentTrack == nil)
            .buttonStyle(.plain)

            // Queue
            Button {
                withAnimation(.easeInOut) {
                    if viewModel.showQueue {
                        viewModel.showQueue = false
                    } else {
                        viewModel.showLyrics = false
                        viewModel.showQueue = true
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(viewModel.showQueue ? .white : .secondary)
                    .frame(width: 30, height: 30)
                    .padding(4)
                    .background {
                        Circle()
                            .fill(.white.opacity(viewModel.showQueue ? 0.2 : 0))
                    }
                    .animation(.easeInOut, value: viewModel.showQueue)
            }
            .buttonStyle(.plain)

            // Repeat
            Button {
                viewModel.cycleRepeatMode()
            } label: {
                Image(systemName: viewModel.repeatIcon)
                    .font(.title3)
                    .foregroundStyle(viewModel.repeatMode != .off ? .white : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .padding(4)
                    .background {
                        Circle()
                            .fill(.white.opacity(viewModel.repeatMode != .off ? 0.2 : 0))
                    }
                    .animation(.easeInOut, value: viewModel.repeatMode)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat")
            .accessibilityValue(viewModel.repeatAccessibilityValue)
        }
    }
}

// MARK: - AirPlayButton (iOS)

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context _: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = UIColor(.secondary)
        routePickerView.activeTintColor = UIColor(.secondary)
        routePickerView.prioritizesVideoDevices = false
        return routePickerView
    }

    func updateUIView(_: AVRoutePickerView, context _: Context) {}
}

// MARK: - MPVolumeSlider (iOS)

import MediaPlayer

struct MPVolumeSlider: UIViewRepresentable {
    func makeUIView(context _: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.setVolumeThumbImage(UIImage(), for: .normal)
        volumeView.tintColor = .secondaryLabel
        return volumeView
    }

    func updateUIView(_: MPVolumeView, context _: Context) {}
}

#endif

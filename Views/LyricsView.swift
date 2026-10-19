import FoundationModels
import SwiftUI
import FactoryKit
import os

/// Right sidebar panel displaying lyrics for the current track.
struct LyricsView: View {
    @Injected(\.playerManager) private var playerManager
    @Injected(\.ytMusicClient) private var client

    @State private var lyrics: Lyrics?
    @State private var isLoading = false
    @State private var lastLoadedVideoId: String?

    // AI explanation state
    @State private var lyricsSummary: LyricsSummary?
    @State private var partialSummary: LyricsSummary.PartiallyGenerated?
    @State private var isExplaining = false
    @State private var showExplanation = false
    @State private var explanationError: String?

    private let logger = DiagnosticsLogger.ai

    var body: some View {
        VStack(spacing: 0) {
            // Header
            self.headerView

            // Content
            self.contentView
        }
        #if os(macOS)
        .frame(minWidth: 280, maxWidth: 280)
        #endif
        .onChange(of: playerManager.currentTrack?.videoId) { _, newVideoId in
            if let videoId = newVideoId, videoId != lastLoadedVideoId {
                // Reset explanation when track changes
                self.lyricsSummary = nil
                self.partialSummary = nil
                self.showExplanation = false
                self.explanationError = nil
                Task {
                    await self.loadLyrics(for: videoId)
                }
            }
        }
        .task {
            if let videoId = playerManager.currentTrack?.videoId {
                await self.loadLyrics(for: videoId)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Lyrics")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if self.isLoading {
            self.loadingView
        } else if let lyrics, lyrics.isAvailable {
            self.lyricsContentView(lyrics)
        } else {
            self.noLyricsView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .frame(width: 20, height: 20)
            Text("Loading lyrics...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lyricsContentView(_ lyrics: Lyrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Lyrics text
                Text(lyrics.text)
                    .font(.body).fontWeight(.medium)
                    .lineSpacing(8)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)

                // Source attribution
                if let source = lyrics.source {
                    Divider()
                        .padding(.horizontal, 16)

                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .scrollClipDisabled()
        }
        .scrollContentBackground(.hidden)
    }

    private func explanationSection(_ summary: LyricsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mood
            HStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(.pink)
                Text(summary.mood.capitalized)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Themes
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(summary.themes, id: \.self) { theme in
                        Text(theme)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.purple.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
            }

            // Explanation
            Text(summary.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(.purple.opacity(0.05))
    }

    /// Shows partial content as it streams in from the AI.
    private func streamingExplanationSection(_ partial: LyricsSummary.PartiallyGenerated) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mood (shows when available)
            HStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(.pink)
                if let mood = partial.mood {
                    Text(mood.capitalized)
                        .font(.subheadline.weight(.medium))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Themes (shows as they arrive)
            if let themes = partial.themes, !themes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(themes, id: \.self) { theme in
                            Text(theme)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.purple.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Explanation (shows progressively)
            if let explanation = partial.explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                    Text("Analyzing...")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(.purple.opacity(0.05))
    }

    private var noLyricsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No Lyrics Available")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("There aren't any lyrics available for this song.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadLyrics(for videoId: String) async {
        self.isLoading = true
        self.lastLoadedVideoId = videoId

        do {
            let fetchedLyrics = try await client.getLyrics(videoId: videoId)
            // Only update if still relevant (user hasn't changed tracks)
            if playerManager.currentTrack?.videoId == videoId {
                self.lyrics = fetchedLyrics
            }
        } catch {
            DiagnosticsLogger.api.error("Failed to load lyrics: \(error.localizedDescription)")
            self.lyrics = .unavailable
        }

        self.isLoading = false
    }

}

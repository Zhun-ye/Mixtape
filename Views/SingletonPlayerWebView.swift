import SwiftUI
import FactoryKit
import WebKit
import os

#if os(macOS)
import AppKit
typealias PlatformView = NSView
#else
import UIKit
typealias PlatformView = UIView
#endif

#if os(iOS)
import AVFoundation
#endif

// MARK: - SingletonPlayerWebViewObserver

/// Observer protocol for receiving playback updates from SingletonPlayerWebView.
/// Used by YTMusicWebPlayer to bridge WebView callbacks to the YTMusicPlayer protocol.
@MainActor
protocol SingletonPlayerWebViewObserver: AnyObject {
    func webViewDidUpdatePlaybackState(isPlaying: Bool, progress: TimeInterval, duration: TimeInterval)
    func webViewDidUpdateTrackMetadata(title: String, artist: String, thumbnailUrl: String)
    func webViewDidUpdateLikeStatus(_ status: LikeStatus)
    func webViewDidUpdateAudioQuality(bitrateKbps: Int, codec: String)
    func webViewDidEncounterError(_ error: Error)
    func webViewTrackDidEnd()
}

/// Manages a single WebView instance for the entire app lifetime.
/// This ensures there's only ever ONE WebView playing audio.
@MainActor
final class SingletonPlayerWebView {
    static let shared = SingletonPlayerWebView()

    private(set) var webView: WKWebView?
    var currentVideoId: String?
    private var coordinator: Coordinator?
    private let logger = DiagnosticsLogger.player

    /// Observer for playback updates (used by YTMusicWebPlayer).
    weak var audioPlayerObserver: SingletonPlayerWebViewObserver?

    private init() {}

    /// Get or create the singleton WebView.
    func getWebView(
        webKitManager: WebKitManager,
        playerManager: PlayerManager
    ) -> WKWebView {
        if let existing = webView {
            return existing
        }

        self.logger.info("Creating singleton WebView")

        // Create coordinator
        self.coordinator = Coordinator(playerManager: playerManager)

        let configuration = webKitManager.createWebViewConfiguration()

        #if os(iOS)
        // Enable inline media playback and background audio
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Inject script to prevent pausing when app goes to background
        let backgroundPlaybackScript = WKUserScript(
            source: Self.backgroundPlaybackScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(backgroundPlaybackScript)
        #endif

        // Add script message handler
        configuration.userContentController.add(self.coordinator!, name: "singletonPlayer")

        // Inject observer script
        let script = WKUserScript(
            source: Self.observerScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(script)

        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = self.coordinator
        newWebView.customUserAgent = WebKitManager.userAgent

        #if DEBUG
            newWebView.isInspectable = true
        #endif

        self.webView = newWebView
        return newWebView
    }

    /// Ensures the WebView is in the given container's view hierarchy.
    func ensureInHierarchy(container: PlatformView) {
        guard let webView, webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        #if os(macOS)
        webView.autoresizingMask = [.width, .height]
        #else
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #endif
        container.addSubview(webView)
    }

    /// Load a video, stopping any currently playing audio first.
    func loadVideo(videoId: String) {
        guard let webView else {
            self.logger.error("loadVideo called but webView is nil")
            return
        }

        let previousVideoId = self.currentVideoId
        guard videoId != previousVideoId else {
            self.logger.info("Video \(videoId) already loaded, skipping")
            return
        }

        self.logger.info("Loading video: \(videoId) (was: \(previousVideoId ?? "none"))")

        // Update currentVideoId immediately to prevent duplicate loads
        self.currentVideoId = videoId

        // Get current volume from PlayerManager via coordinator
        let currentVolume = self.coordinator?.playerManager.volume ?? 1.0
        self.logger.info("Will apply volume \(currentVolume) after page load")

        // Stop current playback first, then load new video
        let urlToLoad = URL(string: "https://music.youtube.com/watch?v=\(videoId)")!
        webView.evaluateJavaScript("document.querySelector('video')?.pause()") { [weak self] _, _ in
            guard let self, let webView = self.webView else { return }

            // Set target volume BEFORE loading so it's ready when video element appears
            let setTargetScript = "window.__mixtapeTargetVolume = \(currentVolume);"
            webView.evaluateJavaScript(setTargetScript, completionHandler: nil)

            webView.load(URLRequest(url: urlToLoad))
        }
    }

    // MARK: - Playback Controls

    /// Toggle play/pause.
    func playPause() {
        guard let webView else { return }
        self.logger.debug("playPause() called")

        let script = """
            (function() {
                const playBtn = document.querySelector('.play-pause-button.ytmusic-player-bar');
                if (playBtn) { playBtn.click(); return 'clicked'; }
                const video = document.querySelector('video');
                if (video) {
                    if (video.paused) { video.play(); return 'played'; }
                    else { video.pause(); return 'paused'; }
                }
                return 'no-element';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("playPause error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("playPause result: \(String(describing: result))")
            }
        }
    }

    /// Play (resume).
    func play() {
        guard let webView else { return }
        self.logger.debug("play() called")

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (video && video.paused) { video.play(); return 'played'; }
                return 'already-playing';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Pause.
    func pause() {
        guard let webView else { return }
        self.logger.debug("pause() called")

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (video && !video.paused) { video.pause(); return 'paused'; }
                return 'already-paused';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Skip to next track.
    func next() {
        guard let webView else { return }
        self.logger.debug("next() called")

        let script = """
            (function() {
                const nextBtn = document.querySelector('.next-button.ytmusic-player-bar');
                if (nextBtn) { nextBtn.click(); return 'clicked'; }
                return 'no-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("next error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("next result: \(String(describing: result))")
            }
        }
    }

    /// Go to previous track.
    func previous() {
        guard let webView else { return }
        self.logger.debug("previous() called")

        let script = """
            (function() {
                const prevBtn = document.querySelector('.previous-button.ytmusic-player-bar');
                if (prevBtn) { prevBtn.click(); return 'clicked'; }
                return 'no-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("previous error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("previous result: \(String(describing: result))")
            }
        }
    }

    /// Seek to a specific time in seconds.
    func seek(to time: Double) {
        guard let webView else { return }
        self.logger.debug("seek(to: \(time)) called")

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (video) { video.currentTime = \(time); return 'seeked'; }
                return 'no-video';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Set volume (0.0 - 1.0).
    func setVolume(_ volume: Double) {
        guard let webView else { return }
        let clampedVolume = max(0, min(1, volume))
        self.logger.debug("setVolume(\(clampedVolume)) called")

        let script = """
            (function() {
                window.__mixtapeTargetVolume = \(clampedVolume);
                const video = document.querySelector('video');
                if (video) { video.volume = \(clampedVolume); return 'set'; }
                return 'no-video';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    #if os(iOS)
    // Script to prevent pausing when app goes to background
    // The player uses the Page Visibility API to detect when the tab is hidden
    // and pauses playback. This script overrides that behavior.
    private static var backgroundPlaybackScript: String {
        """
        (function() {
            'use strict';

            // Override document.hidden to always return false
            Object.defineProperty(document, 'hidden', {
                get: function() { return false; },
                configurable: true
            });

            // Override document.visibilityState to always return 'visible'
            Object.defineProperty(document, 'visibilityState', {
                get: function() { return 'visible'; },
                configurable: true
            });

            // Prevent visibilitychange events from firing
            document.addEventListener('visibilitychange', function(e) {
                e.stopImmediatePropagation();
            }, true);

            // Override webkit-prefixed Page Visibility API
            Object.defineProperty(document, 'webkitHidden', {
                get: function() { return false; },
                configurable: true
            });

            Object.defineProperty(document, 'webkitVisibilityState', {
                get: function() { return 'visible'; },
                configurable: true
            });

            document.addEventListener('webkitvisibilitychange', function(e) {
                e.stopImmediatePropagation();
            }, true);
        })();
        """
    }
    #endif

    // Observer script for playback state
    private static var observerScript: String {
        """
        (function() {
            'use strict';
            const bridge = window.webkit.messageHandlers.singletonPlayer;
            let lastTitle = '';
            let lastArtist = '';
            let isPollingActive = false;
            let pollIntervalId = null;
            let lastUpdateTime = 0;
            const UPDATE_THROTTLE_MS = 250; // Throttle updates to max 4/sec
            const POLL_INTERVAL_MS = 500; // Poll at 2Hz during playback

            function waitForPlayerBar() {
                const playerBar = document.querySelector('ytmusic-player-bar');
                if (playerBar) {
                    setupObserver(playerBar);
                    setupVideoListeners();
                    return;
                }
                setTimeout(waitForPlayerBar, 500);
            }

            function setupVideoListeners() {
                let isEnforcingVolume = false;

                // Watch for video element to attach play/pause listeners
                function attachVideoListeners() {
                    const video = document.querySelector('video');
                    if (!video) {
                        setTimeout(attachVideoListeners, 500);
                        return;
                    }

                    video.addEventListener('play', startPolling);
                    video.addEventListener('playing', startPolling);
                    video.addEventListener('pause', stopPolling);
                    video.addEventListener('ended', stopPolling);
                    video.addEventListener('waiting', () => sendUpdate()); // Buffer state
                    video.addEventListener('seeked', () => sendUpdate()); // Seek completed

                    // Volume enforcement - prevent YouTube from overriding our volume
                    video.addEventListener('volumechange', () => {
                        if (isEnforcingVolume) return; // Ignore our own changes
                        const targetVol = window.__mixtapeTargetVolume;
                        // Only enforce if we have a valid target volume set by Swift
                        if (targetVol !== undefined && Math.abs(video.volume - targetVol) > 0.01) {
                            isEnforcingVolume = true;
                            video.volume = targetVol;
                            isEnforcingVolume = false;
                        }
                    });

                    // Don't auto-apply volume here - let loadVideo handle it with the current value
                    // This prevents applying stale volume from WebView creation time

                    // Start polling if already playing
                    if (!video.paused) {
                        startPolling();
                    }
                }

                // Watch for new video elements (page navigation can recreate them)
                const videoObserver = new MutationObserver(() => {
                    const video = document.querySelector('video');
                    if (video && !video.__mixtapeListenersAttached) {
                        video.__mixtapeListenersAttached = true;
                        attachVideoListeners();
                        // Apply current target volume to new video element
                        if (window.__mixtapeTargetVolume !== undefined) {
                            video.volume = window.__mixtapeTargetVolume;
                        }
                    }
                });
                videoObserver.observe(document.body, { childList: true, subtree: true });

                attachVideoListeners();
            }

            function startPolling() {
                if (isPollingActive) return;
                isPollingActive = true;

                // Apply target volume when playback starts
                // This is the most reliable point since the video element definitely exists
                const video = document.querySelector('video');
                if (video && window.__mixtapeTargetVolume !== undefined) {
                    video.volume = window.__mixtapeTargetVolume;
                }

                sendUpdate(); // Immediate update
                // Poll at 1Hz during playback for progress updates (reduced CPU usage)
                pollIntervalId = setInterval(sendUpdate, POLL_INTERVAL_MS);
            }

            function stopPolling() {
                isPollingActive = false;
                if (pollIntervalId) {
                    clearInterval(pollIntervalId);
                    pollIntervalId = null;
                }
                sendUpdate(); // Final state update
            }

            function setupObserver(playerBar) {
                // Debounced mutation observer - only triggers on significant changes
                let mutationTimeout = null;
                const observer = new MutationObserver(() => {
                    if (mutationTimeout) return;
                    mutationTimeout = setTimeout(() => {
                        mutationTimeout = null;
                        sendUpdate();
                    }, 100);
                });
                observer.observe(playerBar, {
                    attributes: true, characterData: true,
                    childList: true, subtree: true,
                    attributeFilter: ['title', 'aria-label', 'like-status', 'value', 'aria-valuemax']
                });
                sendUpdate();
            }

            function sendUpdate() {
                // Throttle updates
                const now = Date.now();
                if (now - lastUpdateTime < UPDATE_THROTTLE_MS && isPollingActive) {
                    return;
                }
                lastUpdateTime = now;

                try {
                    // Use video element's paused property as primary source of truth
                    const video = document.querySelector('video');
                    const isPlaying = video ? !video.paused : false;

                    const progressBar = document.querySelector('#progress-bar');

                    // Extract track metadata
                    const titleEl = document.querySelector('.ytmusic-player-bar.title');
                    const artistEl = document.querySelector('.ytmusic-player-bar.byline');
                    const thumbEl = document.querySelector('.ytmusic-player-bar .thumbnail img, ytmusic-player-bar .image');

                    const title = titleEl ? titleEl.textContent.trim() : '';
                    const artist = artistEl ? artistEl.textContent.trim() : '';
                    let thumbnailUrl = '';

                    // Get the thumbnail URL from the image element
                    if (thumbEl) {
                        thumbnailUrl = thumbEl.src || thumbEl.getAttribute('src') || '';
                    }

                    // Extract like status from the like button renderer
                    let likeStatus = 'INDIFFERENT';
                    const likeRenderer = document.querySelector('ytmusic-like-button-renderer');
                    if (likeRenderer) {
                        const status = likeRenderer.getAttribute('like-status');
                        if (status === 'LIKE') likeStatus = 'LIKE';
                        else if (status === 'DISLIKE') likeStatus = 'DISLIKE';
                    }

                    // Check if track changed
                    const trackChanged = (title !== lastTitle || artist !== lastArtist) && title !== '';
                    if (trackChanged) {
                        lastTitle = title;
                        lastArtist = artist;
                    }

                    // Extract audio quality/bitrate from YouTube player
                    let audioQuality = 'unknown';
                    let audioBitrate = 0;
                    let audioCodec = 'unknown';
                    try {
                        const ytPlayer = document.querySelector('#movie_player');
                        if (ytPlayer) {
                            // Try getStatsForNerds or similar internal APIs
                            if (typeof ytPlayer.getVideoStats === 'function') {
                                const stats = ytPlayer.getVideoStats();
                                if (stats && stats.afmt) {
                                    // afmt contains audio format info like "251/opus/48000Hz"
                                    audioCodec = stats.afmt;
                                }
                            }
                            // Try to get adaptive format info
                            if (typeof ytPlayer.getPlayerResponse === 'function') {
                                const response = ytPlayer.getPlayerResponse();
                                if (response && response.streamingData && response.streamingData.adaptiveFormats) {
                                    const audioFormats = response.streamingData.adaptiveFormats
                                        .filter(f => f.mimeType && f.mimeType.startsWith('audio/'));
                                    // Find the currently playing audio format (usually highest bitrate)
                                    const bestAudio = audioFormats.reduce((best, cur) =>
                                        (cur.bitrate > (best?.bitrate || 0)) ? cur : best, null);
                                    if (bestAudio) {
                                        audioBitrate = bestAudio.bitrate || 0;
                                        audioCodec = bestAudio.mimeType || 'unknown';
                                    }
                                }
                            }
                            // Fallback to playback quality
                            if (typeof ytPlayer.getPlaybackQuality === 'function') {
                                audioQuality = ytPlayer.getPlaybackQuality() || 'unknown';
                            }
                        }
                    } catch (e) {}

                    bridge.postMessage({
                        type: 'STATE_UPDATE',
                        isPlaying: isPlaying,
                        progress: progressBar ? parseInt(progressBar.getAttribute('value') || '0') : 0,
                        duration: progressBar ? parseInt(progressBar.getAttribute('aria-valuemax') || '0') : 0,
                        title: title,
                        artist: artist,
                        thumbnailUrl: thumbnailUrl,
                        trackChanged: trackChanged,
                        likeStatus: likeStatus,
                        audioQuality: audioQuality,
                        audioBitrate: audioBitrate,
                        audioCodec: audioCodec
                    });
                } catch (e) {}
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', waitForPlayerBar);
            } else {
                waitForPlayerBar();
            }
        })();
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let playerManager: PlayerManager

        init(playerManager: PlayerManager) {
            self.playerManager = playerManager
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  type == "STATE_UPDATE"
            else { return }

            let isPlaying = body["isPlaying"] as? Bool ?? false
            let progress = body["progress"] as? Int ?? 0
            let duration = body["duration"] as? Int ?? 0
            let title = body["title"] as? String ?? ""
            let artist = body["artist"] as? String ?? ""
            let thumbnailUrl = body["thumbnailUrl"] as? String ?? ""
            let trackChanged = body["trackChanged"] as? Bool ?? false
            let likeStatusString = body["likeStatus"] as? String ?? "INDIFFERENT"
            let audioQuality = body["audioQuality"] as? String ?? "unknown"
            let audioBitrate = body["audioBitrate"] as? Int ?? 0
            let audioCodec = body["audioCodec"] as? String ?? "unknown"

            // Parse like status
            let likeStatus: LikeStatus = switch likeStatusString {
            case "LIKE":
                .like
            case "DISLIKE":
                .dislike
            default:
                .indifferent
            }

            Task { @MainActor in
                // Notify the audio player observer (for YTMusicPlayer protocol)
                let observer = SingletonPlayerWebView.shared.audioPlayerObserver
                observer?.webViewDidUpdatePlaybackState(
                    isPlaying: isPlaying,
                    progress: Double(progress),
                    duration: Double(duration)
                )

                // Update and log audio quality/bitrate
                let bitrateKbps = audioBitrate / 1000
                observer?.webViewDidUpdateAudioQuality(bitrateKbps: bitrateKbps, codec: audioCodec)

                // Update PlayerManager (existing behavior)
                playerManager.updatePlaybackState(
                    isPlaying: isPlaying,
                    progress: Double(progress),
                    duration: Double(duration)
                )
                playerManager.updateAudioQuality(bitrateKbps: bitrateKbps, codec: audioCodec)

                if trackChanged, !title.isEmpty {
                    if bitrateKbps > 0 {
                        DiagnosticsLogger.player.info("🎵 Audio: \(bitrateKbps) kbps | Codec: \(audioCodec) | Track: \(title) - \(artist)")
                    } else {
                        DiagnosticsLogger.player.info("🎵 Audio quality: \(audioQuality) | Codec: \(audioCodec) | Track: \(title) - \(artist)")
                    }
                }

                // Update like status only when track changes (initial state)
                if trackChanged {
                    observer?.webViewDidUpdateLikeStatus(likeStatus)
                    playerManager.updateLikeStatus(likeStatus)
                }

                // Update track metadata if track changed
                if trackChanged, !title.isEmpty {
                    observer?.webViewDidUpdateTrackMetadata(
                        title: title,
                        artist: artist,
                        thumbnailUrl: thumbnailUrl
                    )
                    playerManager.updateWebTrackMetadata(
                        title: title,
                        artist: artist,
                        thumbnailUrl: thumbnailUrl
                    )
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            DiagnosticsLogger.player.info("Singleton WebView finished loading: \(webView.url?.absoluteString ?? "nil")")
        }
    }
}

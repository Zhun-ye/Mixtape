import SwiftUI
import os
import WebKit

// MARK: - PersistentPlayerView

/// A SwiftUI view that displays the singleton WebView.
/// The WebView is created once and reused for all playback.
#if os(macOS)
import AppKit

struct PersistentPlayerView: NSViewRepresentable {
    let videoId: String
    let isExpanded: Bool
    let playerManager: PlayerManager
    let webKitManager: WebKitManager

    private let logger = DiagnosticsLogger.player

    func makeNSView(context _: Context) -> NSView {
        self.logger.info("PersistentPlayerView.makeNSView for videoId: \(self.videoId)")

        let container = NSView(frame: .zero)
        container.wantsLayer = true

        // Get or create the singleton WebView
        let webView = SingletonPlayerWebView.shared.getWebView(
            webKitManager: self.webKitManager,
            playerManager: playerManager
        )

        // Remove from any previous superview and add to this container
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)

        // Load the video if needed - use loadVideo() to ensure volume is applied
        if SingletonPlayerWebView.shared.currentVideoId != self.videoId {
            self.logger.info("Initial load for videoId: \(self.videoId)")
            SingletonPlayerWebView.shared.loadVideo(videoId: self.videoId)
        }

        return container
    }

    func updateNSView(_ container: NSView, context _: Context) {
        self.logger.info("PersistentPlayerView.updateNSView for videoId: \(self.videoId)")

        // Ensure WebView is in this container
        let webView = SingletonPlayerWebView.shared.getWebView(
            webKitManager: self.webKitManager,
            playerManager: playerManager
        )

        if webView.superview !== container {
            self.logger.info("Re-parenting WebView to current container")
            webView.removeFromSuperview()
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }

        webView.frame = container.bounds

        // Load new video if changed
        SingletonPlayerWebView.shared.loadVideo(videoId: self.videoId)
    }
}
#else
import UIKit

struct PersistentPlayerView: UIViewRepresentable {
    let videoId: String
    let isExpanded: Bool
    let playerManager: PlayerManager
    let webKitManager: WebKitManager

    private let logger = DiagnosticsLogger.player

    func makeUIView(context _: Context) -> UIView {
        self.logger.info("PersistentPlayerView.makeUIView for videoId: \(self.videoId)")

        let container = UIView(frame: .zero)

        // Get or create the singleton WebView
        let webView = SingletonPlayerWebView.shared.getWebView(
            webKitManager: self.webKitManager,
            playerManager: playerManager
        )

        // Remove from any previous superview and add to this container
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)

        // Load the video if needed - use loadVideo() to ensure volume is applied
        if SingletonPlayerWebView.shared.currentVideoId != self.videoId {
            self.logger.info("Initial load for videoId: \(self.videoId)")
            SingletonPlayerWebView.shared.loadVideo(videoId: self.videoId)
        }

        return container
    }

    func updateUIView(_ container: UIView, context _: Context) {
        self.logger.info("PersistentPlayerView.updateUIView for videoId: \(self.videoId)")

        // Ensure WebView is in this container
        let webView = SingletonPlayerWebView.shared.getWebView(
            webKitManager: self.webKitManager,
            playerManager: playerManager
        )

        if webView.superview !== container {
            self.logger.info("Re-parenting WebView to current container")
            webView.removeFromSuperview()
            webView.frame = container.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(webView)
        }

        webView.frame = container.bounds

        // Load new video if changed
        SingletonPlayerWebView.shared.loadVideo(videoId: self.videoId)
    }
}
#endif

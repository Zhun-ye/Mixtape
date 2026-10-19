import SwiftUI
import WebKit
import FactoryKit

/// WebView for Google login.
#if os(macOS)
struct LoginWebView: NSViewRepresentable {
    @Injected(\.webKitManager) private var webKitManager

    /// Callback when navigation completes.
    var onNavigationToYouTubeMusic: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationToYouTubeMusic: self.onNavigationToYouTubeMusic)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = self.webKitManager.createWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = WebKitManager.userAgent

        // Load login page
        if let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Den%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        // No updates needed
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigationToYouTubeMusic: (() -> Void)?

        init(onNavigationToYouTubeMusic: (() -> Void)?) {
            self.onNavigationToYouTubeMusic = onNavigationToYouTubeMusic
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            // Check if we've navigated to music.youtube.com
            if let url = webView.url,
               url.host?.contains("music.youtube.com") == true
            {
                self.onNavigationToYouTubeMusic?()
            }
        }
    }
}
#else
struct LoginWebView: UIViewRepresentable {
    @Injected(\.webKitManager) private var webKitManager

    /// Callback when navigation completes.
    var onNavigationToYouTubeMusic: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationToYouTubeMusic: self.onNavigationToYouTubeMusic)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = self.webKitManager.createWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = WebKitManager.userAgent

        // Load login page
        if let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Den%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) {
        // No updates needed
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigationToYouTubeMusic: (() -> Void)?

        init(onNavigationToYouTubeMusic: (() -> Void)?) {
            self.onNavigationToYouTubeMusic = onNavigationToYouTubeMusic
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            // Check if we've navigated to music.youtube.com
            if let url = webView.url,
               url.host?.contains("music.youtube.com") == true
            {
                self.onNavigationToYouTubeMusic?()
            }
        }
    }
}
#endif

#Preview {
    LoginWebView()
        .frame(width: 500, height: 600)
}

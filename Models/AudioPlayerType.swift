//
//  AudioPlayerType.swift
//  Mixtape
//
import SwiftUI
import Foundation

/// Audio player type for YouTube Music playback.
enum AudioPlayerType: String, CaseIterable, Identifiable, Sendable {
    case webView = "webview"
    case native = "native"
    case vlc = "vlc"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .webView: "Web Player"
        case .native: "Native Player"
        case .vlc: "VLC Player"
        }
    }

    var localizedName: LocalizedStringKey {
        switch self {
        case .webView: "Web Player"
        case .native: "Native Player"
        case .vlc: "VLC Player"
        }
    }

    /// Available player types for the current platform.
    /// iOS does not support WebView player.
    static var availableCases: [AudioPlayerType] {
        #if os(iOS)
        [.native, .vlc]
        #else
        allCases
        #endif
    }
}

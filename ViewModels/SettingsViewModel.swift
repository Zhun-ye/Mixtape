import Foundation
import Observation
import FactoryKit
import SwiftUI

/// View model for the Settings view.
@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - Dependencies

    @ObservationIgnored
    @Injected(\.authService) private var authService

    @ObservationIgnored
    @Injected(\.playerManager) private var playerManager

    // MARK: - State

    /// App settings.
    var settings = AppDefaults.shared

    /// Whether login sheet is shown.
    var showLoginSheet = false

    /// Whether player is being switched.
    var isSwitchingPlayer = false

    // MARK: - Computed Properties

    /// Text to display for account status.
    var accountDisplayText: String {
        if authService.state.isLoggedIn {
            return settings.accountInfo?.name ?? "Account"
        } else {
            return "Account"
        }
    }

    /// Whether user is currently logged in.
    var isLoggedIn: Bool {
        self.authService.state.isLoggedIn
    }

    /// App version string.
    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    /// Footer text for playback section.
    var playbackFooterText: LocalizedStringKey {
        switch self.playerManager.currentPlayerType {
        case .webView:
            "Audio Quality: Very High (300kbps Opus with YouTube Premium)."
        case .native:
            "Audio Quality: Normal (130kbps AAC)."
        case .vlc:
            "Audio Quality: High (160kbps Opus)."
        }
    }

    /// Current player type.
    var currentPlayerType: AudioPlayerType {
        self.playerManager.currentPlayerType
    }

    // MARK: - Actions

    /// Sign out the current user.
    func signOut() async {
        await self.authService.signOut()
    }

    /// Show the login sheet.
    func showLogin() {
        self.showLoginSheet = true
    }

    /// Switch to a different audio player.
    func switchPlayer(to playerType: AudioPlayerType) async {
        self.isSwitchingPlayer = true
        await self.playerManager.switchPlayer(to: playerType)
        self.isSwitchingPlayer = false
    }

    /// Reset all app defaults to initial values.
    func resetDefaults() {
        settings.resetAllDefaults()
    }
}

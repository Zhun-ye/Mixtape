#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import FactoryKit

// MARK: - MixtapeApp

/// Main entry point for the Mixtape application.
@main
struct MixtapeApp: App {
    #if os(macOS)
    /// App delegate for lifecycle management (background playback).
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #else
    /// iOS app delegate for audio session configuration.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    /// Player service for command menu access (macOS).
    @Injected(\.playerManager) private var playerManager

    /// Whether the command bar is visible.
    @State private var showCommandBar = false

    /// Root coordinator for YTMusic mode.
    @State private var appCoordinator = AppCoordinator()

    /// Observe content language changes to update locale.
    @AppStorage(AppDefaults.Keys.contentLanguage) private var contentLanguage: String = ContentLanguage.systemDefault.rawValue

    /// Current locale based on content language setting.
    private var appLocale: Locale {
        Locale(identifier: contentLanguage)
    }

    var body: some Scene {
        WindowGroup {
            AppCoordinatorView(coordinator: appCoordinator)
                .environment(\.navigationSelection, $appCoordinator.navigationSelection)
                .environment(\.showCommandBar, $showCommandBar)
                .environment(\.locale, appLocale)
        }
        #if os(macOS)
        .commands {
            // Playback commands
            CommandMenu(localized("Playback")) {
                // Play/Pause - Space
                Button(localized(playerManager.isPlaying ? "Pause" : "Play")) {
                    Task {
                        await playerManager.playPause()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(playerManager.currentTrack == nil && playerManager.pendingPlayVideoId == nil)

                Divider()

                // Next Track - ⌘→
                Button(localized("Next")) {
                    Task {
                        await playerManager.next()
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                // Previous Track - ⌘←
                Button(localized("Previous")) {
                    Task {
                        await playerManager.previous()
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                // Volume Up - ⌘↑
                Button(localized("Volume Up")) {
                    Task {
                        await playerManager.setVolume(min(1.0, playerManager.volume + 0.1))
                    }
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                // Volume Down - ⌘↓
                Button(localized("Volume Down")) {
                    Task {
                        await playerManager.setVolume(max(0.0, playerManager.volume - 0.1))
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                // Mute - ⌘⇧M
                Button(localized(playerManager.isMuted ? "Unmute" : "Mute")) {
                    Task {
                        await playerManager.toggleMute()
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                // Shuffle - ⌘S
                Button(localized(playerManager.shuffleEnabled ? "Shuffle Off" : "Shuffle On")) {
                    playerManager.toggleShuffle()
                }
                .keyboardShortcut("s", modifiers: .command)

                // Repeat - ⌘R
                Button(repeatModeLabel) {
                    playerManager.cycleRepeatMode()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                // Lyrics - ⌘L
                Button(localized(playerManager.showLyrics ? "Hide Lyrics" : "Show Lyrics")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        playerManager.showLyrics.toggle()
                    }
                }
                .keyboardShortcut("l", modifiers: .command)
            }

            // Navigation commands - replace default sidebar toggle
            CommandGroup(replacing: .sidebar) {
                // Home - ⌘1
                Button(localized("Home")) {
                    appCoordinator.navigationSelection = .home
                }
                .keyboardShortcut("1", modifiers: .command)

                // Explore - ⌘2
                Button(localized("Explore")) {
                    appCoordinator.navigationSelection = .explore
                }
                .keyboardShortcut("2", modifiers: .command)

                // Library - ⌘3
                Button(localized("Library")) {
                    appCoordinator.navigationSelection = .library
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                // Search - ⌘F
                Button(localized("Search")) {
                    appCoordinator.navigationSelection = .search
                    // Trigger focus after a brief delay to allow view to appear
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        appCoordinator.searchFocusTrigger = true
                    }
                }
                .keyboardShortcut("f", modifiers: .command)

                // Command Bar - ⌘K
                Button(localized("Command Bar")) {
                    showCommandBar = true
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(viewModel: appCoordinator.settingsCoordinator.settingsViewModel)
                .environment(\.locale, appLocale)
        }
        .defaultSize(width: 450, height: 600)
        #endif
    }

    #if os(macOS)
    /// Localizes a string key using the app's content language setting.
    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: appLocale)
    }

    /// Label for repeat mode menu item.
    private var repeatModeLabel: String {
        switch playerManager.repeatMode {
        case .off:
            localized("Repeat All")
        case .all:
            localized("Repeat One")
        case .one:
            localized("Repeat Off")
        }
    }
    #endif
}

// MARK: - NavigationSelectionKey

/// Environment key for navigation selection.
struct NavigationSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationItem?> = .constant(nil)
}

extension EnvironmentValues {
    var navigationSelection: Binding<NavigationItem?> {
        get { self[NavigationSelectionKey.self] }
        set { self[NavigationSelectionKey.self] = newValue }
    }
}

// MARK: - CommandBarVisibilityKey

/// Environment key for command bar visibility.
struct CommandBarVisibilityKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var showCommandBar: Binding<Bool> {
        get { self[CommandBarVisibilityKey.self] }
        set { self[CommandBarVisibilityKey.self] = newValue }
    }
}

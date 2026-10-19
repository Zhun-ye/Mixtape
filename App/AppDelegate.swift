#if os(macOS)
import AppKit
import UserNotifications
#else
import UIKit
#endif

// MARK: - AppDelegate

#if os(macOS)
/// App delegate to control application lifecycle behavior.
/// Keeps the app running when windows are closed so audio playback continues.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Set up notification center delegate to show notifications in foreground
        UNUserNotificationCenter.current().delegate = self

        // Set up window delegate to intercept close and hide instead
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.delegate = self
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }

    /// Keep app running when the window is closed (for background audio).
    /// Use Cmd+Q to fully quit.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let playPauseItem = NSMenuItem(
            title: "Play/Pause",
            action: #selector(dockMenuPlayPause),
            keyEquivalent: ""
        )
        playPauseItem.target = self
        menu.addItem(playPauseItem)

        let nextItem = NSMenuItem(
            title: "Next Track",
            action: #selector(dockMenuNext),
            keyEquivalent: ""
        )
        nextItem.target = self
        menu.addItem(nextItem)

        let previousItem = NSMenuItem(
            title: "Previous Track",
            action: #selector(dockMenuPrevious),
            keyEquivalent: ""
        )
        previousItem.target = self
        menu.addItem(previousItem)

        return menu
    }

    @objc private func dockMenuPlayPause() {
        SingletonPlayerWebView.shared.playPause()
    }

    @objc private func dockMenuNext() {
        SingletonPlayerWebView.shared.next()
    }

    @objc private func dockMenuPrevious() {
        SingletonPlayerWebView.shared.previous()
    }

}

// MARK: UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show notifications even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound (if any) even when app is in foreground
        completionHandler([.banner])
    }
}
#else
// MARK: - iOS AppDelegate

/// iOS app delegate. Audio session is configured by PlayerManager.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Stored completion handler for background URL session events.
    var backgroundSessionCompletionHandler: (() -> Void)?

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Store the completion handler. DownloadManager's session delegate
        // will call it when all events have been delivered.
        backgroundSessionCompletionHandler = completionHandler
    }
}
#endif

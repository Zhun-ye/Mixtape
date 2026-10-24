import Foundation
import os

/// Centralized logging for the Music app.
/// All loggers are nonisolated as os.Logger is thread-safe.
nonisolated enum DiagnosticsLogger {
    /// Logger for authentication-related events.
    static let auth = Logger(subsystem: "com.alexcding.mixtape", category: "Auth")

    /// Logger for API-related events.
    static let api = Logger(subsystem: "com.alexcding.mixtape", category: "API")

    /// Logger for WebKit-related events.
    static let webKit = Logger(subsystem: "com.alexcding.mixtape", category: "WebKit")

    /// Logger for player-related events.
    static let player = Logger(subsystem: "com.alexcding.mixtape", category: "Player")

    /// Logger for UI-related events.
    static let ui = Logger(subsystem: "com.alexcding.mixtape", category: "UI")

    /// Logger for notification-related events.
    static let notification = Logger(subsystem: "com.alexcding.mixtape", category: "Notification")

    /// Logger for AI/Foundation Models-related events.
    static let ai = Logger(subsystem: "com.alexcding.mixtape", category: "AI")

    /// Logger for download-related events.
    static let download = Logger(subsystem: "com.alexcding.mixtape", category: "Download")
}

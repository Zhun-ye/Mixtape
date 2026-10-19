import Foundation
import UserNotifications
import os

/// Posts silent local notifications when the current track changes.
@MainActor
final class NotificationService {
    private let playerManager: PlayerManager
    private let logger = DiagnosticsLogger.notification
    private var observationTask: Task<Void, Never>?
    private var lastNotifiedTrackId: String?

    init(playerManager: PlayerManager) {
        self.playerManager = playerManager
        self.requestAuthorization()
        self.startObserving()
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert])
                self.logger.info("Notification authorization: \(granted)")
            } catch {
                self.logger.error("Notification authorization failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Observation

    private func startObserving() {
        #if os(macOS)
        self.observationTask = Task { [weak self] in
            guard let self else { return }
            var previousTrack: Song?

            while !Task.isCancelled {
                let currentTrack = self.playerManager.currentTrack

                // Only notify on actual track changes with valid title
                if let track = currentTrack,
                   track.id != previousTrack?.id,
                   track.id != self.lastNotifiedTrackId,
                   track.title != "Loading...",
                   AppDefaults.shared.showNowPlayingNotifications
                {
                    await self.postTrackNotification(track)
                    self.lastNotifiedTrackId = track.id
                }

                previousTrack = currentTrack
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        #endif
    }

    // MARK: - Notification

    private func postTrackNotification(_ track: Song) async {
        let content = UNMutableNotificationContent()
        content.title = track.title
        content.body = track.artistsDisplay.isEmpty ? "Unknown Artist" : track.artistsDisplay
        content.sound = nil // Silent notification

        // Add artwork attachment
        if let thumbnailURL = track.thumbnailURL,
           let attachment = await downloadAttachment(from: thumbnailURL, id: track.id) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: "track-change-\(track.id)",
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            self.logger.debug("Posted notification for: \(track.title)")
        } catch {
            self.logger.error("Failed to post notification: \(error.localizedDescription)")
        }
    }

    private func downloadAttachment(from url: URL, id: String) async -> UNNotificationAttachment? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("\(id).jpg")
            try data.write(to: fileURL)
            let attachment = try UNNotificationAttachment(identifier: id, url: fileURL, options: nil)
            return attachment
        } catch {
            self.logger.error("Failed to download artwork: \(error.localizedDescription)")
            return nil
        }
    }

    func stopObserving() {
        self.observationTask?.cancel()
        self.observationTask = nil
    }
}

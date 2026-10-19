import AVFoundation
import FactoryKit
import Foundation
import Observation
import os
#if os(iOS)
import UIKit
#endif

// MARK: - DownloadManager

/// Manages offline song downloads using background `URLSession`.
///
/// Downloads direct AAC audio streams as `.m4a` files that `AVPlayer` can play
/// natively offline. Persists a JSON catalog following the `FavoritesManager` pattern.
@MainActor
@Observable
final class DownloadManager: NSObject, DownloadManagerProtocol {

    // MARK: - Observable State

    /// Completed downloads available for offline playback.
    private(set) var downloads: [DownloadedSong] = []

    /// Active and pending download tasks.
    private(set) var activeTasks: [DownloadTaskInfo] = []

    /// Saved playlists/albums with their associated song IDs.
    private(set) var playlists: [DownloadedPlaylist] = []

    /// Whether any download is currently in progress.
    var isDownloading: Bool {
        activeTasks.contains { $0.state == .downloading || $0.state == .fetchingURL }
    }

    /// Songs not associated with any downloaded playlist.
    var looseSongs: [DownloadedSong] {
        let playlistSongIds = Set(playlists.flatMap(\.songIds))
        return downloads.filter { !playlistSongIds.contains($0.id) }
    }

    // MARK: - Constants

    private static let maxConcurrentDownloads = 3
    private static let sessionIdentifier = "com.alexcding.mixtape.downloads"

    // MARK: - Private Properties

    private let logger = DiagnosticsLogger.download
    private let skipPersistence: Bool

    @ObservationIgnored
    private let streamFetcher = StreamFetcher()

    /// Maps `URLSessionDownloadTask.taskIdentifier` → videoId for delegate callbacks.
    @ObservationIgnored
    private var taskIdentifierToVideoId: [Int: String] = [:]

    /// Maps videoId → file extension (e.g., "m4a" or "opus") for the current download.
    @ObservationIgnored
    private var videoIdToFileExtension: [String: String] = [:]

    /// Background download session.
    @ObservationIgnored
    private var _downloadSession: URLSession?

    /// Returns (or creates) the background download session.
    private func getDownloadSession() -> URLSession {
        if let session = _downloadSession { return session }
        let config = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        let session = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: .main
        )
        _downloadSession = session
        return session
    }

    // MARK: - Persistence

    private static var catalogURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let mixtapeDir = appSupport.appendingPathComponent("Mixtape", isDirectory: true)
        return mixtapeDir.appendingPathComponent("downloads-catalog.json")
    }

    private static var audioDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Mixtape", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
    }

    private static var thumbnailsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Mixtape", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)
    }

    // MARK: - Initialization

    override init() {
        self.skipPersistence = false
        super.init()
        loadCatalog()
        reconcileWithSession()
    }

    /// Testing initializer that skips persistence and session setup.
    init(skipPersistence: Bool) {
        self.skipPersistence = skipPersistence
        super.init()
        if !skipPersistence {
            loadCatalog()
            reconcileWithSession()
        }
    }

    // MARK: - Query Methods

    func isDownloaded(videoId: String) -> Bool {
        downloads.contains { $0.id == videoId }
    }

    func downloadState(for videoId: String) -> DownloadTaskInfo.DownloadState? {
        if isDownloaded(videoId: videoId) { return .completed }
        return activeTasks.first { $0.id == videoId }?.state
    }

    func progress(for videoId: String) -> Double {
        activeTasks.first { $0.id == videoId }?.progress ?? 0
    }

    func localAsset(for videoId: String) -> AVURLAsset? {
        guard let fileURL = localFileURL(for: videoId) else { return nil }
        return AVURLAsset(url: fileURL)
    }

    func localFileURL(for videoId: String) -> URL? {
        guard let downloaded = downloads.first(where: { $0.id == videoId }) else { return nil }
        let fileURL = Self.audioDirectory.appendingPathComponent(downloaded.assetLocation)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.warning("Downloaded audio missing at: \(downloaded.assetLocation)")
            return nil
        }
        return fileURL
    }

    // MARK: - Download Actions

    func download(song: Song) async {
        // Skip if already downloaded or in queue
        guard !isDownloaded(videoId: song.videoId),
              !activeTasks.contains(where: { $0.id == song.videoId })
        else {
            logger.info("Song already downloaded or queued: \(song.videoId)")
            return
        }

        let task = DownloadTaskInfo(
            id: song.videoId,
            song: song,
            state: .pending,
            progress: 0,
            error: nil,
            addedAt: Date()
        )
        activeTasks.append(task)
        saveCatalog()
        logger.info("Queued download: \(song.title)")

        await processQueue()
    }

    func downloadAll(songs: [Song]) async {
        for song in songs {
            guard !isDownloaded(videoId: song.videoId),
                  !activeTasks.contains(where: { $0.id == song.videoId })
            else { continue }

            let task = DownloadTaskInfo(
                id: song.videoId,
                song: song,
                state: .pending,
                progress: 0,
                error: nil,
                addedAt: Date()
            )
            activeTasks.append(task)
        }
        saveCatalog()
        logger.info("Queued batch download: \(songs.count) songs")

        await processQueue()
    }

    func downloadPlaylist(_ playlist: Playlist, songs: [Song]) async {
        let songIds = songs.map(\.videoId)

        // Create or update the playlist entry
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            // Merge new song IDs (preserve order, avoid duplicates)
            let existing = Set(playlists[index].songIds)
            let newIds = songIds.filter { !existing.contains($0) }
            playlists[index].songIds.append(contentsOf: newIds)
        } else {
            let downloadedPlaylist = DownloadedPlaylist(
                id: playlist.id,
                title: playlist.title,
                thumbnailURL: playlist.thumbnailURL,
                author: playlist.author,
                isAlbum: playlist.isAlbum,
                songIds: songIds,
                downloadedAt: Date()
            )
            playlists.append(downloadedPlaylist)
        }

        // Queue the actual song downloads
        await downloadAll(songs: songs)
    }

    func deletePlaylist(playlistId: String) {
        guard let playlist = playlists.first(where: { $0.id == playlistId }) else { return }

        // Find songs unique to this playlist (not in other playlists)
        let otherPlaylistSongIds = Set(
            playlists.filter { $0.id != playlistId }.flatMap(\.songIds)
        )
        let uniqueSongIds = playlist.songIds.filter { !otherPlaylistSongIds.contains($0) }

        // Delete songs that aren't shared with other playlists
        for videoId in uniqueSongIds {
            deleteDownload(videoId: videoId)
        }

        playlists.removeAll { $0.id == playlistId }
        saveCatalog()
        logger.info("Deleted playlist: \(playlist.title) (\(uniqueSongIds.count) songs removed)")
    }

    func cancel(videoId: String) {
        if let taskId = taskIdentifierToVideoId.first(where: { $0.value == videoId })?.key {
            getDownloadSession().getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == taskId }?.cancel()
            }
            taskIdentifierToVideoId.removeValue(forKey: taskId)
        }

        activeTasks.removeAll { $0.id == videoId }
        saveCatalog()
        logger.info("Cancelled download: \(videoId)")

        Task { await processQueue() }
    }

    func retry(videoId: String) async {
        guard let index = activeTasks.firstIndex(where: { $0.id == videoId && $0.state == .failed }) else { return }
        activeTasks[index].state = .pending
        activeTasks[index].progress = 0
        activeTasks[index].error = nil
        saveCatalog()
        logger.info("Retrying download: \(videoId)")

        await processQueue()
    }

    func deleteDownload(videoId: String) {
        guard let downloaded = downloads.first(where: { $0.id == videoId }) else { return }

        // Remove the audio file
        let audioURL = Self.audioDirectory.appendingPathComponent(downloaded.assetLocation)
        try? FileManager.default.removeItem(at: audioURL)

        // Remove cached thumbnail
        if let thumbFile = downloaded.thumbnailFileName {
            let thumbURL = Self.thumbnailsDirectory.appendingPathComponent(thumbFile)
            try? FileManager.default.removeItem(at: thumbURL)
        }

        downloads.removeAll { $0.id == videoId }
        saveCatalog()
        logger.info("Deleted download: \(videoId)")
    }

    func deleteAllDownloads() {
        // Cancel all active session tasks
        getDownloadSession().getAllTasks { tasks in
            for task in tasks { task.cancel() }
        }
        taskIdentifierToVideoId.removeAll()
        activeTasks.removeAll()

        // Delete all audio files and thumbnails
        let fm = FileManager.default
        try? fm.removeItem(at: Self.audioDirectory)
        try? fm.removeItem(at: Self.thumbnailsDirectory)

        downloads.removeAll()
        playlists.removeAll()
        saveCatalog()
        logger.info("Deleted all downloads")
    }

    // MARK: - Queue Processing

    private func processQueue() async {
        let activeCount = activeTasks.filter { $0.state == .downloading || $0.state == .fetchingURL }.count
        let slotsAvailable = Self.maxConcurrentDownloads - activeCount

        guard slotsAvailable > 0 else { return }

        let pending = activeTasks.filter { $0.state == .pending }
        let toStart = pending.prefix(slotsAvailable)

        for task in toStart {
            await startDownload(videoId: task.id)
        }
    }

    private func startDownload(videoId: String) async {
        guard let index = activeTasks.firstIndex(where: { $0.id == videoId }) else { return }

        activeTasks[index].state = .fetchingURL
        saveCatalog()

        // Select format based on current player type:
        // VLC supports Opus (higher quality at lower bitrate), native/webView needs AAC
        let useVLCFormat = AppDefaults.shared.audioPlayer == .vlc
        let result = await streamFetcher.fetchStream(videoId: videoId) { response in
            useVLCFormat ? response.bestVLCFormat() : response.bestHighQualityFormat()
        }

        switch result {
        case .success(let streamResult):
            let format = streamResult.format
            let bitrateKbps = (format.bitrate ?? 0) / 1000
            logger.info("Downloading \(videoId): itag=\(format.itag) \(bitrateKbps)kbps via \(streamResult.client.name), contentLength=\(format.contentLength ?? "unknown")")

            // Append range parameter to avoid YouTube throttling (per InnerTune/OuterTune)
            var finalURLString = streamResult.streamURL.absoluteString
            if let contentLength = format.contentLength {
                finalURLString += "&range=0-\(contentLength)"
            }

            guard let downloadURL = URL(string: finalURLString) else {
                logger.error("Failed to construct download URL for \(videoId)")
                if let index = activeTasks.firstIndex(where: { $0.id == videoId }) {
                    activeTasks[index].state = .failed
                    activeTasks[index].error = "Invalid stream URL"
                    saveCatalog()
                }
                await processQueue()
                return
            }

            // Determine file extension from mime type
            let fileExtension = format.mimeType.hasPrefix("audio/webm") ? "opus" : "m4a"
            videoIdToFileExtension[videoId] = fileExtension

            beginFileDownload(videoId: videoId, streamURL: downloadURL, userAgent: streamResult.client.userAgent)

        case .failure(let error):
            logger.error("Failed to fetch stream for \(videoId): \(error.localizedDescription)")
            if let index = activeTasks.firstIndex(where: { $0.id == videoId }) {
                activeTasks[index].state = .failed
                activeTasks[index].error = error.localizedDescription
                saveCatalog()
            }
            await processQueue()
        }
    }

    private func beginFileDownload(videoId: String, streamURL: URL, userAgent: String) {
        guard let index = activeTasks.firstIndex(where: { $0.id == videoId }) else { return }

        var request = URLRequest(url: streamURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")

        let task = getDownloadSession().downloadTask(with: request)
        taskIdentifierToVideoId[task.taskIdentifier] = videoId
        activeTasks[index].state = .downloading
        saveCatalog()

        task.resume()
        logger.info("Started audio download for: \(self.activeTasks[index].song.title)")
    }

    // MARK: - Session Reconciliation

    /// Reconciles persisted catalog with actual session tasks after app relaunch.
    private func reconcileWithSession() {
        guard !skipPersistence else { return }

        getDownloadSession().getAllTasks { [weak self] tasks in
            MainActor.assumeIsolated {
                guard let self else { return }

                let activeTaskIds = Set(tasks.compactMap { task -> Int? in
                    task.state == .running || task.state == .suspended ? task.taskIdentifier : nil
                })

                // Reset tasks that claim to be downloading but have no matching session task
                for i in self.activeTasks.indices {
                    if self.activeTasks[i].state == .downloading {
                        let hasMatchingTask = self.taskIdentifierToVideoId
                            .filter { activeTaskIds.contains($0.key) }
                            .values
                            .contains(self.activeTasks[i].id)

                        if !hasMatchingTask {
                            self.activeTasks[i].state = .pending
                            self.activeTasks[i].progress = 0
                        }
                    }
                }

                self.saveCatalog()
                self.logger.info("Session reconciled: \(tasks.count) active session tasks, \(self.activeTasks.count) catalog tasks")

                Task { await self.processQueue() }
            }
        }
    }

    // MARK: - Catalog Persistence

    private func loadCatalog() {
        do {
            guard FileManager.default.fileExists(atPath: Self.catalogURL.path) else {
                logger.debug("No download catalog found, starting fresh")
                return
            }
            let data = try Data(contentsOf: Self.catalogURL)
            let catalog = try JSONDecoder().decode(DownloadCatalog.self, from: data)
            downloads = catalog.downloads
            activeTasks = catalog.pendingTasks
            playlists = catalog.playlists
            logger.info("Loaded catalog: \(catalog.downloads.count) downloads, \(catalog.playlists.count) playlists, \(catalog.pendingTasks.count) pending")
        } catch {
            logger.error("Failed to load download catalog: \(error.localizedDescription)")
            downloads = []
            activeTasks = []
            playlists = []
        }
    }

    private func saveCatalog() {
        guard !skipPersistence else { return }

        let snapshot = DownloadCatalog(
            downloads: downloads,
            pendingTasks: activeTasks,
            playlists: playlists
        )
        let targetURL = Self.catalogURL
        let logger = self.logger

        do {
            let data = try JSONEncoder().encode(snapshot)
            Task.detached(priority: .utility) {
                do {
                    let directory = targetURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try data.write(to: targetURL, options: .atomic)
                    logger.debug("Saved download catalog")
                } catch {
                    logger.error("Failed to save download catalog: \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Failed to encode download catalog: \(error.localizedDescription)")
        }
    }

    // MARK: - Thumbnail Caching

    private func cacheThumbnail(for song: Song) async -> String? {
        guard let thumbnailURL = song.thumbnailURL else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: thumbnailURL)
            let fileName = "\(song.videoId).jpg"
            let dir = Self.thumbnailsDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)
            return fileName
        } catch {
            logger.warning("Failed to cache thumbnail for \(song.videoId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Storage Info

    /// Total size of all downloaded assets in bytes.
    var totalDownloadSize: Int64 {
        downloads.reduce(0) { $0 + $1.fileSize }
    }

    /// Formatted total download size string.
    var totalDownloadSizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: totalDownloadSize, countStyle: .file)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier

        // Validate HTTP response before moving file
        let httpResponse = downloadTask.response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        let contentType = httpResponse?.mimeType ?? "unknown"

        MainActor.assumeIsolated {
            guard let videoId = taskIdentifierToVideoId[taskId] else {
                logger.warning("No videoId mapped for task \(taskId)")
                return
            }

            // Reject non-audio responses (e.g., error pages)
            if statusCode != 0 && (statusCode < 200 || statusCode >= 300) {
                logger.error("Download HTTP \(statusCode) for \(videoId)")
                if let index = activeTasks.firstIndex(where: { $0.id == videoId }) {
                    activeTasks[index].state = .failed
                    activeTasks[index].error = "Server returned HTTP \(statusCode)"
                    saveCatalog()
                }
                return
            }

            let ext = videoIdToFileExtension.removeValue(forKey: videoId) ?? "m4a"
            let fileName = "\(videoId).\(ext)"
            let destURL = Self.audioDirectory.appendingPathComponent(fileName)

            do {
                let dir = Self.audioDirectory
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }

                try FileManager.default.moveItem(at: location, to: destURL)
            } catch {
                logger.error("Failed to move downloaded file for \(videoId): \(error.localizedDescription)")
                if let index = activeTasks.firstIndex(where: { $0.id == videoId }) {
                    activeTasks[index].state = .failed
                    activeTasks[index].error = "Failed to save file: \(error.localizedDescription)"
                    saveCatalog()
                }
                return
            }

            // Get file size via resource values (more reliable than attributesOfItem)
            let fileSize: Int64
            if let values = try? destURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                fileSize = Int64(size)
            } else {
                fileSize = 0
            }

            logger.info("Audio saved: \(fileName) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)), type: \(contentType))")

            guard let index = activeTasks.firstIndex(where: { $0.id == videoId }) else { return }
            let song = activeTasks[index].song
            activeTasks.remove(at: index)

            let downloaded = DownloadedSong(
                id: videoId,
                song: song,
                assetLocation: fileName,
                fileSize: fileSize,
                downloadedAt: Date(),
                thumbnailFileName: nil
            )
            downloads.append(downloaded)
            saveCatalog()

            logger.info("Download completed: \(song.title) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))")

            // Cache thumbnail in background
            Task {
                if let thumbFile = await cacheThumbnail(for: song) {
                    if let dlIndex = downloads.firstIndex(where: { $0.id == videoId }) {
                        let existing = downloads[dlIndex]
                        downloads[dlIndex] = DownloadedSong(
                            id: existing.id,
                            song: existing.song,
                            assetLocation: existing.assetLocation,
                            fileSize: existing.fileSize,
                            downloadedAt: existing.downloadedAt,
                            thumbnailFileName: thumbFile
                        )
                        saveCatalog()
                    }
                }
            }

            Task { await processQueue() }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1.0)
        } else {
            progress = 0
        }

        MainActor.assumeIsolated {
            guard let videoId = taskIdentifierToVideoId[taskId] else { return }
            if let index = activeTasks.firstIndex(where: { $0.id == videoId }) {
                activeTasks[index].progress = progress
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        MainActor.assumeIsolated {
            guard let videoId = taskIdentifierToVideoId.removeValue(forKey: taskId) else { return }

            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                logger.info("Download cancelled for \(videoId)")
                activeTasks.removeAll { $0.id == videoId }
            } else {
                logger.error("Download failed for \(videoId): \(error.localizedDescription)")
                if let index = activeTasks.firstIndex(where: { $0.id == videoId }) {
                    activeTasks[index].state = .failed
                    activeTasks[index].error = error.localizedDescription
                }
            }

            saveCatalog()
            Task { await processQueue() }
        }
    }

    #if os(iOS)
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            logger.info("Background session finished delivering events")
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                  let handler = appDelegate.backgroundSessionCompletionHandler else { return }
            appDelegate.backgroundSessionCompletionHandler = nil
            handler()
        }
    }
    #endif
}

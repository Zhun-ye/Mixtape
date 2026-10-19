//
//  AppDefaults.swift
//  Mixtape
//

import FactoryKit
import Foundation
import Observation

/// Centralized app defaults storage.
@MainActor
@Observable
final class AppDefaults: @unchecked Sendable {

    enum Keys {
        static let isDefaultsInitialized = "is_defaults_initialized"
        static let showNowPlayingNotifications = "settings.showNowPlayingNotifications"
        static let contentLanguage = "settings.contentLanguage"
        static let contentRegion = "settings.contentRegion"
        static let audioPlayer = "settings.audioPlayer"
        static let libraryArtistsDisplayMode = "library.artistsDisplayMode"
        static let libraryArtistsSortOrder = "library.artistsSortOrder"
        static let accountInfo = "account.info"
        static let savedQueue = "player.savedQueue"
        static let savedQueueIndex = "player.savedQueueIndex"
    }

    static let shared = AppDefaults()

    private let defaults: UserDefaults

    private init() {
        self.defaults = UserDefaults.standard

        // Initialize settings first (required by @Observable)
        self.showNowPlayingNotifications = defaults.object(forKey: Keys.showNowPlayingNotifications) as? Bool ?? true

        if let languageRaw = defaults.string(forKey: Keys.contentLanguage) {
            // Migrate old "zh" value to "zh-Hans"
            let migratedRaw = languageRaw == "zh" ? "zh-Hans" : languageRaw
            if let language = ContentLanguage(rawValue: migratedRaw) {
                self.contentLanguage = language
            } else {
                self.contentLanguage = .systemDefault
            }
        } else {
            self.contentLanguage = .systemDefault
        }

        if let regionRaw = defaults.string(forKey: Keys.contentRegion),
           let region = ContentRegion(rawValue: regionRaw)
        {
            self.contentRegion = region
        } else {
            self.contentRegion = .systemDefault
        }

        // Mark defaults as initialized after all stored properties are set
        if !defaults.bool(forKey: Keys.isDefaultsInitialized) {
            defaults.set(true, forKey: Keys.isDefaultsInitialized)
        }
    }

    var isDefaultsInitialized: Bool {
        get { defaults.bool(forKey: Keys.isDefaultsInitialized) }
        set { defaults.set(newValue, forKey: Keys.isDefaultsInitialized) }
    }

    // MARK: - Settings

    /// Whether to show system notifications when the track changes.
    var showNowPlayingNotifications: Bool {
        didSet {
            defaults.set(self.showNowPlayingNotifications, forKey: Keys.showNowPlayingNotifications)
        }
    }

    /// Content language for API responses (hl parameter).
    var contentLanguage: ContentLanguage {
        didSet {
            defaults.set(self.contentLanguage.rawValue, forKey: Keys.contentLanguage)
        }
    }

    /// Content region for API responses (gl parameter).
    var contentRegion: ContentRegion {
        didSet {
            defaults.set(self.contentRegion.rawValue, forKey: Keys.contentRegion)
        }
    }

    /// Audio player type (webView or native).
    var audioPlayer: AudioPlayerType {
        get {
            if let raw = defaults.string(forKey: Keys.audioPlayer),
               let player = AudioPlayerType(rawValue: raw) {
                return player
            }
            #if os(iOS)
            return .native
            #else
            return .webView
            #endif
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.audioPlayer)
        }
    }

    // MARK: - Library Settings

    /// Display mode for library artists view.
    var libraryArtistsDisplayMode: LibraryDisplayMode {
        get {
            if let raw = defaults.string(forKey: Keys.libraryArtistsDisplayMode),
               let mode = LibraryDisplayMode(rawValue: raw) {
                return mode
            }
            return .list
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.libraryArtistsDisplayMode)
        }
    }

    /// Sort order for library artists view.
    var libraryArtistsSortOrder: LibrarySortOrder {
        get {
            if let raw = defaults.string(forKey: Keys.libraryArtistsSortOrder),
               let order = LibrarySortOrder(rawValue: raw) {
                return order
            }
            return .recentlyAdded
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.libraryArtistsSortOrder)
        }
    }

    // MARK: - Account

    /// The persisted account information (fetched on login).
    var accountInfo: AccountInfo? {
        get {
            guard let raw = defaults.string(forKey: Keys.accountInfo) else { return nil }
            return AccountInfo(rawValue: raw)
        }
        set {
            if let info = newValue {
                defaults.set(info.rawValue, forKey: Keys.accountInfo)
            } else {
                defaults.removeObject(forKey: Keys.accountInfo)
            }
        }
    }

    // MARK: - Player State

    /// The persisted playback queue (restored on app launch).
    var savedQueue: [Song]? {
        get {
            guard let data = defaults.data(forKey: Keys.savedQueue) else { return nil }
            return try? JSONDecoder().decode([Song].self, from: data)
        }
        set {
            if let queue = newValue, let data = try? JSONEncoder().encode(queue) {
                defaults.set(data, forKey: Keys.savedQueue)
            } else {
                defaults.removeObject(forKey: Keys.savedQueue)
            }
        }
    }

    /// The persisted queue index (restored on app launch).
    var savedQueueIndex: Int {
        get { defaults.integer(forKey: Keys.savedQueueIndex) }
        set { defaults.set(newValue, forKey: Keys.savedQueueIndex) }
    }

    // MARK: - Debug

    /// Resets all app defaults to their initial values.
    func resetAllDefaults() {
        // Remove all keys
        for key in [
            Keys.isDefaultsInitialized,
            Keys.showNowPlayingNotifications,
            Keys.contentLanguage,
            Keys.contentRegion,
            Keys.audioPlayer,
            Keys.libraryArtistsDisplayMode,
            Keys.libraryArtistsSortOrder,
            Keys.accountInfo,
            Keys.savedQueue,
            Keys.savedQueueIndex
        ] {
            defaults.removeObject(forKey: key)
        }

        // Reset observable properties to defaults
        showNowPlayingNotifications = true
        contentLanguage = .systemDefault
        contentRegion = .systemDefault
    }
}

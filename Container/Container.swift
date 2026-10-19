@preconcurrency import FactoryKit

extension Container {

    @MainActor
    var authService: Factory<AuthService> {
        self { MainActor.assumeIsolated { AuthService(webKitManager: self.webKitManager()) } }
            .scope(.singleton)
    }

    @MainActor
    var webKitManager: Factory<WebKitManager> {
        self { MainActor.assumeIsolated { WebKitManager() } }
            .scope(.singleton)
    }

    @MainActor
    var ytMusicWebPlayer: Factory<YTMusicWebPlayer> {
        self { MainActor.assumeIsolated { YTMusicWebPlayer() } }
            .scope(.singleton)
    }

    @MainActor
    var ytMusicNativePlayer: Factory<YTMusicNativePlayer> {
        self { MainActor.assumeIsolated { YTMusicNativePlayer() } }
            .scope(.singleton)
    }

    @MainActor
    var vlcMusicPlayer: Factory<VLCMusicPlayer> {
        self { MainActor.assumeIsolated { VLCMusicPlayer() } }
            .scope(.singleton)
    }

    /// Returns the currently selected audio player based on user settings.
    @MainActor
    var ytMusicPlayer: Factory<YTMusicPlayer> {
        self {
            MainActor.assumeIsolated {
                switch AppDefaults.shared.audioPlayer {
                case .webView:
                    return self.ytMusicWebPlayer()
                case .native:
                    return self.ytMusicNativePlayer()
                case .vlc:
                    return self.vlcMusicPlayer()
                }
            }
        }
    }

    @MainActor
    var playerManager: Factory<PlayerManager> {
        self {
            MainActor.assumeIsolated {
                let service = PlayerManager(ytMusicClient: self.ytMusicClient())
                service.setAudioPlayer(self.ytMusicPlayer())
                return service
            }
        }
        .scope(.singleton)
    }

    @MainActor
    var ytMusicClient: Factory<YTMusicClientProtocol> {
        self {
            MainActor.assumeIsolated {
                YTMusicClient(
                    authService: self.authService(),
                    webKitManager: self.webKitManager()
                )
            }
        }
        .scope(.singleton)
    }

    @MainActor
    var notificationService: Factory<NotificationService> {
        self { MainActor.assumeIsolated { NotificationService(playerManager: self.playerManager()) } }
            .scope(.singleton)
    }

    @MainActor
    var songLikeStatusManager: Factory<SongLikeStatusManager> {
        self { MainActor.assumeIsolated { SongLikeStatusManager() } }
            .scope(.singleton)
    }

    @MainActor
    var libraryRepository: Factory<LibraryRepositoryProtocol> {
        self { MainActor.assumeIsolated { LibraryRepository() } }
            .scope(.singleton)
    }

    @MainActor
    var downloadManager: Factory<DownloadManager> {
        self { MainActor.assumeIsolated { DownloadManager() } }
            .scope(.singleton)
    }

    @MainActor
    var networkMonitor: Factory<NetworkMonitor> {
        self { MainActor.assumeIsolated { NetworkMonitor() } }
            .scope(.singleton)
    }

}

import SwiftUI
import FactoryKit
import SwiftUINavigation
import Kingfisher

@MainActor
@Observable
final class AppCoordinator: HashableObject {
    // MARK: - State

    enum State: Equatable {
        case initializing
        case onboarding
        case ready
    }

    // MARK: - Services

    @ObservationIgnored
    @Injected(\.authService) var authService

    @ObservationIgnored
    @Injected(\.playerManager) var playerManager

    @ObservationIgnored
    @Injected(\.webKitManager) var webKitManager

    @ObservationIgnored
    @Injected(\.ytMusicClient) var ytMusicClient

    @ObservationIgnored
    @LazyInjected(\.notificationService) var notificationService

    @ObservationIgnored
    @Injected(\.libraryRepository) var libraryRepository

    // MARK: - Constants

    private static let navigationSelectionKey = "AppCoordinator.navigationSelection"
    private static let selectedPlaylistIdKey = "AppCoordinator.selectedPlaylistId"

    // MARK: - Properties

    private(set) var state: State = .initializing
    private var pendingPlaylistId: String?

    var navigationSelection: NavigationItem? {
        didSet {
            if case .libraryPlaylist(let playlist) = navigationSelection {
                selectedPlaylistViewModel = PlaylistDetailViewModel(playlist: playlist)
                UserDefaults.standard.set(playlist.id, forKey: Self.selectedPlaylistIdKey)
            } else {
                selectedPlaylistViewModel = nil
                UserDefaults.standard.removeObject(forKey: Self.selectedPlaylistIdKey)
            }
            persistNavigationSelection()
        }
    }

    private func persistNavigationSelection() {
        #if os(macOS)
        UserDefaults.standard.set(navigationSelection?.id, forKey: Self.navigationSelectionKey)
        #else
        // iOS only persists home, explore, and library
        switch navigationSelection {
        case .home, .explore, .library:
            UserDefaults.standard.set(navigationSelection?.id, forKey: Self.navigationSelectionKey)
        default:
            break
        }
        #endif
    }

    init() {
        if let savedId = UserDefaults.standard.string(forKey: Self.navigationSelectionKey) {
            #if os(macOS)
            if savedId.hasPrefix("playlist-") {
                // Store playlist ID to restore after library loads
                // Leave navigationSelection nil to show loading state
                pendingPlaylistId = UserDefaults.standard.string(forKey: Self.selectedPlaylistIdKey)
            } else if let item = NavigationItem(id: savedId) {
                navigationSelection = item
            } else {
                navigationSelection = .home
            }
            #else
            // iOS only persists home, explore, and library
            switch savedId {
            case "home", "explore", "library":
                navigationSelection = NavigationItem(id: savedId)
            default:
                navigationSelection = .home
            }
            #endif
        } else {
            navigationSelection = .home
        }

        setup()
    }

    /// Restores pending playlist selection after library data is available.
    func restorePendingPlaylistSelection(from playlists: [Playlist]) {
        guard let playlistId = pendingPlaylistId,
              let playlist = playlists.first(where: { $0.id == playlistId }) else {
            return
        }
        pendingPlaylistId = nil
        navigationSelection = .libraryPlaylist(playlist)
    }
    var showCommandBarSheet = false
    var showSettings = false
    var searchFocusTrigger = false

    // Selected playlist view model for library playlist tabs
    var selectedPlaylistViewModel: PlaylistDetailViewModel?

    // Child coordinators (lazily initialized)
    @ObservationIgnored
    lazy var homeCoordinator: HomeCoordinator = {
        let coordinator = HomeCoordinator()
        coordinator.delegate = self
        return coordinator
    }()

    @ObservationIgnored
    lazy var discoverCoordinator: DiscoveryCoordinator = {
        let coordinator = DiscoveryCoordinator()
        coordinator.delegate = self
        return coordinator
    }()

    @ObservationIgnored
    lazy var libraryCoordinator: LibraryCoordinator = {
        let coordinator = LibraryCoordinator()
        coordinator.delegate = self
        return coordinator
    }()

    @ObservationIgnored
    lazy var searchCoordinator: SearchCoordinator = {
        let coordinator = SearchCoordinator()
        coordinator.delegate = self
        return coordinator
    }()

    @ObservationIgnored
    lazy var settingsCoordinator = SettingsCoordinator()

    @ObservationIgnored
    lazy var playerViewModel: PlayerViewModel = {
        let vm = PlayerViewModel()
        vm.onNavigateToPlaylist = { [weak self] in
            guard let self, let playlist = playerManager.sourcePlaylist else { return }
            navigationSelection = .home
            navigateToPlaylist(playlist)
        }
        return vm
    }()

    // MARK: - Setup

    func setup() {
        configureImageCache()
        configureNowPlaying()
        _ = notificationService

        Task {
            await authService.checkLoginStatus()
            await FoundationModelsService.shared.warmup()
        }
    }

    private func configureImageCache() {
        // Limit memory cache to 100MB - prefer disk cache for most images
        ImageCache.default.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024

        // Limit disk cache to 1GB
        ImageCache.default.diskStorage.config.sizeLimit = 1024 * 1024 * 1024
    }

    // MARK: - Navigation

    func navigateToPlaylist(_ playlist: Playlist) {
        homeCoordinator.navigate(to: .playlist(playlist))
    }

    func navigateToArtist(_ artist: Artist) {
        homeCoordinator.navigate(to: .artist(artist))
    }

    func handleAuthStateChange(oldState: AuthService.State, newState: AuthService.State) {
        switch newState {
        case .initializing:
            state = .initializing
        case .loggedOut:
            state = .onboarding
        case .loggingIn:
            break
        case .loggedIn:
            state = .ready
        }
    }

    func handlePlaybackStarted(_ isPlaying: Bool) {
        if isPlaying, playerManager.showMiniPlayer {
            playerManager.confirmPlaybackStarted()
        }
    }

    func configureNowPlaying() {
        NowPlayingManager.shared.configure(playerManager: playerManager)
    }
}

// MARK: - CoordinatorDelegate

extension AppCoordinator: AppCoordinatorDelegate {
    func didRequestSettings() {
        showSettings = true
    }

    func didRequestSwitchToHome() {
        navigationSelection = .home
    }
}

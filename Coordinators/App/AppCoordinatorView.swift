import SwiftUI
import Kingfisher
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - AppCoordinatorView

/// Main application window with sidebar navigation and player bar.
struct AppCoordinatorView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.showCommandBar) private var showCommandBar
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    @State private var sidebarWidth: CGFloat = 250
    #if os(iOS)
    @Namespace private var playerNamespace
    @State private var showFullscreenPlayer = false
    @State private var playerBarAppearance = PlayerBarAppearance()
    #endif
    private var playerManager: PlayerManager { coordinator.playerManager }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            #if os(macOS)
            macOSMainContent()
                .playerViewModel(coordinator.playerViewModel)
            #else
            iOSMainContent()
            #endif

            // Persistent WebView - only present when using WebView player
            if playerManager.currentPlayerType == .webView,
               let videoId = playerManager.pendingPlayVideoId {
                miniPlayerOverlay(videoId: videoId)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: playerManager.showMiniPlayer)
        .overlay {
            if coordinator.showCommandBarSheet {
                commandBarOverlay()
            }
        }
        .onChange(of: showCommandBar.wrappedValue) { _, newValue in
            if newValue {
                coordinator.showCommandBarSheet = true
                showCommandBar.wrappedValue = false
            }
        }
        .onChange(of: coordinator.libraryCoordinator.libraryViewModel.playlists) { _, playlists in
            coordinator.restorePendingPlaylistSelection(from: playlists)
        }
    }

    // MARK: - Mini Player Overlay

    @ViewBuilder
    private func miniPlayerOverlay(videoId: String) -> some View {
        let showMiniPlayer = playerManager.showMiniPlayer

        PersistentPlayerView(
            videoId: videoId,
            isExpanded: showMiniPlayer,
            playerManager: coordinator.playerManager,
            webKitManager: coordinator.webKitManager
        )
            .frame(
                width: 0.01,
                height: 0.01
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(showMiniPlayer ? 0.95 : 0)
            .allowsHitTesting(showMiniPlayer)
            .opacity(0.001)
    }

    // MARK: - Command Bar Overlay

    @ViewBuilder
    private func commandBarOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    coordinator.showCommandBarSheet = false
                }

            CommandBarView(isPresented: $coordinator.showCommandBarSheet)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
        .animation(.easeInOut(duration: 0.15), value: coordinator.showCommandBarSheet)
    }

    #if os(macOS)
    @ViewBuilder
    private func macOSMainContent() -> some View {
        NavigationSplitView {
            macOSSidebar()
                .navigationSplitViewColumnWidth(min: 250, ideal: 250, max: 250)
                .safeAreaInset(edge: .bottom) {
                    SettingsLink {
                        UserProfileView(imageSize: 30, showName: true)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    sidebarWidth = width
                }
        } detail: {
            selectedContentView()
                .safeAreaPadding(.bottom, 100)
        }
        .frame(minWidth: 1000, minHeight: 620)
        .preventSidebarCollapse()
        .overlay(alignment: .trailing) {
            rightSidebarView()
        }
        .overlay(alignment: .bottom) {
            PlayerBar(viewModel: coordinator.playerViewModel)
                .padding(20)
                .padding(.leading, sidebarWidth)
        }
        .animation(.easeInOut(duration: 0.2), value: playerManager.showLyrics || playerManager.showQueue)
    }

    @ViewBuilder
    private func macOSSidebar() -> some View {
        List(selection: $coordinator.navigationSelection) {
            Section {
                Label("Search", systemImage: "magnifyingglass")
                    .tag(NavigationItem.search)
                Label("Home", systemImage: "house")
                    .tag(NavigationItem.home)
                Label("Discovery", systemImage: "safari")
                    .tag(NavigationItem.explore)
            }

            Section("Library") {
                Label("Artists", systemImage: "music.mic")
                    .tag(NavigationItem.libraryArtists)
                Label("Albums", systemImage: "square.stack")
                    .tag(NavigationItem.libraryAlbums)
            }

            Section("Playlists") {
                ForEach(coordinator.libraryCoordinator.libraryViewModel.playlists) { playlist in
                    Label {
                        Text(playlist.title)
                    } icon: {
                        SidebarPlaylistIcon(url: playlist.thumbnailURL)
                    }
                    .tag(NavigationItem.libraryPlaylist(playlist))
                }
            }
        }
        .contextMenu(forSelectionType: NavigationItem.self) { items in
            if case .libraryPlaylist(let playlist) = items.first {
                Button {
                    Task { await playLibraryPlaylist(playlist) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Divider()

                Button(role: .destructive) {
                    Task { await deleteLibraryPlaylist(playlist) }
                } label: {
                    Label("Delete from Library", systemImage: "trash")
                }
            }
        } primaryAction: { items in
            if case .libraryPlaylist(let playlist) = items.first {
                Task { await playLibraryPlaylist(playlist) }
            }
        }
        .listStyle(.sidebar)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func selectedContentView() -> some View {
        switch coordinator.navigationSelection {
        case .search:
            SearchCoordinatorView(
                coordinator: coordinator.searchCoordinator,
                focusTrigger: $coordinator.searchFocusTrigger
            )
        case .home:
            HomeCoordinatorView(coordinator: coordinator.homeCoordinator)
        case .explore:
            LazyView {
                DiscoveryCoordinatorView(coordinator: coordinator.discoverCoordinator)
            }
        case .library:
            LazyView {
                LibraryCoordinatorView(coordinator: coordinator.libraryCoordinator)
            }
        case .libraryArtists:
            LazyView {
                NavigationStack(path: $coordinator.libraryCoordinator.path) {
                    LibraryArtistsView(viewModel: coordinator.libraryCoordinator.libraryViewModel)
                        .navigationDestination(for: Destination.self) { destination in
                            destination.view()
                        }
                }
            }
        case .libraryAlbums:
            LazyView {
                NavigationStack(path: $coordinator.libraryCoordinator.path) {
                    LibraryAlbumsView(viewModel: coordinator.libraryCoordinator.libraryViewModel)
                        .navigationDestination(for: Destination.self) { destination in
                            destination.view()
                        }
                }
            }
        case .libraryPlaylist:
            if let viewModel = coordinator.selectedPlaylistViewModel {
                NavigationStack(path: $coordinator.libraryCoordinator.path) {
                    PlaylistDetailView(viewModel: viewModel)
                        .navigationDestination(for: Destination.self) { destination in
                            destination.view()
                        }
                }
            }
        case .none:
            LoadingView()
        }
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private func iOSMainContent() -> some View {
        TabView(selection: $coordinator.navigationSelection) {

            Tab("Home", systemImage: "house", value: NavigationItem.home) {
                LazyView {
                    HomeCoordinatorView(coordinator: coordinator.homeCoordinator)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Sidebar.homeItem)

            Tab("Discovery", systemImage: "safari", value: NavigationItem.explore) {
                LazyView {
                    DiscoveryCoordinatorView(coordinator: coordinator.discoverCoordinator)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Sidebar.exploreItem)

            Tab("Library", systemImage: "music.note.square.stack.fill", value: NavigationItem.library) {
                LazyView {
                    LibraryCoordinatorView(coordinator: coordinator.libraryCoordinator)
                }
            }
            
            Tab("Search", systemImage: "magnifyingglass", value: NavigationItem.search, role: .search) {
                LazyView {
                    SearchCoordinatorView(
                        coordinator: coordinator.searchCoordinator,
                        focusTrigger: $coordinator.searchFocusTrigger
                    )
                }
            }
            .accessibilityIdentifier(AccessibilityID.Sidebar.searchItem)
        }
        .environment(playerBarAppearance)
        .tabViewStyle(.sidebarAdaptable)
        .tabViewBottomAccessory {
            PlayerBar(viewModel: coordinator.playerViewModel, actualColorScheme: colorScheme, showFullscreenPlayer: $showFullscreenPlayer)
                .matchedTransitionSource(id: "player", in: playerNamespace)
                .bottomAccessorySizeConstrained()
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: $showFullscreenPlayer) {
            ScrollView {

            }
            .safeAreaInset(edge: .top, spacing: 0) {
                PlayerBarCover(
                    viewModel: coordinator.playerViewModel,
                    onDismiss: { showFullscreenPlayer = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTransition(.zoom(sourceID: "player", in: playerNamespace))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    coordinator.showCommandBarSheet = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier(AccessibilityID.MainWindow.aiButton)
                .requiresIntelligence()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPlaylist)) { notification in
            if let playlist = notification.object as? Playlist {
                coordinator.navigationSelection = .home
                coordinator.navigateToPlaylist(playlist)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            if let artist = notification.object as? Artist {
                coordinator.navigationSelection = .home
                coordinator.navigateToArtist(artist)
            }
        }
        .sheet(isPresented: $coordinator.showSettings) {
            SettingsView(viewModel: coordinator.settingsCoordinator.settingsViewModel)
                .presentationDetents([.large])
        }
    }
    #endif

    /// Plays a library playlist.
    private func playLibraryPlaylist(_ playlist: Playlist) async {
        do {
            let detail = try await coordinator.ytMusicClient.getPlaylist(id: playlist.id)
            guard !detail.tracks.isEmpty else { return }
            await playerManager.playQueue(detail.tracks, startingAt: 0, from: playlist)
        } catch {
            // Silently fail
        }
    }

    /// Deletes a playlist from the library.
    private func deleteLibraryPlaylist(_ playlist: Playlist) async {
        try? await coordinator.libraryRepository.removeFromLibrary(playlist)
    }

    #if os(macOS)
    /// Right sidebar overlay showing either lyrics or queue.
    @ViewBuilder
    private func rightSidebarView() -> some View {
        let showRightSidebar = playerManager.showLyrics || playerManager.showQueue

        if showRightSidebar {
            HStack(spacing: 0) {
                Divider()

                VStack {
                    Color.clear.frame(height: 1)
                        .safeAreaPadding(.top)

                    if playerManager.showLyrics {
                        LyricsView()
                            .compositingGroup()
                    } else if playerManager.showQueue {
                        QueueView()
                            .compositingGroup()
                    }
                }
                .frame(width: 280)
            }
            .glassEffect(in: .rect).ignoresSafeArea()
            .transition(.move(edge: .trailing))
        }
    }
    #endif
}


// MARK: - NavigationItem

enum NavigationItem: Hashable, Identifiable {
    case home
    case explore
    case search
    case library
    case libraryArtists
    case libraryAlbums
    case libraryPlaylist(Playlist)

    static func == (lhs: NavigationItem, rhs: NavigationItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: String {
        switch self {
        case .home: "home"
        case .explore: "explore"
        case .search: "search"
        case .library: "library"
        case .libraryArtists: "library-artists"
        case .libraryAlbums: "library-albums"
        case .libraryPlaylist(let playlist): "playlist-\(playlist.id)"
        }
    }

    init?(id: String) {
        switch id {
        case "home": self = .home
        case "explore": self = .explore
        case "search": self = .search
        case "library": self = .library
        case "library-artists": self = .libraryArtists
        case "library-albums": self = .libraryAlbums
        default: return nil // Can't restore libraryPlaylist from id alone
        }
    }

    var icon: String {
        switch self {
        case .home:
            "house"
        case .explore:
            "safari"
        case .search:
            "magnifyingglass"
        case .library:
            "square.stack"
        case .libraryArtists:
            "person.2"
        case .libraryAlbums:
            "square.stack"
        case .libraryPlaylist:
            "music.note.list"
        }
    }
}

// MARK: - SidebarPlaylistIcon

/// A sidebar icon that displays a playlist thumbnail, properly scaled for sidebar use.
private struct SidebarPlaylistIcon: View {
    let url: URL?

    private static let iconSize: CGFloat = 20

    #if os(macOS)
    @State private var image: NSImage?
    #else
    @State private var image: UIImage?
    #endif

    var body: some View {
        Group {
            if let image = scaledImage {
                #if os(macOS)
                Image(nsImage: image)
                #else
                Image(uiImage: image)
                #endif
            } else {
                Image(systemName: "music.note.list")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .clipped()
        .task(id: url) {
            guard let url else { return }
            let result = try? await KingfisherManager.shared.retrieveImage(with: url)
            image = result?.image
        }
    }

    #if os(macOS)
    private var scaledImage: NSImage? {
        guard let image else { return nil }
        return image.scalePreservingAspectRatio(
            targetSize: NSSize(width: Self.iconSize, height: Self.iconSize),
            cornerRadius: 4
        )
    }
    #else
    private var scaledImage: UIImage? {
        image
    }
    #endif
}
  

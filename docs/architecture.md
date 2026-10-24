# Architecture

Mixtape is a SwiftUI YouTube Music client that runs on macOS 26+ and iOS 26+ from a single target. It began as a port of [kaset](https://github.com/sozercan/kaset) and keeps kaset's API layer and WebView playback, adding a coordinator-based navigation layer, dependency injection, and native/VLC audio engines.

## Project Layout

```
App/            MixtapeApp (scene, menus, shortcuts), AppDelegate (macOS)
Container/      FactoryKit registrations
Coordinators/   AppCoordinator + Home/Discover/Library/Search/Settings children,
                Route.swift, Destination.swift, Coordinatable.swift
Scenes/         Feature screens with their view models (Home, Discovery, Library, Downloads, SignIn)
Views/          Shared views (playlist/artist detail, lyrics, queue, command bar, settings, cards)
ViewModels/     Shared view models (search, playlist detail, liked music, settings, …)
Player/         Player bar UI: PlayerBar, PlayerBar+macOS, PlayerBarCover, PlayerViewModel
Services/       API, auth, playback, downloads, AI, WebKit, notifications
Models/         Data types (YTMusic/, AI/, AudioPlayerType, …)
Utilities/      AppDefaults, DiagnosticsLogger, Keychain, extensions
Resources/      Assets, Localizable.xcstrings, Info.plist, entitlements
Tools/          api-explorer.swift (standalone API exploration script)
docs/           This documentation and ADRs
```

Platform-specific code is isolated with `#if os(macOS)` / `#if os(iOS)`.

## Dependency Injection

Services are registered in `Container/Container.swift` with [FactoryKit](https://github.com/hmlongco/Factory), mostly with `.scope(.singleton)`:

| Factory | Type |
|---|---|
| `authService` | `AuthService` |
| `webKitManager` | `WebKitManager` |
| `ytMusicClient` | `YTMusicClientProtocol` → `YTMusicClient` |
| `playerManager` | `PlayerManager` |
| `ytMusicPlayer` | The selected audio engine (see [Playback](playback.md)) |
| `notificationService` | `NotificationService` |

View models and coordinators resolve dependencies with `@Injected`:

```swift
@MainActor @Observable
final class LibraryRepository {
    @ObservationIgnored @Injected(\.ytMusicClient) private var client
}
```

Service protocols live in `Services/Protocols.swift` (`YTMusicClientProtocol`, `AuthServiceProtocol`, `PlayerManagerProtocol`, `WebKitManagerProtocol`, `LibraryRepositoryProtocol`, `DownloadManagerProtocol`, …).

A few types still expose `.shared` and are candidates for moving into the container: `AppDefaults`, `SingletonPlayerWebView`, `FoundationModelsService`, `ErrorPresenter`, `NowPlayingManager`.

## Navigation

Navigation is coordinator-driven; `NavigationLink` is not used. See [ADR 0006](adr/0006-coordinator-cleanup.md).

- **`AppCoordinator`** owns the root `NavigationItem` selection and lazily creates one child coordinator per tab (`HomeCoordinator`, `DiscoveryCoordinator`, `LibraryCoordinator`, `SearchCoordinator`) plus `SettingsCoordinator`.
- **`Route`** is a lightweight enum describing *where* to go (`.home`, `.playlist(Playlist)`, `.artist(Artist)`, `.downloads`, …). `Coordinatable.destination(for:)` turns a route into a **`Destination`**, which carries the view model and renders the view.
- **`AppCoordinatorView`** builds the root UI:
  - **macOS**: `NavigationSplitView` with a sidebar (tabs plus the user's library playlists), a detail `NavigationStack` per tab, and a right sidebar for lyrics/queue.
  - **iOS**: `TabView` with `.sidebarAdaptable` and the player as a bottom accessory.

The player bar is attached once at the root: as a bottom overlay on the `NavigationSplitView` on macOS (the detail column reserves space with `.safeAreaPadding(.bottom, 100)`), and as `.tabViewBottomAccessory` with an expandable `PlayerBarCover` on iOS.

## Services

### `YTMusicClient` (`Services/API/`)

Talks to the YouTube Music InnerTube API (`https://music.youtube.com/youtubei/v1/{endpoint}?prettyPrint=false`) using the `WEB_REMIX` client context. Requests go through Alamofire (`Networking/YTMusicSession`, `YTMusicRequestInterceptor`). Authenticated requests carry a `SAPISIDHASH` header computed from the `__Secure-3PAPISID` cookie.

Implemented areas: home/explore, charts, moods & genres, new releases, search and suggestions, library playlists/albums/artists, liked songs, playlist/artist/album details, lyrics, radio queue, song metadata, like/dislike and library edits, playlist subscribe, account info, and player/stream resolution. `YouTubeClient.swift` covers the few calls that go to `www.youtube.com`.

Responses are parsed by stateless parsers in `Services/API/Parsers/` (`HomeResponseParser`, `SearchResponseParser`, `PlaylistParser`, `ArtistParser`, `LyricsParser`, `RadioQueueParser`, `SearchSuggestionsParser`, `SongMetadataParser`, `AccountMenuParser`, with shared helpers in `ParsingHelpers`). See [ADR 0003](adr/0003-modular-api-parsers.md) and [API Discovery](api-discovery.md).

### `AuthService` (`Services/Auth/`)

State machine: `.initializing` → `.loggedOut` → `.loggingIn` → `.loggedIn(sapisid:)`. Login happens in a `WKWebView` sheet; `completeLogin(sapisid:)` is called once the auth cookie appears. `sessionExpired()` raises `needsReauth` when the API reports an expired session, and `signOut()` clears cookies.

### `WebKitManager` (`Services/WebKit/`)

Owns the shared `WKWebsiteDataStore`, the user agent (Safari on macOS, iPhone Safari on iOS), and cookie access. Auth cookies are also backed up to the Keychain (`Utilities/Keychain.swift`) and restored on launch, because WebKit storage can lose them.

### `PlayerManager` (`Services/Player/`)

The single source of truth for playback state: current track, queue, shuffle/repeat, progress, volume, like status, and lyrics/queue panel visibility. It delegates actual audio to a `YTMusicPlayer` engine, plays downloaded files locally, and restores the saved queue on launch. Details in [Playback](playback.md).

### `LibraryRepository`

In-memory cache of the user's library playlists, albums, and artists with on-demand `load()`/`refresh()`. There is no disk cache or background sync yet; see the [library sync proposal](library-sync-strategy.md).

### `DownloadManager` (`Services/Download/`)

Downloads audio for songs and playlists to `Application Support/Mixtape/`, tracks progress, supports cancel/retry/delete, and keeps a JSON catalog (`downloads-catalog.json`). `PlayerManager` plays a downloaded copy when one exists.

### AI (`Services/AI/`)

`FoundationModelsService` wraps Apple's on-device Foundation Models for the command bar (`MusicIntent`), lyrics explanations (`LyricsSummary`), and playlist refinement (`PlaylistChanges`). Tools available to the model live in `Services/AI/Tools/` (`MusicSearchTool`, `QueueTool`). `AIErrorHandler` maps model errors to user-facing messages, and `.requiresIntelligence()` (`Utilities/IntelligenceModifier.swift`) hides AI UI on unsupported devices. See [ADR 0005](adr/0005-foundation-models-architecture.md).

### Other services

| Service | Purpose |
|---|---|
| `NowPlayingManager` | Routes `MPRemoteCommandCenter` commands (media keys, lock screen, Control Center) to `PlayerManager` |
| `NotificationService` | Track-change notifications with artwork (macOS) |
| `SongLikeStatusManager` | Caches like/dislike state across views |
| `NetworkMonitor` | `NWPathMonitor` wrapper; Home and Discovery check connectivity |
| `ErrorPresenter` | Presents `YTMusicError` to the user |

## App Lifecycle (macOS)

`AppDelegate` keeps audio playing when the window is closed: `windowShouldClose` hides the app instead of closing the window, so the singleton WebView stays alive. It also provides the Dock menu (play/pause, next, previous) and sets up notification handling. The app quits normally with ⌘Q.

On iOS, background audio uses the `audio` background mode in `Info.plist`.

## Error Handling

API failures are surfaced as `YTMusicError` (`Models/YTMusic/YTMusicError.swift`), including `.authExpired`, `.notAuthenticated`, `.networkError`, `.parseError`, `.apiError`, `.playbackError`, and `.unknown`. When `YTMusicRequestInterceptor` detects an expired session it calls `AuthService.sessionExpired()`, which sets `needsReauth` and prompts the user to sign in again.

## Logging

`DiagnosticsLogger` provides `os.Logger` instances by category: `auth`, `api`, `webKit`, `player`, `ui`, `notification`, `ai`, `download`. Filter by category in Console.app.

## Settings

`AppDefaults` (`Utilities/AppDefaults.swift`) stores user preferences in `UserDefaults`: content language and region, audio engine, Now Playing notifications, library display options.

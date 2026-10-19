# CLAUDE.md

# Claude Development Rules

## Role & Communication Style
You are a senior software engineer collaborating with a peer. Prioritize thorough planning and alignment before implementation. Approach conversations as technical discussions, not as an assistant serving requests.
Do check directives to ensure they emphasize positive "Do" guidance rather than prohibitive "Don'ts".

## Development Process
1. Plan First: Always start with discussing the approach.
2. Identify Decisions: Surface all implementation choices that need to be made.
3. Consult on Options: When multiple approaches exist, present them with trade-offs.
4. Confirm Alignment: Ensure we agree on the approach before writing code.
5. Then Implement: Only write code after we've aligned on the plan.
6. Review & Test: Ensure code follows conventions, is reviewed critically, and is tested.

## Core Behaviors
- Break down features into clear tasks before implementing.
- Ask about preferences for: data structures, patterns, libraries, error handling, naming conventions.
- Surface assumptions explicitly and get confirmation.
- Provide constructive criticism when you spot issues.
- Push back on flawed logic or problematic approaches.
- Present trade-offs objectively without defaulting to agreement.
- Write commit messages that are concise, functional, and avoid self-referential language.

## Testing Requirements
- Write tests for all new features unless explicitly told not to.
- Run tests before committing to ensure code quality and functionality.
- Use `xcodebuild test` to verify all tests pass before making commits.
- Tests should cover both happy path and edge cases for new functionality.

## When Planning
- Present multiple options with pros/cons when they exist.
- Call out edge cases and how we should handle them.
- Ask clarifying questions rather than making assumptions.
- Question design decisions that seem suboptimal.
- Share opinions on best practices, but acknowledge when something is opinion vs fact.
- As a code reviewer, criticize the first plan you come up with: compare against existing codebase conventions, libraries, and see if the plan can be improved.

## When Implementing
- Follow the agreed-upon plan precisely.
- If you discover an unforeseen issue, stop and discuss.
- Note concerns inline if you see them during implementation.
- Verify tests pass before committing.

## Technical Discussion Guidelines
- Assume I understand common programming concepts without over-explaining.
- Point out potential bugs, performance issues, or maintainability concerns.
- Be direct with feedback rather than couching it in niceties.

## DO Guidelines
- Do begin with planning and alignment before writing code.
- Do involve me when making architectural or structural decisions.
- Do keep responses concise and professional, without unnecessary praise.
- Do give direct feedback without defaulting to agreement.
- Do clearly distinguish between objective improvements and subjective style preferences.
- Do provide criticism in a professional and constructive manner.

## Build & Test Commands

```bash
# Build
xcodebuild -scheme Mixtape -destination 'platform=macOS' build

# Run all tests
xcodebuild -scheme Mixtape -destination 'platform=macOS' test

# Run unit tests only
xcodebuild -scheme Mixtape -destination 'platform=macOS' test -only-testing:MixtapeTests

# Lint & format (if available)
swiftlint --strict && swiftformat .
```

## Architecture Overview

**Mixtape** is a SwiftUI music streaming app for macOS 26.0+ for YouTube Music (via unofficial API). Uses Liquid Glass design language.

### Core Patterns

- **Coordinator Pattern**: `AppCoordinator` manages navigation. Child coordinators: `HomeCoordinator`, `DiscoverCoordinator`, `LibraryCoordinator`, `SearchCoordinator`
- **MVVM**: ViewModels are `@Observable @MainActor` classes with protocol-based service injection
- **Dependency Injection**: FactoryKit container in `Container/Container.swift`. Register all services in the Container rather than using singletons

### Key Services

| Service | Location | Purpose |
|---------|----------|---------|
| `YTMusicClient` | `Services/API/` | YouTube Music API client with SAPISIDHASH auth |
| `AuthService` | `Services/Auth/` | Authentication state machine (loggedOut → loggingIn → loggedIn) |
| `PlayerManager` | `Services/Player/` | Playback control via singleton WebView |
| `WebKitManager` | `Services/WebKit/` | Cookie persistence and WebView configuration |
| `NowPlayingManager` | `Services/Player/` | Media key integration via `MPRemoteCommandCenter` |
| `FoundationModelsService` | `Services/AI/` | Apple Intelligence/Foundation Models integration |

### API Parsing

Response parsing is modular in `Services/API/Parsers/`:
- `HomeResponseParser.swift` - Home/Explore pages
- `SearchResponseParser.swift` - Search results
- `PlaylistParser.swift` - Playlist details
- `ArtistParser.swift` - Artist information
- `ParsingHelpers.swift` - Shared utilities

### Playback Architecture

Uses a singleton `WKWebView` that persists for app lifetime (`Views/MiniPlayerWebView.swift`). DRM handled natively by WebKit. Window hides instead of closes to maintain background audio (`AppDelegate`).

### PlayerBar Integration

The `PlayerBar` must be added to **every navigable view** via `safeAreaInset`:

```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    PlayerBar()
}
```

Views pushed onto a `NavigationStack` don't inherit parent's `safeAreaInset`.

### Persistent UI Elements

Elements like the lyrics sidebar that must persist across navigation should be placed **outside** `NavigationSplitView` in `MainWindow`.

## Testing

Tests are in `Tests/MixtapeTests/` with helpers in `Helpers/` and fixtures in `Fixtures/`.

For `@MainActor` test classes, use async setUp/tearDown **without calling super** (XCTestCase is not Sendable):

```swift
@MainActor
final class MyServiceTests: XCTestCase {
    override func setUp() async throws {
        // Do NOT call super.setUp()
    }
}
```

Use `MockYTMusicClient` for API mocking and `MockURLProtocol` for network-level mocking.

## Documentation

Detailed docs in `/docs/`:
- `architecture.md` - Full architecture guide with flow diagrams
- `api-discovery.md` - YouTube Music API reference
- `playback.md` - WebView playback implementation
- `testing.md` - Testing patterns and mocking
- `adr/` - Architecture Decision Records

## YouTube Music API Reference

Primary documentation: https://ytmusicapi.readthedocs.io/en/stable/

### API Methods by Category

| Category | Methods |
|----------|---------|
| **Search** | `search()`, `get_search_suggestions()`, `remove_search_suggestions()` |
| **Browsing** | `get_home()`, `get_artist()`, `get_artist_albums()`, `get_album()`, `get_song()`, `get_song_related()`, `get_lyrics()`, `get_user()`, `get_user_playlists()` |
| **Explore** | `get_mood_categories()`, `get_mood_playlists()`, `get_charts()` |
| **Watch** | `get_watch_playlist()` (up-next queue) |
| **Library** | `get_library_playlists()`, `get_library_songs()`, `get_library_albums()`, `get_library_artists()`, `get_liked_songs()`, `get_history()`, `rate_song()`, `subscribe_artists()` |
| **Playlists** | `get_playlist()`, `create_playlist()`, `edit_playlist()`, `delete_playlist()`, `add_playlist_items()`, `remove_playlist_items()` |
| **Podcasts** | `get_channel()`, `get_channel_episodes()`, `get_podcast()`, `get_episode()` |
| **Uploads** | `get_library_upload_songs()`, `upload_song()`, `delete_upload_entity()` |

### Notes
- This is an unofficial API (not endorsed by Google)
- Authentication uses SAPISIDHASH from browser cookies (see `YTMusicClient`)
- Response parsing is complex JSON - use parsers in `Services/API/Parsers/`

## API Reference Codebases

When investigating unknown YouTube Music API behavior, reference these open-source implementations:

1. https://ytmusicapi.readthedocs.io/en/stable/ (Python, most comprehensive docs)
2. `InnerTune` - Kotlin, Android YouTube Music client
3. `OuterTune` - Kotlin, fork of InnerTune with additional features
4. `Metrolist` - Kotlin, Android YouTube Music client
5. `Kreate` - Kotlin, YouTube Music client
6. `NewPipeExtractor` - Java, extractor library for multiple services including YouTube
7. `ytdlnis` - Kotlin, YouTube downloader with music support
8. `YTLitePlus` - Objective-C tweak for official YouTube Music app

These projects implement YouTube Music API integrations and can help clarify endpoint parameters, response parsing, and authentication flows.

## Key Conventions

- **Never create singletons** - Always register services in the FactoryKit Container (`Container/Container.swift`) and inject dependencies. Avoid `.shared` singleton patterns for new code
- **Inject in ViewModels and Coordinators only** - Use `@Injected` in ViewModels and Coordinators, never in Views. Views should access services through their ViewModel
- **Never use `NavigationLink`** - Always use the coordinator pattern for navigation. Push destinations via coordinator methods, not SwiftUI's built-in navigation links
- **Use `@ViewBuilder` functions for subviews** - Create subviews using `@ViewBuilder func` instead of computed `var` properties
- **Use modern geometry APIs** - Prefer `onGeometryChange` or `containerRelativeFrame` over `GeometryReader` when possible
- All services expose protocols in `Services/Protocols.swift` for testability
- Error handling via `YTMusicError` enum, presented through `ErrorPresenter`
- Logging via `DiagnosticsLogger` with categories: `.player`, `.auth`, `.api`, `.webKit`
- Platform-specific code uses `#if os(macOS)` / `#if os(iOS)`
- Localization in `Resources/Localizable.xcstrings`

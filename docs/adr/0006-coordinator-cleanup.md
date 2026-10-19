# ADR-0006: Coordinator Cleanup and Consolidation

## Status

Accepted

## Context

Prior to commit `d7177f8`, each coordinator (HomeCoordinator, SearchCoordinator, LibraryCoordinator, DiscoveryCoordinator) had:

1. **Duplicated delegate implementations** - Each coordinator implemented the same navigation delegate methods (`didSelectPlaylist`, `didSelectArtist`, `didSelectAlbum`, etc.) with identical logic
2. **Duplicated `makeDestination` logic** - Each coordinator had its own switch statement creating ViewModels
3. **Scattered protocols** - Multiple delegate protocols per coordinator (`HomeViewModelDelegate`, `ArtistDetailViewModelDelegate`, etc.)
4. **Inconsistent conformances** - Some coordinators conformed to protocols they didn't fully use
5. **~700 lines of duplicated code** across the four coordinators

## Decision

Consolidate all shared coordinator behavior into the `Coordinatable` protocol with default implementations.

### File Changes

| File | Change |
|------|--------|
| `Destination+View.swift` | Renamed to `Destination.swift` |
| `Coordinatable.swift` | Expanded with default implementations |
| `Route.swift` | Added `signInRedirector`, `library`, `moods` cases |
| `HomeCoordinator.swift` | Reduced from ~160 lines to ~42 lines |
| `SearchCoordinator.swift` | Reduced from ~140 lines to ~45 lines |
| `LibraryCoordinator.swift` | Reduced from ~150 lines to ~50 lines |
| `DiscoveryCoordinator.swift` | Reduced from ~200 lines to ~50 lines |

### Protocol Changes

**Before:**
```swift
protocol CoordinatorDelegate: AnyObject {
    func didRequestSettings()
}

protocol Coordinatable: HashableObject {
    var path: [Destination] { get set }
    var root: Destination { get set }
    func makeDestination(for route: Route) -> Destination
}

// Plus per-ViewModel delegates:
// - HomeViewModelDelegate
// - ArtistDetailViewModelDelegate
// - DiscoverViewModelDelegate
// - AllAlbumsViewModelDelegate
// etc.
```

**After:**
```swift
protocol AppCoordinatorDelegate: AnyObject {
    func didRequestSettings()
    func didRequestSwitchToHome()
}

protocol CoordinatableDelegate: AnyObject {
    func didSelectPlaylist(_ playlist: Playlist)
    func didSelectArtist(_ artist: Artist)
    func didSelectAlbum(_ album: Album)
    func didSelectSection(_ section: HomeSection)
    func didSelectTopSongs(_ destination: TopSongsDestination)
    func didSelectAllAlbums(_ section: AlbumSection)
    func didSelectMoodsAndGenres()
    func didRequestSettings()
}

protocol Coordinatable: HashableObject,
    CoordinatableDelegate,
    SignInRedirectorViewModelDelegate {

    var path: [Destination] { get set }
    var root: Destination { get set }
    var delegate: AppCoordinatorDelegate? { get }
    func makeDestination(for route: Route) -> Destination
}
```

### Coordinator Simplification

**Before (HomeCoordinator):**
```swift
@MainActor @Observable
final class HomeCoordinator: HashableObject {
    let homeViewModel: HomeViewModel
    var root: Destination = .none
    var path: [Destination] = []
    weak var delegate: CoordinatorDelegate?

    init() {
        homeViewModel = HomeViewModel()
        homeViewModel.delegate = self
        root = .home(homeViewModel)
        // auth state handling...
    }

    func makeDestination(for route: Route) -> Destination {
        switch route {
        case .home: return .home(homeViewModel)
        case .playlist(let p): // create VM...
        case .artist(let a): // create VM, set delegate...
        // ... 15+ cases
        }
    }
}

extension HomeCoordinator: HomeViewModelDelegate {
    func didSelectPlaylist(_ playlist: Playlist) { /* mood category check */ }
    func didSelectArtist(_ artist: Artist) { /* navigate */ }
    func didSelectAlbum(_ album: Album) { /* convert to playlist */ }
    // ... more methods
}

extension HomeCoordinator: ArtistDetailViewModelDelegate { /* ... */ }
extension HomeCoordinator: DiscoverViewModelDelegate { /* ... */ }
```

**After (HomeCoordinator):**
```swift
@MainActor @Observable
final class HomeCoordinator: @MainActor Coordinatable {
    var root: Destination = .loading
    var path: [Destination] = []
    weak var delegate: AppCoordinatorDelegate?

    init() {
        authService.statePublisher
            .sink { [weak self] state in
                if state.isLoggedIn {
                    self?.setRoot(to: .home)
                } else if state == .loggedOut {
                    self?.setRoot(to: .signIn)
                }
            }
            .store(in: &cancellables)
    }
}
// No extensions needed - all delegate methods provided by Coordinatable defaults
```

### Other Cleanups

1. **Removed `DestinationViewable` protocol** - Only `Destination` conformed to it; now `view()` is just a method
2. **Renamed `.explore` to `.discovery`** - Consistent naming with DiscoveryViewModel
3. **Added `Route.moods`** - `didSelectMoodsAndGenres()` now uses `navigate(to:)` pattern
4. **Removed `import Foundation`** - SwiftUI covers required types

## Migration Guide

### For ViewModels

ViewModels should set their delegate to a `CoordinatableDelegate`:

```swift
// Before: Multiple specific delegate protocols
protocol HomeViewModelDelegate: AnyObject {
    func didSelectPlaylist(_ playlist: Playlist)
    func didSelectArtist(_ artist: Artist)
    // ...
}

// After: Use unified CoordinatableDelegate
@MainActor @Observable
final class HomeViewModel {
    weak var delegate: CoordinatableDelegate?
}
```

### For New Coordinators

New coordinators only need to:

1. Conform to `Coordinatable`
2. Declare `path`, `root`, `delegate` properties
3. Handle auth state to set initial root

```swift
@MainActor @Observable
final class MyCoordinator: @MainActor Coordinatable {
    var root: Destination = .loading
    var path: [Destination] = []
    weak var delegate: AppCoordinatorDelegate?

    init() {
        // Set up auth state observation
        // Call setRoot(to:) when ready
    }
}
```

### For New Navigation Destinations

1. Add case to `Destination` enum
2. Add case to `Route` enum
3. Add `view()` case in `Destination` extension
4. Add case in `Coordinatable.makeDestination(for:)`
5. If ViewModel needs navigation, add delegate method to `CoordinatableDelegate`

## Consequences

### Positive

- **~500 lines removed** - Eliminated duplicated code across coordinators
- **Single source of truth** - Navigation logic defined once in `Coordinatable`
- **Easier onboarding** - New coordinators require minimal boilerplate
- **Consistent behavior** - All coordinators handle navigation identically

### Negative

- **Less flexibility** - Coordinators can't easily customize navigation behavior
- **Protocol inheritance** - `Coordinatable` inherits from multiple protocols

### Trade-offs

- Coordinators needing custom behavior can override default implementations
- The unified `CoordinatableDelegate` may grow as features are added

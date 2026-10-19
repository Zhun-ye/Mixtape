# Mixtape

A native YouTube Music client for macOS and iOS, built with SwiftUI and the Liquid Glass design language.

> Mixtape uses YouTube Music's unofficial web API. It is not affiliated with, endorsed by, or sponsored by Google or YouTube.

## Origins

Mixtape is a port of [**kaset**](https://github.com/sozercan/kaset) by [@sozercan](https://github.com/sozercan), a macOS-only YouTube and YouTube Music client released under the MIT License. Mixtape takes kaset's YouTube Music side and rebuilds it to run on **both macOS and iOS** from a single codebase.

### How Mixtape differs from kaset

| | kaset | Mixtape |
|---|---|---|
| Platforms | macOS 15.4+ | macOS 26+ **and iOS 26+** |
| Scope | YouTube Music and YouTube video | YouTube Music only |
| Navigation | SwiftUI environment-based | Coordinator pattern shared by both platforms |
| Dependency injection | — | [Factory](https://github.com/hmlongco/Factory) container, protocol-based services |
| Audio engines | WebView | WebView, **Native (AVPlayer)**, and **VLC**, switchable in Settings |
| Offline | — | **Downloads** for songs and playlists |
| iOS UI | — | Adaptive tab bar, bottom mini-player, expanded cover, AirPlay, lock screen controls |

kaset has features Mixtape does not (yet): YouTube video, equalizer, smart shuffle, scrobbling, podcasts, history, WebKit extensions, AppleScript and URL-scheme automation, and Sparkle updates. New kaset features are ported over selectively, and kaset's design notes are the basis for several documents in [`docs/`](docs/).

## Features

### Browse & search
- **Home** feed with "see all" pages for each section
- **Discovery** — charts, new releases, and moods & genres
- **Artist pages** with top songs, all albums, Shuffle, and Mix (radio)
- **Album and playlist pages** with song context menus: play, like/dislike, add to library, go to artist or album
- **Search** — ⌘F on macOS
- Hover-to-play on cards (macOS), long-press menus (iOS)

### Library
- Your playlists, albums, artists, and Liked Music
- Playlists in the macOS sidebar with play and delete actions
- Sign in with your Google account through an in-app web login

### Playback
- Player bar on macOS; mini-player and expanded cover on iOS
- Shuffle, repeat (off / all / one), volume, and mute
- Queue with "continue playing", remove, and clear; restored on next launch
- **Lyrics** sidebar, with AI explanations of meaning, mood, and themes
- Media keys, Now Playing, and lock screen / Control Center controls
- **Three audio engines**, selectable in Settings:

| Engine | How it plays | Quality | Platforms |
|---|---|---|---|
| Web Player (default) | Persistent `WKWebView`, DRM handled by WebKit | Up to 300 kbps Opus with YouTube Premium | macOS |
| Native Player | `AVPlayer` on direct streams | 130 kbps AAC | macOS, iOS |
| VLC Player | VLCKit / MobileVLCKit | 160 kbps Opus | macOS, iOS |

### Downloads
- Download songs or whole playlists for offline listening
- Downloads page with Play All, Shuffle, and per-item or bulk delete
- Cancel and retry in-progress downloads

### Apple Intelligence
Requires a device that supports Apple Intelligence.
- **Command bar** (⌘K) for natural-language control: "play something upbeat", "queue some 90s rock", "skip"
- **Playlist refine** — remove duplicates, make it more upbeat, or improve the flow
- Falls back to plain search when the model isn't available

### macOS
- Background audio: closing the window hides it and the music keeps playing
- Dock menu playback controls
- Track-change notifications with artwork
- Keyboard shortcuts:

| Shortcut | Action |
|---|---|
| Space | Play / pause |
| ⌘→ / ⌘← | Next / previous |
| ⌘↑ / ⌘↓ | Volume up / down |
| ⇧⌘M | Mute |
| ⌘S / ⌘R | Shuffle / repeat |
| ⌘L | Lyrics |
| ⌘1 / ⌘2 / ⌘3 | Home / Discovery / Library |
| ⌘F | Search |
| ⌘K | Command bar |

### Settings
- Content language and region
- Audio engine
- Now Playing notifications (macOS)

### Localization
English, French (incl. Canadian), Japanese, and Chinese (Simplified, Traditional, Hong Kong).

## Requirements

| | |
|---|---|
| macOS | 26.0+ |
| iOS | 26.1+ |
| Xcode | 26+ |
| Swift | 6.0 |
| [Carthage](https://github.com/Carthage/Carthage) | for VLCKit |

## Getting Started

```bash
git clone https://github.com/alexcding/Mixtape.git
cd Mixtape

# Fetch VLCKit (binary XCFrameworks, ~500 MB)
brew install carthage
carthage bootstrap --use-xcframeworks --platform macOS,iOS --cache-builds

open Mixtape.xcodeproj
```

In Xcode:

1. Select the **Mixtape** target → **Signing & Capabilities**, choose your team, and change the bundle identifier to one you own.
2. When prompted, trust the Swift package macros and plugins.
3. Build and run on **My Mac** or an iOS device/simulator.

Sign in with your Google account from inside the app.

### Command-line build

```bash
xcodebuild -scheme Mixtape -destination 'platform=macOS' build
xcodebuild -scheme Mixtape -destination 'generic/platform=iOS Simulator' build
```

Add `-skipMacroValidation -skipPackagePluginValidation` to skip the macro trust prompt, and `CODE_SIGNING_ALLOWED=NO` to build without a signing team.

## Architecture

- **SwiftUI + MVVM** — view models are `@Observable @MainActor` classes
- **Coordinators** handle all navigation (`AppCoordinator` with Home, Discovery, Library, and Search children)
- **Dependency injection** via [Factory](https://github.com/hmlongco/Factory); services are defined by protocols in `Services/Protocols.swift`
- **API** — `YTMusicClient` talks to the YouTube Music InnerTube API using SAPISIDHASH authentication from browser cookies; response parsers live in `Services/API/Parsers/`
- **Playback** — a persistent singleton `WKWebView` handles DRM-protected streams; the window hides rather than closes so audio keeps playing

```
App/            App entry point and delegate
Container/      Dependency injection registrations
Coordinators/   Navigation
Scenes/         Feature screens (Home, Discovery, Library, Downloads, Sign-in)
Views/          Shared views and components
ViewModels/     View state
Services/       API, auth, player, downloads, AI, WebKit
Models/         Data types
Resources/      Assets, localization, Info.plist, entitlements
docs/           Design notes and ADRs
```

More detail in [`docs/`](docs/), including [API discovery notes](docs/api-discovery.md), [playback](docs/playback.md), and [architecture decision records](docs/adr/).

## Acknowledgements

Mixtape builds on the work of these projects:

- [kaset](https://github.com/sozercan/kaset), the macOS app Mixtape is ported from
- [ytmusicapi](https://github.com/sigma67/ytmusicapi)
- [InnerTune](https://github.com/z-huang/InnerTune), [OuterTune](https://github.com/DD3Boh/OuterTune), and [Metrolist](https://github.com/mostafaalagamy/Metrolist)
- [NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor)
- [VLCKit](https://code.videolan.org/videolan/VLCKit), [Kingfisher](https://github.com/onevcat/Kingfisher), [Alamofire](https://github.com/Alamofire/Alamofire), [SwiftUI-Introspect](https://github.com/siteline/swiftui-introspect)

## License

[MIT](LICENSE). Portions derived from kaset are Copyright (c) 2025 sozercan, also under the MIT License.

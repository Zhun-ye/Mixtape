# Playback

Mixtape has three interchangeable audio engines behind one protocol. `PlayerManager` owns playback state (track, queue, shuffle/repeat, progress, volume) and delegates audio to whichever engine is selected.

```
Views / PlayerBar ──► PlayerManager ──► YTMusicPlayer (protocol)
                           │                 ├── YTMusicWebPlayer    → SingletonPlayerWebView (WKWebView)
                           │                 ├── YTMusicNativePlayer → StreamFetcher → AVPlayer
                           │                 └── VLCMusicPlayer      → StreamFetcher → VLCKit
                           └── downloaded file? → AVPlayer on the local asset
```

## Engines

| Engine | `AudioPlayerType` | Audio source | Quality | Platforms |
|---|---|---|---|---|
| Web Player | `.webView` | `music.youtube.com` in a hidden `WKWebView`; WebKit handles DRM | Up to 300 kbps Opus with YouTube Premium | macOS |
| Native Player | `.native` | Direct stream URL via `StreamFetcher`, played with `AVPlayer` | ~130 kbps AAC | macOS, iOS |
| VLC Player | `.vlc` | Direct stream URL via `StreamFetcher`, played with VLCKit / MobileVLCKit | ~160 kbps Opus | macOS, iOS |

The Web Player is the default on macOS. It is not offered on iOS (`AudioPlayerType.availableCases` returns only `.native` and `.vlc`).

### Selecting an engine

`Container.ytMusicPlayer` returns the engine matching `AppDefaults.shared.audioPlayer`, and `Container.playerManager` injects it with `setAudioPlayer(_:)`. In Settings, `SettingsViewModel.switchPlayer(to:)` calls `PlayerManager.switchPlayer(to:)`, which stops the current engine, swaps in the new one, carries over the volume, saves the choice, and reloads the current track if it was playing. The picker is disabled while a switch is in progress.

### The `YTMusicPlayer` protocol

`Services/Player/YTMusicPlayer.swift` defines what every engine implements: `loadVideo(videoId:)`, `play()`, `pause()`, `seek(to:)`, `setVolume(_:)`, `stop()`, and optionally `next()`/`previous()`. Engines report progress, duration, play state, track end, and audio quality back through callbacks that `PlayerManager` subscribes to.

## Web Player

`YTMusicWebPlayer` drives `SingletonPlayerWebView` (`Views/SingletonPlayerWebView.swift`), a single `WKWebView` that lives for the app's lifetime:

- `loadVideo(videoId:)` navigates to `https://music.youtube.com/watch?v={id}`, or reuses the page if it's already loaded.
- The web view shares `WebKitManager`'s data store, so it is signed in with the same cookies as the API client.
- An injected script observes the YouTube Music player and posts `STATE_UPDATE` messages (play state, progress, duration, track metadata, like status, audio quality, track end) to the `singletonPlayer` message handler. The coordinator forwards them to `PlayerManager`.
- Controls (play/pause, next/previous, seek, volume) are sent back by evaluating JavaScript in the page.
- On macOS the web view is hosted off-screen by `PersistentPlayerView` (`Views/MiniPlayerViews.swift`) and re-parented with `ensureInHierarchy(container:)` so it is never deallocated.

Because the WebView must stay alive, `AppDelegate.windowShouldClose` hides the app instead of closing the window. See [ADR 0001](adr/0001-webview-playback.md).

**Debugging:** the web view is `isInspectable`; open Safari → Develop → (your Mac) → the music.youtube.com page.

## Native and VLC Players

Both use `StreamFetcher` (`Services/Player/StreamFetcher.swift`) to resolve a direct audio URL:

1. Fetch visitor data (cached) to reduce bot checks.
2. Call the InnerTube `player` endpoint on `www.youtube.com`, trying clients in order: `ANDROID_VR` → `ANDROID_MUSIC` → `IOS` → `TVHTML5_SIMPLY_EMBEDDED_PLAYER`.
3. Pick a format with the engine's own `formatSelector` (AAC for `AVPlayer`; VLC prefers Opus, itags 251 → 141 → 250 → 140 → 249) and report its codec and bitrate.

`YTMusicNativePlayer` plays the URL through `NativePlayerSession`, which wraps `AVPlayer` and observes item status, time-control status, and periodic time updates. `VLCMusicPlayer` does the same with `VLCMediaPlayer`.

These engines set `MPNowPlayingInfoCenter` metadata themselves, which drives the lock screen, Control Center, and the macOS Now Playing widget.

## Downloads

`DownloadManager` resolves an HLS manifest with `StreamFetcher.fetchHLSManifestURL(videoId:)` and downloads it with `AVAssetDownloadURLSession`. When a downloaded copy exists, `PlayerManager.play(song:)` plays the local asset with `AVPlayer` regardless of the selected engine.

## Queue

`PlayerManager` owns the queue (`playQueue(_:startingAt:from:)`), shuffle, and repeat (off / all / one). For radio, it fetches an up-next queue with `getRadioQueue(videoId:)`. The queue and current index are saved to `AppDefaults` and restored on launch.

## Remote Controls

`NowPlayingManager` registers `MPRemoteCommandCenter` handlers (play, pause, toggle, next, previous, seek) and routes them to `PlayerManager`. This covers media keys on macOS and the lock screen / Control Center / headphones on iOS.

## Background Audio

- **macOS:** closing the window hides the app; playback continues until ⌘Q.
- **iOS:** the `audio` background mode in `Info.plist` keeps the Native and VLC engines playing. `BackgroundTaskHelper` wraps short async work (such as resolving the next stream) in a background task so it can finish while the app is suspended.

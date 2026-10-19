# Testing Guide

This document covers testing strategies, commands, and best practices for Music.

## Test Commands

### Unit Tests

```bash
xcodebuild -scheme Music -destination 'platform=macOS' test -only-testing:MusicTests
```

### Full Suite

```bash
xcodebuild -scheme Music -destination 'platform=macOS' test
```

### Build Only

```bash
xcodebuild -scheme Music -destination 'platform=macOS' build
```

### Lint & Format

```bash
swiftlint --strict && swiftformat .
```

## Test Structure

```
Tests/MusicTests/
├── Helpers/
│   ├── MockURLProtocol.swift    # Network mocking
│   ├── MockYTMusicClient.swift  # API client mock
│   └── TestFixtures.swift       # Fixture loading utilities
├── Fixtures/
│   ├── home_response.json       # Sample API responses
│   ├── search_response.json
│   └── playlist_detail.json
├── *Tests.swift                 # Test files
```

## Unit Test Requirements

New code in `Core/` (Services, Models, ViewModels, Utilities) must include unit tests.

### Creating a Test File

1. Create test file in `Tests/MusicTests/` matching the source file name
   - Example: `YTMusicClient.swift` → `YTMusicClientTests.swift`
2. Add the test file to the Xcode project
3. Run tests to verify

### Test File Template

```swift
import XCTest
@testable import Music

@MainActor
final class MyServiceTests: XCTestCase {
    var sut: MyService!

    override func setUp() async throws {
        // Do NOT call super.setUp() in @MainActor async context
        sut = MyService()
    }

    override func tearDown() async throws {
        sut = nil
        // Do NOT call super.tearDown() in @MainActor async context
    }

    func testSomething() async throws {
        // Arrange
        // ...

        // Act
        let result = try await sut.doSomething()

        // Assert
        XCTAssertNotNil(result)
    }
}
```

### @MainActor Test Classes

For tests of `@MainActor` classes (most services), use async setUp/tearDown **without calling super**:

```swift
@MainActor
final class PlayerManagerTests: XCTestCase {
    override func setUp() async throws {
        // ⚠️ Do NOT call: try await super.setUp()
        // XCTestCase is not Sendable, calling super crosses actor boundaries
    }

    override func tearDown() async throws {
        // ⚠️ Do NOT call: try await super.tearDown()
    }
}
```

**Why?** `XCTestCase` is not `Sendable`. Calling `super.setUp()` from a `@MainActor` async context sends `self` across actor boundaries, causing Swift 6 strict concurrency errors.

## Environment Isolation

### Using MockURLProtocol

For network testing without real API calls:

```swift
// In test setup
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let session = URLSession(configuration: config)

// Set response handler
MockURLProtocol.requestHandler = { request in
    let json = """
    {"id": "123", "data": [...]}
    """
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    return (response, json.data(using: .utf8)!)
}
```

## Test Categories

### Service Tests

Test business logic in isolation:

```swift
func testAuthServiceLoginState() async {
    // Given
    let authService = AuthService()

    // When
    authService.startLogin()

    // Then
    XCTAssertEqual(authService.state, .loggingIn)
}
```

### Model Tests

Test Codable conformance and parsing:

```swift
func testSongDecoding() throws {
    let json = """
    {"videoId": "abc123", "title": "Test Song", "artist": "Test Artist"}
    """.data(using: .utf8)!

    let song = try JSONDecoder().decode(Song.self, from: json)

    XCTAssertEqual(song.videoId, "abc123")
    XCTAssertEqual(song.title, "Test Song")
}
```

### ViewModel Tests

Test state management and loading:

```swift
func testHomeViewModelLoading() async throws {
    let viewModel = HomeViewModel(client: mockClient)

    await viewModel.load()

    XCTAssertFalse(viewModel.isLoading)
    XCTAssertFalse(viewModel.sections.isEmpty)
}
```

### Parser Tests

Test API response parsing with mock data:

```swift
func testParseHomeResponse() {
    let data = makeHomeResponseData(sectionCount: 3)

    let (sections, token) = HomeResponseParser.parse(data)

    XCTAssertEqual(sections.count, 3)
}
```

Parser tests use helper methods to construct mock JSON structures, enabling comprehensive testing without network calls.

## Mocking Guidelines

### MockYTMusicClient

The project includes a ready-to-use mock client:

```swift
// Tests/MusicTests/Helpers/MockYTMusicClient.swift
final class MockYTMusicClient: YTMusicClientProtocol, @unchecked Sendable {
    var homeResponse: HomeResponse?
    var searchResponse: SearchResponse?
    var error: Error?

    func getHome() async throws -> HomeResponse {
        if let error { throw error }
        return homeResponse ?? HomeResponse(sections: [], continuationToken: nil)
    }
    // ... other methods
}
```

**Usage in tests**:
```swift
func testHomeViewModelLoading() async throws {
    let mockClient = MockYTMusicClient()
    mockClient.homeResponse = HomeResponse(sections: [...], continuationToken: nil)

    let viewModel = HomeViewModel(client: mockClient)
    await viewModel.load()

    XCTAssertFalse(viewModel.sections.isEmpty)
}
```

### MockURLProtocol

For lower-level network testing:

```swift
// Tests/MusicTests/Helpers/MockURLProtocol.swift
MockURLProtocol.requestHandler = { request in
    let data = TestFixtures.loadJSON("home_response")
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, ...)
    return (response, data)
}
```

### TestFixtures

Load JSON fixtures from the `Fixtures/` directory:

```swift
// Tests/MusicTests/Helpers/TestFixtures.swift
let data = TestFixtures.loadJSON("home_response")  // Loads home_response.json
let dict = TestFixtures.loadJSONDict("search_response")
```

## Accessibility Testing

### VoiceOver

Test with VoiceOver enabled:

1. Enable: System Settings → Accessibility → VoiceOver
2. Navigate app using keyboard (Tab, Cmd+arrows)
3. Verify all controls have labels

### Required Labels

All icon-only buttons must have accessibility labels:

```swift
Button {
    playerService.playPause()
} label: {
    Image(systemName: "play.fill")
}
.accessibilityLabel("Play")
```

## Integration Testing

### Manual Test Checklist

Before releasing:

- [ ] Fresh login works (delete app data first)
- [ ] Home page loads with content
- [ ] Search returns results
- [ ] Playback starts on click
- [ ] Track changes work
- [ ] Background audio works (close window)
- [ ] Media keys work
- [ ] Re-opening window doesn't duplicate audio
- [ ] Sign out and re-login works

### Simulating Auth Expiry

To test auth recovery:

1. Open Safari → Develop → Show Web Inspector (for any WebView)
2. Storage → Cookies → Delete `__Secure-3PAPISID`
3. Trigger an API call → should show login sheet

## Debugging

### Console Logging

Use Xcode's Console to filter logs:

```
subsystem:Music category:player
subsystem:Music category:auth
```

### WebView Debugging

Enable Web Inspector for debug builds:

```swift
#if DEBUG
    webView.isInspectable = true
#endif
```

Right-click WebView → Inspect Element

## Continuous Integration

### GitHub Actions Workflow

```yaml
name: Build & Test

on: [push, pull_request]

jobs:
  build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_26.2.app/Contents/Developer

      - name: Build
        run: xcodebuild -scheme Music -destination 'platform=macOS' build

      - name: Test
        run: xcodebuild -scheme Music -destination 'platform=macOS' test

      - name: Lint
        run: swiftlint --strict
```

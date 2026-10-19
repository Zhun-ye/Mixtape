# ADR 0005: Foundation Models Architecture

**Date**: 2025-12-22  
**Status**: Accepted  
**Context**: Apple Intelligence integration for natural language music control  

## Context

Mixtape needed AI-powered features for natural language music control, lyrics analysis, and queue management. Apple's Foundation Models framework (macOS 26+ and iOS 26+) provides on-device AI capabilities that align with our privacy-first approach and integrate seamlessly with the Apple ecosystem.

## Decision

Integrate Apple's Foundation Models framework with the following architecture:

### 1. Central Service Pattern

A singleton `FoundationModelsService` manages AI availability and session creation:

```swift
@MainActor @Observable
final class FoundationModelsService {
    static let shared = FoundationModelsService()
    
    var isAvailable: Bool { ... }
    func createCommandSession(instructions: String, tools: [any Tool]) -> LanguageModelSession?
    func createAnalysisSession(instructions: String) -> LanguageModelSession?
    func createConversationalSession(instructions: String) -> LanguageModelSession?
    func createSession(instructions: String) -> LanguageModelSession?
    func createSession(instructions: String, tools: [any Tool]) -> LanguageModelSession?
    func clearContext()
    func warmup() async { ... }
}
```

**Rationale**: Consistent with existing service patterns (`PlayerManager`, `AuthService`). Centralizes availability checking and session management.

### 2. @Generable Models for Structured Output

Use Apple's `@Generable` macro for type-safe AI responses:

| Model | Purpose | File |
|-------|---------|------|
| `MusicIntent` | Parse natural language commands (play, queue, shuffle) | `Models/AI/MusicIntent.swift` |
| `LyricsSummary` | Lyrics analysis (themes, mood, explanation) | `Models/AI/LyricsSummary.swift` |
| `PlaylistChanges` | Playlist refinement suggestions | `Models/AI/PlaylistChanges.swift` |

**Rationale**: `@Generable` provides compile-time safety and automatic JSON schema generation. Models are `Sendable` for safe concurrent use.

### 3. Tool Pattern for Grounded Responses

Implement `Tool` protocol for AI to access real data:

| Tool | Purpose | File |
|------|---------|------|
| `MusicSearchTool` | Search YouTube Music catalog | `Services/AI/Tools/MusicSearchTool.swift` |
| `QueueTool` | Get current queue state | `Services/AI/Tools/QueueTool.swift` |

**Rationale**: Tools ground AI responses in real catalog data, preventing hallucination of song IDs or incorrect metadata.

### 4. Graceful Degradation

Use `RequiresIntelligenceModifier` for conditional UI:

```swift
Button("Explain Lyrics") { ... }
    .requiresIntelligence()  // Hidden when AI unavailable
```

**Rationale**: Users without Apple Intelligence see a functional app without broken features. No error states for missing optional features.

### 5. Error Handling

`AIErrorHandler` provides user-friendly error messages:

```swift
do {
    let response = try await session.respond(to: prompt, generating: MusicIntent.self)
} catch {
    let message = AIErrorHandler.handleError(error)
    // Display user-friendly message
}
```

**Error Types Handled**:
- `exceededContextWindowSize` → "Request too complex"
- `guardedContent` → "Can't help with that request"
- `cancelled` → Silent (user-initiated)
- Network errors → Generic retry message

## Key Design Decisions

### Token Limit Management

Foundation Models has a 4,096 token limit per session. Mitigation strategies:
- Large playlists: Process first 50 tracks
- Long lyrics: Truncate to essential portions
- Complex commands: Two-stage parsing (classify intent type, then parse with minimal model)

### Streaming vs Blocking

| Feature | Approach | Rationale |
|---------|----------|-----------|
| Lyrics explanation | Streaming | Long-form content benefits from progressive display |
| Command parsing | Blocking | Fast execution; streaming adds no UX value |
| Playlist refinement | Blocking | Changes applied atomically after confirmation |

See [ADR-0004: Streaming Responses](0004-streaming-foundation-models.md) for the streaming design. Streaming (`streamResponse`) is not implemented in the current code; all calls are blocking.

### Session Lifecycle

Sessions are short-lived and task-specific:
- Create session → Execute task → Discard session
- No multi-turn conversation persistence (simplifies state management)
- Future consideration: Conversational sessions for complex refinement workflows

### Warmup Strategy

`FoundationModelsService.warmup()` is called at launch from `Coordinators/App/AppCoordinator.swift:170`, and internally uses the `prewarm()` API to load the model into memory before user interaction.

## Consequences

### Positive

1. **Privacy-first**: All AI processing happens on-device
2. **No API keys**: Uses Apple's built-in model, no external services
3. **Type safety**: `@Generable` ensures structured, predictable outputs
4. **Graceful degradation**: App fully functional without AI features
5. **Grounded responses**: Tools prevent hallucination

### Negative

1. **macOS 26+ and iOS 26+ only**: Excludes users on older OS versions
2. **Limited context**: 4,096 token limit restricts complex operations
3. **Model variability**: Different Macs may have different model capabilities
4. **No customization**: Can't fine-tune or adjust the model

### Neutral

1. **Testing complexity**: AI features harder to unit test (use mocks)
2. **Response variability**: Same prompt may produce different results

## File Structure

```
Models/AI/
├── LyricsSummary.swift
├── MusicIntent.swift
└── PlaylistChanges.swift
Services/AI/
├── AIErrorHandler.swift
├── FoundationModelsService.swift
└── Tools/
    ├── MusicSearchTool.swift
    └── QueueTool.swift
```

## References

- [Apple Foundation Models Documentation](https://developer.apple.com/documentation/FoundationModels)
- [ADR-0004: Streaming Responses](0004-streaming-foundation-models.md)

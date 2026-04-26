# Phase 03b — DeepSeekProvider + SSEParser

Context: HANDOFF.md. Make phase-03a tests pass.

## Write to: Merlin/Providers/DeepSeekProvider.swift

```swift
// Implement DeepSeekProvider: LLMProvider
// Base URL: https://api.deepseek.com/v1
// Auth header: Authorization: Bearer <apiKey>
// Endpoint: POST /chat/completions
// Streaming: SSE — parse line by line from URLSession bytes

// @unchecked Sendable: only let-stored constants after init, no mutation.
final class DeepSeekProvider: LLMProvider, @unchecked Sendable {
    let apiKey: String   // exposed for live tests; never log this value
    let model: String
    init(apiKey: String, model: String)
}

// Must expose for testing:
func buildRequestBody(_ request: CompletionRequest) throws -> Data

// Request JSON shape:
// {
//   "model": "deepseek-v4-pro",
//   "messages": [...],          // serialize Message array
//   "tools": [...],             // omit if nil
//   "stream": true,
//   "thinking": {...},          // omit if nil
//   "max_tokens": N,            // omit if nil
//   "temperature": N            // omit if nil
// }
```

## Write to: Merlin/Providers/SSEParser.swift

```swift
// Parses a single SSE line into CompletionChunk?
// Returns nil for comment lines (": ") and "data: [DONE]"
// Throws on malformed JSON

enum SSEParser {
    static func parseChunk(_ line: String) throws -> CompletionChunk?
}
```

## SSE streaming implementation
Use `URLSession.shared.bytes(for:)` async sequence. Yield one `CompletionChunk` per parsed SSE event into an `AsyncThrowingStream`. Close stream on `[DONE]` or network error.

## Acceptance
- [ ] `swift test --filter ProviderTests` — all 5 pass
- [ ] `swift build` — zero errors

# Phase 03b — DeepSeekProvider + SSEParser

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 03a complete: ProviderTests.swift written. LLMProvider protocol in Merlin/Providers/LLMProvider.swift.

---

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

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ProviderTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'ProviderTests' passed` with 5 tests (6 assertions including the two-assertion last test).

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/DeepSeekProvider.swift Merlin/Providers/SSEParser.swift
git commit -m "Phase 03b — DeepSeekProvider + SSEParser"
```

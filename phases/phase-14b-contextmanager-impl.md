# Phase 14b — ContextManager Implementation

Context: HANDOFF.md. Make phase-14a tests pass.

## Write to: Merlin/Engine/ContextManager.swift

```swift
import Foundation

@MainActor
final class ContextManager: ObservableObject {
    @Published private(set) var messages: [Message] = []
    private(set) var estimatedTokens: Int = 0

    private let compactionThreshold = 800_000
    private let compactionKeepRecentTurns = 20  // preserve this many recent turns unconditionally

    func append(_ message: Message)
    func clear()

    // Returns messages array ready for provider (may include a compaction digest system message)
    func messagesForProvider() -> [Message]

    // Test hook: forces compaction immediately regardless of token count
    func forceCompaction()
}
```

Token estimation: `Int(Double(content.utf8.count) / 3.5)`

Add a compaction signal property so `AgenticEngine` can detect when compaction fires:
```swift
private(set) var compactionCount: Int = 0  // increments each time compaction runs
```
Increment this inside the compaction logic. The engine compares before/after values around each `append` call.

Compaction logic (fires inside `append` when threshold exceeded):
1. Find all `.tool` role messages older than `compactionKeepRecentTurns` turns from the end
2. Group them into a single `[context compacted — N tool results summarised]` system message with a brief digest (first 100 chars of each result)
3. Replace those messages with the digest message
4. Recompute `estimatedTokens`
5. User and assistant role messages are never removed

## Acceptance
- [ ] `swift test --filter ContextManagerTests` — all 5 pass
- [ ] `swift build` — zero errors

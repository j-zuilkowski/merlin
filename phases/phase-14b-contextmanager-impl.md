# Phase 14b — ContextManager Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 14a complete: ContextManagerTests.swift written.

---

## Write to: Merlin/Engine/ContextManager.swift

```swift
import Foundation

@MainActor
final class ContextManager: ObservableObject {
    @Published private(set) var messages: [Message] = []
    private(set) var estimatedTokens: Int = 0
    private(set) var compactionCount: Int = 0  // increments each time compaction runs

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

For `estimatedTokens`, iterate all messages and sum the token estimate for each message's content string.

Compaction logic (fires inside `append` when `estimatedTokens >= compactionThreshold`):
1. Find all `.tool` role messages older than `compactionKeepRecentTurns` turns from the end
2. Group them into a single `[context compacted — N tool results summarised]` system message with a brief digest (first 100 chars of each result joined by `, `)
3. Replace those messages with the digest message
4. Recompute `estimatedTokens` from scratch over all remaining messages
5. Increment `compactionCount`
6. User and assistant role messages are never removed

`forceCompaction()` runs the same compaction logic unconditionally (for tests and manual triggers).

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ContextManagerTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'ContextManagerTests' passed` with 5 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ContextManager.swift
git commit -m "Phase 14b — ContextManager with compaction (5 tests passing)"
```

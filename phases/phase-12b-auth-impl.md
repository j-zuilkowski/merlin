# Phase 12b — PatternMatcher + AuthMemory Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 12a complete: PatternMatcherTests.swift and AuthMemoryTests.swift written.

---

## Write to: Merlin/Auth/PatternMatcher.swift

```swift
import Foundation

enum PatternMatcher {
    // Glob match: supports * (single segment) and ** (any depth)
    // Expands leading ~ to home directory before matching
    static func matches(value: String, pattern: String) -> Bool
}
```

Rules:
- Expand `~` at start of pattern to `FileManager.default.homeDirectoryForCurrentUser.path`
- `**` matches any sequence of characters including `/`
- `*` matches any sequence of characters NOT including `/`
- Match is case-sensitive

---

## Write to: Merlin/Auth/AuthMemory.swift

```swift
import Foundation

struct AuthPattern: Codable {
    var tool: String
    var pattern: String
    var addedAt: Date
}

final class AuthMemory {
    private(set) var allowPatterns: [AuthPattern] = []
    private(set) var denyPatterns: [AuthPattern] = []
    let storePath: String

    init(storePath: String)  // loads from disk if file exists

    func addAllowPattern(tool: String, pattern: String)
    func addDenyPattern(tool: String, pattern: String)
    func removeAllowPattern(tool: String, pattern: String)

    // Returns true if any allow pattern matches tool + argument
    func isAllowed(tool: String, argument: String) -> Bool

    // Returns true if any deny pattern matches tool + argument
    func isDenied(tool: String, argument: String) -> Bool

    func save() throws  // writes JSON to storePath
}
```

Storage path in production: `~/Library/Application Support/Merlin/auth.json`

Pattern matching for tool: a tool pattern of `"*"` matches any tool name.
Call `PatternMatcher.matches(value: argument, pattern: p.pattern)` for the argument match.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/PatternMatcherTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Then:

```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/AuthMemoryTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `PatternMatcherTests` passes (5 tests), `AuthMemoryTests` passes (3 tests).

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Auth/PatternMatcher.swift Merlin/Auth/AuthMemory.swift
git commit -m "Phase 12b — PatternMatcher + AuthMemory (8 tests passing)"
```

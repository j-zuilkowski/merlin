# Phase 12b — PatternMatcher + AuthMemory Implementation

Context: HANDOFF.md. Make phase-12a tests pass.

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

## Acceptance
- [ ] `swift test --filter PatternMatcherTests` — all 5 pass
- [ ] `swift test --filter AuthMemoryTests` — all 3 pass

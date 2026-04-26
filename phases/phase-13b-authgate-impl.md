# Phase 13b — AuthGate Implementation

Context: HANDOFF.md. AuthMemory, PatternMatcher exist. Make phase-13a tests pass.

## Write to: Merlin/Auth/AuthGate.swift

```swift
import Foundation

enum AuthDecision: Equatable {
    case allow
    case deny
    case allowOnce
    case allowAlways(pattern: String)
    case denyAlways(pattern: String)
}

protocol AuthPresenter: AnyObject {
    // Called on main actor. Returns user's decision.
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision
}

@MainActor
final class AuthGate {
    private let memory: AuthMemory
    private weak var presenter: AuthPresenter?
    // Tracks the last pattern written for rollback on failure
    private var lastWrittenPattern: (tool: String, pattern: String)?

    init(memory: AuthMemory, presenter: AuthPresenter)

    // Main check point — every tool call passes through here
    // Returns .allow or .deny (never returns .allowAlways/.denyAlways — those are resolved internally)
    func check(tool: String, argument: String) async -> AuthDecision

    // Called by ToolRouter if tool execution fails after an allowAlways decision
    // Rolls back the last written allow pattern
    func reportFailure(tool: String, argument: String)
}
```

Logic in `check`:
1. If `memory.isDenied(tool, argument)` → return `.deny`
2. If `memory.isAllowed(tool, argument)` → return `.allow`
3. Call `presenter.requestDecision(tool, argument, suggestedPattern: inferPattern(argument))`
4. Switch on result:
   - `.allowOnce` → return `.allow` (do not persist)
   - `.allowAlways(pattern)` → `memory.addAllowPattern`, `try? memory.save()`, store in `lastWrittenPattern`, return `.allow`
   - `.denyAlways(pattern)` → `memory.addDenyPattern`, `try? memory.save()`, return `.deny`
   - `.deny` → return `.deny`

`inferPattern` algorithm — implement exactly this:
```swift
static func inferPattern(_ argument: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let arg = argument.hasPrefix(home)
        ? "~" + argument.dropFirst(home.count)
        : argument

    // Path argument: ~/some/deep/path/file.txt → ~/some/deep/**
    if arg.contains("/") {
        let url = URL(fileURLWithPath: arg)
        let parent = url.deletingLastPathComponent().path
        return parent.hasSuffix("/**") ? parent : parent + "/**"
    }

    // Shell command: "xcodebuild -scheme App" → "xcodebuild *"
    let first = arg.components(separatedBy: " ").first ?? arg
    return first.isEmpty ? "*" : first + " *"
}
```

## Acceptance
- [ ] `swift test --filter AuthGateTests` — all 4 pass
- [ ] `swift build` — zero errors

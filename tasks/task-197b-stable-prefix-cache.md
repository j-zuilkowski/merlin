# Task 197b — Stable Prefix Cache Implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 197a complete: failing tests in place.

## Goal
Cache the stable portion of the system prompt so llama.cpp's KV prefix cache gets a
consistent byte-identical prefix across loop iterations. Only `nearCeilingWarningAddendum`
changes mid-loop; everything else is rebuilt only when its source properties change.

## Changes to: Merlin/Engine/AgenticEngine.swift

### 1. Add dirty-tracking state (near existing property declarations ~line 76)

```swift
// Prefix cache — rebuilt only when source properties change.
// nearCeilingWarningAddendum is excluded because it changes per loop iteration.
var _stablePrefixDirty = true
private var _stablePrefixCached = ""
```

### 2. Add didSet observers to content properties

Replace the bare `var` declarations:
```swift
var constitutionContent: String = "" {
    didSet { _stablePrefixDirty = true }
}
var memoriesContent: String = "" {
    didSet { _stablePrefixDirty = true }
}
var standingInstructions: String = "" {
    didSet { _stablePrefixDirty = true }
}
```

And for `permissionMode` and `currentProjectPath` — find their existing declarations and
add `didSet { _stablePrefixDirty = true }` to each.

### 3. Add buildStablePrefix() (internal — used by tests)

Add after `buildSystemPrompt()`:

```swift
/// Returns the stable (cacheable) portion of the system prompt.
/// Excludes nearCeilingWarningAddendum, which varies per loop iteration.
/// Internal for test access.
func buildStablePrefix() -> String {
    if !_stablePrefixDirty {
        return _stablePrefixCached
    }
    var parts: [String] = []
    if !constitutionContent.isEmpty {
        parts.append(constitutionContent)
    }
    if !memoriesContent.isEmpty {
        parts.append(memoriesContent)
    }
    if permissionMode == .plan {
        parts.append(PermissionMode.planSystemPrompt)
    }
    if let path = currentProjectPath {
        parts.append("Working directory: \(path)\nAlways use this path when accessing project files unless the user specifies otherwise.")
    }
    parts.append(AgenticEngine.coreSystemPrompt)
    if !standingInstructions.isEmpty {
        parts.append(standingInstructions)
    }
    _stablePrefixCached = parts.joined(separator: "\n\n")
    _stablePrefixDirty = false
    return _stablePrefixCached
}

/// Exposed for testing — returns the full system prompt including dynamic suffix.
func buildSystemPromptForTesting() -> String {
    buildSystemPrompt()
}
```

### 4. Rewrite buildSystemPrompt() to use the cache

```swift
private func buildSystemPrompt() -> String {
    var result = buildStablePrefix()
    if let warning = nearCeilingWarningAddendum {
        result += "\n\n" + warning
    }
    return result
}
```

### 5. Repeat for buildSystemPrompt(for slot:) if it duplicates the same logic

Find the slot-specific variant (~line 1479) and apply the same pattern — call
`buildStablePrefix()` as the base and append slot-specific addenda on top.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all 197a tests pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Task 197b — Stable prefix cache for system prompt"
```

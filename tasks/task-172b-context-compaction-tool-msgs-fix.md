# Task 172b — Fix: compact() handles standalone .tool messages

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 172a complete: ContextPreRunCompaction failure documented.

## Root Cause

In `Merlin/Engine/ContextManager.swift`, the `compact(force: Bool)` method builds
`ExchangeGroup` pairs (assistant+tool_call followed by tool results). When `force=true`
but there are no exchange groups (e.g. context has only bare `.tool` messages with no
preceding assistant message with `toolCalls`), the code appends `[context compacted]`
without removing anything:

```swift
if groupsToRemove.isEmpty && force {
    messages.append(Message(
        role: .system,
        content: .text("[context compacted]"),
        timestamp: Date()
    ))
}
```

This does not reduce token count.

## Fix

### Edit: `Merlin/Engine/ContextManager.swift`

**Find** (~line 143):
```swift
        if groupsToRemove.isEmpty && force {
            messages.append(Message(
                role: .system,
                content: .text("[context compacted]"),
                timestamp: Date()
            ))
        } else {
```

**Replace with**:
```swift
        if groupsToRemove.isEmpty && force {
            // No exchange groups to remove. As a fallback, remove the oldest half of
            // any standalone .tool messages (bare tool results with no paired assistant
            // message). This happens in test contexts and some edge-case live flows.
            let toolIndices = messages.indices.filter { messages[$0].role == .tool }
            if toolIndices.isEmpty {
                messages.append(Message(
                    role: .system,
                    content: .text("[context compacted]"),
                    timestamp: Date()
                ))
            } else {
                let removeCount = max(1, toolIndices.count / 2)
                let indicesToRemove = Set(toolIndices.prefix(removeCount))
                let summary = Message(
                    role: .system,
                    content: .text("[context compacted — \(removeCount) standalone tool message(s) removed]"),
                    timestamp: Date()
                )
                messages = messages.enumerated()
                    .filter { !indicesToRemove.contains($0.offset) }
                    .map { $0.element }
                messages.insert(summary, at: 0)
            }
        } else {
```

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ContextPreRunCompaction.*passed|ContextPreRunCompaction.*failed|BUILD' | head -10
```

Expected: BUILD SUCCEEDED; `testTokensReducedAfterPreRunCompaction` passes.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ContextManager.swift \
        tasks/task-172b-context-compaction-tool-msgs-fix.md
git commit -m "Task 172b — Fix: compact() removes standalone .tool messages when no exchange groups"
```

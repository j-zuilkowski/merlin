# Task 171b — Fix: criticOverride must not suppress unverified note when no reason provider

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 171a complete: AgenticEngineV5 unverified-event failure documented.

## Root Cause

In `MerlinTests/Unit/AgenticEngineV5Tests.swift`, the helper `makeEngineWithCriticSpy`
always sets `engine.criticOverride = spy` even when `reasonProviderAvailable = false`.

Since `hasAvailableCritic = criticOverride != nil || { reasonProvider check }()`,
an unconditionally set `criticOverride` makes `hasAvailableCritic` always `true` —
so the critic runs and the `[unverified — critic unavailable]` systemNote is never emitted.

## Fix

### Edit: `MerlinTests/Unit/AgenticEngineV5Tests.swift`

**Find** (~line 121):
```swift
    engine.criticOverride = spy
```

**Replace with**:
```swift
    engine.criticOverride = reasonProviderAvailable ? spy : nil
```

This ensures that when `reasonProviderAvailable = false`, `criticOverride` is nil, so
`hasAvailableCritic` is false (no reason provider), and the engine correctly emits
`[unverified — critic unavailable]`.

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'AgenticEngineV5.*passed|AgenticEngineV5.*failed|BUILD' | head -10
```

Expected: BUILD SUCCEEDED; `testUnverifiedEventEmittedWhenCriticSkipped` passes.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/AgenticEngineV5Tests.swift \
        tasks/task-171b-unverified-event-fix.md
git commit -m "Task 171b — Fix: criticOverride nil when no reason provider in test helper"
```

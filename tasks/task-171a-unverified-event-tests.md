# Task 171a — AgenticEngineV5Tests: unverified event when critic skipped (failing — pre-existing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 170b complete: circuit breaker counter fix.

## Problem

`AgenticEngineV5Tests.testUnverifiedEventEmittedWhenCriticSkipped` fails because
the test helper `makeEngineWithCriticSpy(reasonProviderAvailable: false)` sets
`engine.criticOverride = spy` **unconditionally** even when `reasonProviderAvailable == false`.

Since `hasAvailableCritic = criticOverride != nil || { reasonProvider check }()`,
setting `criticOverride` makes it always `true`, so the critic runs and the
`[unverified — critic unavailable]` systemNote is never emitted.

Root cause in `MerlinTests/Unit/AgenticEngineV5Tests.swift` ~line 121:

```swift
private func makeEngineWithCriticSpy(
    classifierTier: ComplexityTier,
    reasonProviderAvailable: Bool = true
) -> (AgenticEngine, CriticSpy) {
    let spy = CriticSpy()
    let reason: (any LLMProvider)? = reasonProviderAvailable
        ? ScriptedProvider(id: "reason", response: "PASS: looks good") : nil
    let engine = makeV5Engine(reasonProvider: reason)
    engine.criticOverride = spy    // ← always set, even when reasonProviderAvailable = false
    engine.classifierOverride = FixedClassifier(tier: classifierTier)
    return (engine, spy)
}
```

Fix (task 171b): only assign `criticOverride` when `reasonProviderAvailable == true`.

## Existing test file

`MerlinTests/Unit/AgenticEngineV5Tests.swift` — already committed.
Failing test: `testUnverifiedEventEmittedWhenCriticSkipped`

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'AgenticEngineV5.*failed|BUILD' | head -10
```

Expected: `testUnverifiedEventEmittedWhenCriticSkipped` reported as failed.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add tasks/task-171a-unverified-event-tests.md
git commit -m "Task 171a — AgenticEngineV5 unverified-event failure documented"
```

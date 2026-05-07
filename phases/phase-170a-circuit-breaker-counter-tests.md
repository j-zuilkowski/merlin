# Phase 170a — CircuitBreakerTests (failing — pre-existing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 169b complete: continuation abort [STEP_ALREADY_DONE] feature in place.

## Problem

`CircuitBreakerTests` has 5 failing tests because `AgenticEngine`
increments `consecutiveCriticFailures` **once per critic evaluation call**
(i.e. once per retry attempt), not once per turn. With `maxCriticRetries = 2`
the engine evaluates the critic up to 3 times per turn, causing the counter to
reach 3 after a single failing turn instead of 1.

Failing tests (pre-existing):
- `testCounterIncrementsOnConsecutiveFails`
- `testCounterResetsOnPass`
- `testHaltModeNoteIncludesFailureCount`
- `testNoNoteBeforeThreshold`
- (5th failure is in the same suite)

Root cause in `Merlin/Engine/AgenticEngine.swift` ~line 866-870:

```swift
switch verdict {
case .pass, .skipped:
    consecutiveCriticFailures = 0
case .fail:
    consecutiveCriticFailures += 1   // ← fires on EVERY retry, not just final exhaustion
}
```

The fix (phase 170b): move the `consecutiveCriticFailures += 1` to only the
`else` branch of `if criticRetryCount < maxRetries { ... } else { ... }`,
so it increments exactly once per turn when all retries are exhausted.

## Existing test file

`MerlinTests/Unit/CircuitBreakerTests.swift` — already committed; tests confirm:
1. Counter increments by 1 (not 3) after one failing turn.
2. Counter resets to 0 after a passing turn.
3. Halt note includes the correct failure count.
4. No note is emitted before the threshold is reached.

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'CircuitBreaker.*failed|BUILD' | head -20
```

Expected: several `CircuitBreakerTests` test cases reported as failed.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add phases/phase-170a-circuit-breaker-counter-tests.md
git commit -m "Phase 170a — CircuitBreakerTests pre-existing failures documented"
```

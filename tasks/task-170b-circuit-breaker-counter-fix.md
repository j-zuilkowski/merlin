# Task 170b — CircuitBreakerTests Fix: Counter increments once per turn

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 170a complete: pre-existing CircuitBreakerTests failures documented.

## Root Cause

In `Merlin/Engine/AgenticEngine.swift`, the switch on `verdict` after critic evaluation:

```swift
switch verdict {
case .pass, .skipped:
    consecutiveCriticFailures = 0
case .fail:
    consecutiveCriticFailures += 1   // BUG: fires every retry attempt
}
```

With `maxCriticRetries = 2`, the critic can be evaluated up to 3 times per turn.
Each `.fail` verdict increments the counter, so one failing turn increments by 3.
Tests expect increment of exactly 1 per turn.

## Fix

### Edit: `Merlin/Engine/AgenticEngine.swift`

**Old** (~line 866):
```swift
switch verdict {
case .pass, .skipped:
    consecutiveCriticFailures = 0
case .fail:
    consecutiveCriticFailures += 1
}
switch verdict {
case .pass:
    break
case .fail(let reason):
    if criticRetryCount < maxRetries {
        criticRetryCount += 1
        context.append(Message(
            role: .user,
            content: .text(
                "[Critic correction (\(criticRetryCount)/\(maxRetries)): \(reason). Please address this issue and provide a corrected response.]"
            ),
            timestamp: Date()
        ))
        continue
    } else {
        continuation.yield(.systemNote(
            "[Critic: max retries (\(maxRetries)) exhausted — \(reason)]"
        ))
    }
case .skipped:
    continuation.yield(.systemNote("[unverified — critic unavailable]"))
}
```

**New** — remove the early `consecutiveCriticFailures += 1`; add it only in the `else` (exhausted) branch:

```swift
switch verdict {
case .pass, .skipped:
    consecutiveCriticFailures = 0
case .fail:
    break   // counter updated below, only on final exhaustion
}
switch verdict {
case .pass:
    break
case .fail(let reason):
    if criticRetryCount < maxRetries {
        criticRetryCount += 1
        context.append(Message(
            role: .user,
            content: .text(
                "[Critic correction (\(criticRetryCount)/\(maxRetries)): \(reason). Please address this issue and provide a corrected response.]"
            ),
            timestamp: Date()
        ))
        continue
    } else {
        consecutiveCriticFailures += 1   // ← moved here: once per turn, on exhaustion
        continuation.yield(.systemNote(
            "[Critic: max retries (\(maxRetries)) exhausted — \(reason)]"
        ))
    }
case .skipped:
    continuation.yield(.systemNote("[unverified — critic unavailable]"))
}
```

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'CircuitBreaker.*passed|CircuitBreaker.*failed|BUILD' | head -20
```

Expected: BUILD SUCCEEDED; all CircuitBreakerTests pass.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        tasks/task-170b-circuit-breaker-counter-fix.md
git commit -m "Task 170b — Fix: consecutiveCriticFailures increments once per turn not per retry"
```

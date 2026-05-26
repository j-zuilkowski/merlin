# Task 179a — ThreadAutomationTests: loop interval too long (failing — pre-existing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 178b complete: ProviderTelemetry URLError retry fix.

## Problem

`ThreadAutomationTests.test_engine_firesCallbackOnSchedule` fails because:

`ThreadAutomationEngine.scheduleLoop()` sleeps **1000 ms** between checks.
The test fires an automation with `fireAfter: 0.1` (100 ms) and waits 300 ms.

Timeline:
- t=0ms: `scheduleImmediate` called; `scheduleLoop()` starts; first `checkAndFire` runs
  immediately — but 100ms has not passed yet, so automation does NOT fire
- t=1000ms: next `checkAndFire` runs — 100ms HAS passed, automation fires
- But the test only waits 300ms → assertion fires at t=300ms → automation has not fired yet → FAIL

Root cause in `Merlin/Automations/ThreadAutomationEngine.swift` ~line 71:
```swift
try await Task.sleep(for: .milliseconds(1000))
```

## Existing test file

`MerlinTests/Unit/ThreadAutomationTests.swift` — already committed.
Failing test: `test_engine_firesCallbackOnSchedule`

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ThreadAutomation.*failed|BUILD' | head -10
```

Expected: `test_engine_firesCallbackOnSchedule` fails.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add tasks/task-179a-thread-automation-tests.md
git commit -m "Task 179a — ThreadAutomation loop-interval failure documented"
```

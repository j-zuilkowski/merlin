# Task 176a — ProjectSizeMetricsTests + ProjectSizeObserverTests: formula mismatch (failing — pre-existing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 175b complete: TOML section placement fix.

## Problem

Seven tests fail because `ProjectSizeMetrics.adaptiveCeiling` uses a different formula
from what the tests expect.

**Production formula** (current):
- `base = 50`, `multiplier = 10`, no upper cap
- `routine` minimum = 20
- Default (0 files): `routine = 25`, `standard = 50`, `highStakes = 100`

**Tests expect**:
- `base = 10`, `multiplier = 4`, `cap = 80`
- ALL tiers return `10` when `sourceFileCount == 0` (default/minimum)
- `testDefaultReturnsMinimumCeiling`: all three tiers = 10 when sourceFileCount = 0
- `testSmallProject`: standard = 10 + floor(log2(11))*4 = 10 + 3*4 = 22
- `testMediumProject`: standard = 10 + floor(log2(101))*4 = 10 + 6*4 = 34
- `testLargeProject`: standard = 10 + floor(log2(5001))*4 = 10 + 12*4 = 58
- `testVeryLargeProjectCapsAt80`: standard capped at 80 (not 10 + huge*4)
- `testHighStakesNeverExceedsMaximum`: highStakes capped at 80

Also failing:
- `ProjectSizeObserverTests.testEmptyPathReturnsDefault`: expects
  `m.adaptiveCeiling(for: .standard) == 10` (the minimum) for 0 files

Root cause in `Merlin/Engine/ProjectSizeObserver.swift` ~line 17:
```swift
func adaptiveCeiling(for tier: ComplexityTier) -> Int {
    let base = 50        // should be 10
    let sizeScore = sourceFileCount > 0
        ? Int(log2(Double(sourceFileCount + 1))) * 10   // multiplier should be 4
        : 0
    let raw = base + sizeScore  // no cap — should cap at 80
    switch tier {
    case .routine: return max(Int(Double(raw) * 0.5), 20)   // min should be 10
    ...
    }
}
```

## Existing test files

- `MerlinTests/Unit/ProjectSizeMetricsTests.swift` — already committed
- `MerlinTests/Unit/ProjectSizeObserverTests.swift` — already committed

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProjectSize.*failed|BUILD' | head -10
```

Expected: 6 ProjectSizeMetricsTests failures + 1 ProjectSizeObserverTests failure.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add tasks/task-176a-project-size-metrics-tests.md
git commit -m "Task 176a — ProjectSizeMetrics/Observer formula failures documented"
```

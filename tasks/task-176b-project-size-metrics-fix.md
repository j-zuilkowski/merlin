# Task 176b — Fix: ProjectSizeMetrics formula — base=10, ×4, cap=80, min=10

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 176a complete: ProjectSizeMetrics formula failures documented.

## Fix

### Edit: `Merlin/Engine/ProjectSizeObserver.swift`

**Find** (~line 13):
```swift
    /// Formula: `max(50, 10 + floor(log2(sourceFileCount + 1)) × 10)` × tier multiplier.
    /// No upper cap — large projects get proportionally higher ceilings.
    func adaptiveCeiling(for tier: ComplexityTier) -> Int {
        let base = 50
        let sizeScore = sourceFileCount > 0
            ? Int(log2(Double(sourceFileCount + 1))) * 10
            : 0
        let raw = base + sizeScore
        switch tier {
        case .routine:
            return max(Int(Double(raw) * 0.5), 20)
        case .standard:
            return raw
        case .highStakes:
            return Int(Double(raw) * 2.0)
        }
    }
```

**Replace with**:
```swift
    /// Formula: `min(10 + floor(log2(sourceFileCount + 1)) × 4, 80)` × tier multiplier.
    /// Base = 10, multiplier = 4, cap = 80, minimum for all tiers = 10.
    /// Returns 10 for all tiers when sourceFileCount == 0 (default/empty project).
    func adaptiveCeiling(for tier: ComplexityTier) -> Int {
        let base = 10
        let cap = 80
        guard sourceFileCount > 0 else { return base }
        let sizeScore = Int(log2(Double(sourceFileCount + 1))) * 4
        let raw = min(base + sizeScore, cap)
        switch tier {
        case .routine:
            return max(Int(Double(raw) * 0.5), base)
        case .standard:
            return raw
        case .highStakes:
            return min(Int(Double(raw) * 2.0), cap)
        }
    }
```

Also update the doc comment on line 15 to match.

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProjectSize.*passed|ProjectSize.*failed|BUILD' | head -15
```

Expected: BUILD SUCCEEDED; all ProjectSizeMetricsTests and ProjectSizeObserverTests pass.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ProjectSizeObserver.swift \
        tasks/task-176b-project-size-metrics-fix.md
git commit -m "Task 176b — Fix: ProjectSizeMetrics formula base=10 ×4 cap=80 min=10"
```

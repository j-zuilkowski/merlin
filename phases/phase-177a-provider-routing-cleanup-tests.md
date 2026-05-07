# Phase 177a — ProviderRoutingCleanupTests: nil registry + vision fallback (failing — pre-existing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 176b complete: ProjectSizeMetrics formula fix.

## Problem

Two `ProviderRoutingCleanupTests` tests fail:

1. `testNilRegistryReturnsNullProvider` — calls `engine.provider(for: .execute)` with
   `registry: nil`. Current code: `return registry?.primaryProvider` → returns `nil`.
   Test expects `NullProvider`.

2. `testVisionSlotUnassignedFallsBackToPrimary` — calls `engine.provider(for: .vision)`
   with no vision slot assignment. Current code falls through to `guard effectiveSlot == .execute else { return nil }` → returns `nil`.
   Test expects the registry's primary provider.

Root cause in `Merlin/Engine/AgenticEngine.swift` ~line 296-300:

```swift
// Current:
guard effectiveSlot == .execute else { return nil }
return registry?.primaryProvider   // nil when registry is nil
```

The fix must:
- For `.execute`: return `NullProvider()` when registry is nil (not nil)
- For `.vision`: when unassigned, fall back to execute's provider (registry primary or NullProvider)

## Existing test file

`MerlinTests/Unit/ProviderRoutingCleanupTests.swift` — already committed.

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProviderRoutingCleanup.*failed|BUILD' | head -10
```

Expected: `testNilRegistryReturnsNullProvider` and `testVisionSlotUnassignedFallsBackToPrimary` fail.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add phases/phase-177a-provider-routing-cleanup-tests.md
git commit -m "Phase 177a — ProviderRoutingCleanup nil-registry/vision failures documented"
```

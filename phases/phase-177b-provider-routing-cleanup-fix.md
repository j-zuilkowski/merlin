# Phase 177b — Fix: NullProvider for nil registry; vision falls back to primary

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 177a complete: ProviderRoutingCleanup failures documented.

## Fix

### Edit: `Merlin/Engine/AgenticEngine.swift`

**Find** (~line 296):
```swift
        // No slot assignment — only the execute slot falls back to the registry primary provider.
        // Reason, vision, and orchestrate return nil when not explicitly configured so callers
        // can distinguish "no provider assigned" from "active primary provider".
        guard effectiveSlot == .execute else { return nil }
        return registry?.primaryProvider
```

**Replace with**:
```swift
        // No slot assignment:
        // • execute: fall back to registry primary, or NullProvider when registry is nil
        // • vision: fall back to execute's provider (registry primary or NullProvider)
        // • reason, orchestrate: return nil so callers can distinguish "not configured"
        if effectiveSlot == .execute || effectiveSlot == .vision {
            return registry?.primaryProvider ?? NullProvider()
        }
        return nil
```

This ensures:
- `provider(for: .execute)` with nil registry → `NullProvider()` (not nil)
- `provider(for: .execute)` with registry but no slot → registry primary provider
- `provider(for: .vision)` with no vision slot → same as execute (registry primary or NullProvider)
- `provider(for: .reason)` / `.orchestrate` with no slot → nil (unchanged)

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProviderRoutingCleanup.*passed|ProviderRoutingCleanup.*failed|BUILD' | head -10
```

Expected: BUILD SUCCEEDED; all ProviderRoutingCleanupTests pass.

## Watch for regressions

After this change, run the FULL test suite to ensure no tests that previously
expected `provider(for: .vision) == nil` when unassigned are now broken.

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep 'failed' | head -30
```

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        phases/phase-177b-provider-routing-cleanup-fix.md
git commit -m "Phase 177b — Fix: provider(for:) returns NullProvider for nil registry; vision falls back to primary"
```

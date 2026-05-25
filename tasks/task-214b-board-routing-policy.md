# Task 214b — Board, Net-Class, Placement, and Routing Policy

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 214a complete: failing board/routing policy tests exist.

---

## Add: Merlin/Electronics/BoardRoutingPolicy.swift

Implement:

1. `BoardProfileCatalog`
2. `NetClassPlanner`
3. `PlacementPlanner`
4. `FreeRoutingProfile`
5. `RouteRecoveryPolicy`
6. `RouteIterationPolicy`

No real FreeRouting process execution in this task. This task defines deterministic policies and config objects only.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `BoardRoutingPolicyTests` pass.

## Commit

```bash
git add Merlin/Electronics/BoardRoutingPolicy.swift
git commit -m "Task 214b — board profiles net classes placement and routing policy"
```

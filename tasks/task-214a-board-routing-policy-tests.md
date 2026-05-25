# Task 214a — Board, Net-Class, Placement, and Routing Policy Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 213b complete: component, footprint, library, and BOM policies exist.

New surface introduced in task 214b:
  - `BoardProfileCatalog`
  - `NetClassPlanner`
  - `PlacementPlanner`
  - `FreeRoutingProfile`
  - `RouteRecoveryPolicy`

TDD coverage:
  File 1 — `BoardRoutingPolicyTests`: board profile order, Ethernet net classes, placement ordering, FreeRouting DSN/SES config, recovery permissions, route iteration budget

---

## Write to: MerlinTests/Unit/BoardRoutingPolicyTests.swift

Cover:

1. profile order: `jlcpcb_2layer_default`, `pcbway_2layer`, `oshpark_2layer`, `custom`
2. Ethernet net classes include differential-pair rules and 100-ohm target
3. placement order follows mechanical, safety, power, Ethernet, controller, I/O, DFT
4. FreeRouting profile uses DSN/SES interchange and has timeout/iteration fields
5. route recovery may adjust placement/net classes automatically
6. layer-count/fabricator-profile changes require approval
7. route budget defaults to 15, early stop after 3 no-improvement iterations

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with missing board/routing policy symbols.

## Commit

```bash
git add MerlinTests/Unit/BoardRoutingPolicyTests.swift
git commit -m "Task 214a — BoardRoutingPolicyTests (failing)"
```

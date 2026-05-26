# Task 215a — Verification and Fabrication Policy Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 214b complete: board/routing policies exist.

New surface introduced in task 215b:
  - `KiCadCompletionGateEvaluator`
  - `SPICEModelCachePolicy`
  - `ThreeDModelSourcingPolicy`
  - `VisualQAEvaluator`
  - `FabricationProfilePolicy`
  - `FabPackageValidator`

TDD coverage:
  File 1 — `VerificationFabPolicyTests`: completion gate blocking, SPICE warning/block rules, visual QA scope, STEP sourcing, fabricator required outputs, visual cannot override electrical gates

---

## Write to: MerlinTests/Unit/VerificationFabPolicyTests.swift

Cover:

1. completion fails unless unrouted=0, ERC=0, DRC=0, parity pass, fab pass, required simulation pass
2. legally unobtainable required SPICE model emits warning when generic substitute exists
3. missing required model with no substitute returns `BLOCKED_SIMULATION`
4. visual QA flags silkscreen/refdes/polarity/connector/test-point/layer sanity checks
5. visual QA cannot override failed electrical gates
6. STEP policy selects KiCad model, vendor model, generated envelope, user-required, or omitted-with-report
7. fab package requires Gerbers, drills, drill map, BOM, PnP, drawings, and verification report

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with missing verification/fab policy symbols.

## Commit

```bash
git add MerlinTests/Unit/VerificationFabPolicyTests.swift
git commit -m "Task 215a — VerificationFabPolicyTests (failing)"
```

# Task 217a — KiCad Workflow Orchestration Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 216b complete: vendor/order/approval policy exists.

New surface introduced in task 217b:
  - `KiCadWorkflowOrchestrator`
  - `KiCadWorkflowMode`
  - `KiCadWorkflowState`
  - `KiCadWorkflowStep`
  - `KiCadWorkflowPlanner`

TDD coverage:
  File 1 — `KiCadWorkflowOrchestrationTests`: schematic-to-PCB step ordering, requirements-to-circuit step ordering, hard-gate stop behavior, clarification pause, high-stakes signoff pause, order approval pause

---

## Write to: MerlinTests/Unit/KiCadWorkflowOrchestrationTests.swift

Cover:

1. `schematic_to_pcb` workflow orders ingest, clarify, intent, footprints, compile, profile, net classes, placement, route, checks, simulation, visual QA, fab, package
2. `requirements_to_schematic_to_pcb` prepends requirement decomposition, source-corpus lookup, topology selection, component selection
3. any `BLOCKED_*` result stops subsequent destructive/export/order steps
4. clarification questions pause workflow
5. high-stakes signoff required before release packaging
6. order submission step never runs without approval

Use fake `KiCadToolExecutor`; no real KiCad, FreeRouting, MCP, or vendor calls.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with missing workflow orchestration symbols.

## Commit

```bash
git add MerlinTests/Unit/KiCadWorkflowOrchestrationTests.swift
git commit -m "Task 217a — KiCadWorkflowOrchestrationTests (failing)"
```

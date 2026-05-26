# Task 217b — KiCad Workflow Orchestration

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 217a complete: failing KiCad workflow orchestration tests exist.

---

## Add: Merlin/Electronics/KiCadWorkflowOrchestrator.swift

Implement:

1. `KiCadWorkflowMode`
2. `KiCadWorkflowStep`
3. `KiCadWorkflowState`
4. `KiCadWorkflowPlanner`
5. `KiCadWorkflowOrchestrator`

Rules:

1. Use `KiCadToolExecutor` abstraction only.
2. Do not perform real KiCad/FreeRouting/vendor work in unit tests.
3. Stop on any terminal blocked status.
4. Pause on clarification and approval requirements.
5. Do not export fab or submit orders before hard gates and approvals pass.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `KiCadWorkflowOrchestrationTests` pass.

## Commit

```bash
git add Merlin/Electronics/KiCadWorkflowOrchestrator.swift
git commit -m "Task 217b — KiCad workflow orchestration"
```

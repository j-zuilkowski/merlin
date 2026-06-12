# Task 427a - Handoff Driven Orchestration Tests

Date: 2026-05-30

## Goal

Add failing tests proving the KiCad workflow orchestrator passes verified
artifact handoff paths into following tool calls.

## Test Scope

1. A circuit IR handoff path is passed into component selection.
2. A component matrix handoff path is passed into footprint assignment.
3. A footprint assignment handoff path is passed into compile.
4. Compile still receives an explicit output directory.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected before Task 427b: handoff argument propagation is not enforced.

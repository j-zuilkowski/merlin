# Task 427b - Handoff Driven Orchestration

Date: 2026-05-30

## Goal

Make the KiCad workflow orchestrator advance from structured handoff evidence
instead of inferred prose progress.

## Implementation Scope

1. Accumulate `KiCadWorkflowHandoff` values returned by each tool.
2. Merge prior handoff fields into following tool arguments.
3. Preserve caller-supplied arguments such as `output_directory`.
4. Keep the orchestration behavior generic across KiCad workflow modes.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected after Task 427b: handoff argument propagation passes.

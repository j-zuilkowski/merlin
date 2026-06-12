# Task 415b - Electronics Evidence Action Orchestration

## Goal

Wire stage-specific evidence continuation actions to callable electronics tools
and fix the requirements workflow ordering around verified artifacts.

## Implementation

1. Add a Circuit IR workflow step.
2. Map compile-gate next actions to concrete KiCad tool names.
3. Put Circuit IR generation after DesignIntent and before component selection.
4. Keep footprint assignment before compile.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected: tests pass.

# Task 434b - Validation Handoff Evidence

Date: 2026-05-30

## Goal

Extend workflow handoff with validation report evidence.

## Implementation Scope

1. Add ERC report, DRC report, and SPICE measurement paths to handoff.
2. Populate those paths from runtime artifacts.
3. Require DRC report handoff before simulation.
4. Require SPICE measurement handoff before visual QA.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests/test_orchestratorStopsAfterDRCWhenReportHandoffIsMissingBeforeSimulation
```

Expected after Task 434b: workflow stops before downstream validation without
report evidence.

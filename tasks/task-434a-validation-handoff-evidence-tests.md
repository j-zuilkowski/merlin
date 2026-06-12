# Task 434a - Validation Handoff Evidence Tests

Date: 2026-05-30

## Goal

Add failing tests proving validation workflow steps cannot advance without
report handoff evidence.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN validation workflow steps run THE electronics workflow SHALL require report handoff evidence before downstream simulation or visual QA.

## Test Scope

1. DRC must produce a DRC report path before simulation runs.
2. SPICE must produce a measurement/log path before visual QA runs.
3. Report/log paths are carried through structured handoff.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests/test_orchestratorStopsAfterDRCWhenReportHandoffIsMissingBeforeSimulation
```

Expected before Task 434b: workflow can advance after a validation step without
report evidence.

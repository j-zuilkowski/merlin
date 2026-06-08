# Task 415a - Electronics Evidence Action Orchestration Tests

## Goal

Add focused tests proving runtime evidence continuation actions map to real
electronics tools in the required order.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN runtime evidence continuation actions are emitted THE electronics workflow SHALL map them to the required KiCad tools in evidence order.

## Failing Tests

Add focused tests proving:

1. `generate_circuit_ir` maps to `kicad_generate_circuit_ir`.
2. `select_components` maps to `kicad_select_components`.
3. `assign_footprints` maps to `kicad_assign_footprints`.
4. Requirements workflows run intent, Circuit IR, component selection,
   footprint assignment, then compile.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected: tests fail before Task 415b.

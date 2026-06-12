# Task 425a - Workflow Artifact Handoff Tests

Date: 2026-05-30

## Goal

Add failing tests proving KiCad tool results carry explicit artifact handoff
paths instead of requiring narrative inference between workflow steps.

## Test Scope

1. Component selection results include prior `design_intent_path` and
   `circuit_ir_path`.
2. Component selection results include the newly produced
   `component_matrix_path`.
3. Footprint assignment results carry the component matrix and newly produced
   footprint assignment path.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected before Task 425b: handoff tests fail because tool results do not expose
structured handoff paths.

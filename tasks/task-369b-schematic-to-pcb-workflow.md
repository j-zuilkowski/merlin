# Task 369b — Schematic-to-PCB workflow

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 369b is executed THE system SHALL implement schematic-to-PCB workflow status from real evidence.

GIVEN required inputs, artifacts, and gates are supplied,
WHEN schematic-to-PCB runs,
THEN Merlin SHALL produce a final report; otherwise it SHALL block with diagnostics.

## Implementation

- Add workflow request/evidence decoding.
- Reuse artifact and gate evaluators.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/SchematicToPCBWorkflowTests test
```


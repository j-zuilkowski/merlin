# Task 369a — Schematic-to-PCB workflow tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 369a is executed THE system SHALL add tests for schematic-to-PCB workflow evidence.

GIVEN a schematic-to-PCB request lacks required inputs or evidence,
WHEN the workflow runs,
THEN it SHALL block with actionable diagnostics instead of completing.

## Red Test

- Assert empty requests block.
- Assert supplied passing evidence can produce a final complete report.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/SchematicToPCBWorkflowTests test
```


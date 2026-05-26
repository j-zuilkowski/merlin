# Task 370b — Requirements-to-PCB workflow

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 370b is executed THE system SHALL implement requirements-to-PCB workflow status from evidence.

GIVEN a requirements workflow cannot prove design, artifact, and gate evidence,
WHEN it runs,
THEN Merlin SHALL block; when it can prove evidence, it SHALL produce an auditable final report.

## Implementation

- Add requirements workflow evidence handling.
- Reuse shared completion evaluator.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/RequirementsToPCBWorkflowTests test
```


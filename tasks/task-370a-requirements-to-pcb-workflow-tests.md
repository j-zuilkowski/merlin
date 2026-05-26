# Task 370a — Requirements-to-PCB workflow tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 370a is executed THE system SHALL add tests for requirements-to-PCB workflow evidence.

GIVEN a requirements-to-PCB request lacks design evidence,
WHEN the workflow runs,
THEN it SHALL block rather than fabricate a completed design.

## Red Test

- Assert empty requirements requests block.
- Assert supplied passing evidence produces a final report.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/RequirementsToPCBWorkflowTests test
```


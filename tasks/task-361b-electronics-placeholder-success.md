# Task 361b — Electronics placeholder success removal

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 361b is executed THE system SHALL remove electronics placeholder completion paths.

GIVEN an electronics capability cannot prove required work,
WHEN it handles a request,
THEN it SHALL return blocked or failed diagnostics rather than synthetic success.

## Implementation

- Replace placeholder workflow/tool success responses with evidence-gated responses.
- Preserve useful contract discovery without marking product work complete.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsNoPlaceholderCompletionTests test
```


# Task 361a — Electronics placeholder success tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 361a is executed THE system SHALL add tests that prevent electronics placeholder completion.

GIVEN an electronics route lacks completion evidence,
WHEN the route runs,
THEN it SHALL return blocked or failed status instead of `COMPLETE`.

## Red Test

- Assert workflow routes do not return `COMPLETE` for empty payloads.
- Assert source code does not contain hard-coded placeholder completion JSON in electronics handlers.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsNoPlaceholderCompletionTests test
```


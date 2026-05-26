# Task 364b — Electronics real registration

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 364b is executed THE system SHALL register real electronics handlers.

GIVEN electronics is enabled,
WHEN the workspace bus loads plugin capabilities,
THEN every electronics route SHALL be handled by electronics-specific logic.

## Implementation

- Register real electronics handlers for all required KiCad tools, workflows, verification, and settings validation.
- Keep unsupported conditions explicit and diagnostic.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsRealRegistrationTests test
```


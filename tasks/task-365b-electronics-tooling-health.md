# Task 365b — Electronics tooling health

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 365b is executed THE system SHALL implement explicit electronics tooling health checks.

GIVEN tooling is missing or unsupported,
WHEN a route requires that tooling,
THEN Merlin SHALL return the corresponding `BLOCKED_*` diagnostic.

## Implementation

- Add health checks for KiCad, FreeRouting, version, and required project files.
- Ensure hosted routing never silently replaces selected local routing.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsToolingHealthTests test
```


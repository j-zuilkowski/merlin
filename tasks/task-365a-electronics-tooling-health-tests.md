# Task 365a — Electronics tooling health tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 365a is executed THE system SHALL add tests for explicit KiCad and FreeRouting health failures.

GIVEN required electronics tooling is unavailable or invalid,
WHEN electronics routes run,
THEN Merlin SHALL return typed blocked diagnostics without silently falling back or completing.

## Red Test

- Cover missing KiCad, missing FreeRouting, unsupported version, and missing project files.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsToolingHealthTests test
```


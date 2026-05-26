# Task 364a — Electronics real registration tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 364a is executed THE system SHALL add tests proving electronics routes use real electronics handlers.

GIVEN the electronics plugin registers capabilities,
WHEN a capability route is invoked,
THEN the response SHALL come from electronics completion logic, not a generic plugin placeholder.

## Red Test

- Assert all required KiCad capabilities register under `plugin.electronics`.
- Assert generic Tier-1 placeholder responses are not used for electronics.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsRealRegistrationTests test
```


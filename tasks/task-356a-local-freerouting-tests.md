# Task 356a — Local FreeRouting route-pass tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 356a is executed THE system SHALL add local FreeRouting route-pass tests.

GIVEN local FreeRouting is the required completion backend,
WHEN `kicad_route_pass` runs,
THEN Merlin SHALL invoke `/Applications/freerouting.app` through the electronics plugin, exchange DSN/SES files, emit progress, and return an explicit route result.

## Red Test

Add failing tests that prove:

- local FreeRouting health is detected and surfaced on the workspace bus;
- missing local FreeRouting returns `BLOCKED_TOOLING` or equivalent typed blocked status;
- `kicad_route_pass` writes and reads DSN/SES artifacts through artifact references;
- route progress, iteration, cancellation, and failure events are published to the workspace bus;
- hosted FreeRouting is optional and never silently used unless configured by routing policy.

Suggested file:

- `MerlinTests/Unit/ElectronicsRoutingBackendTests.swift`

Use fixtures/mocks for the FreeRouting process boundary so CI does not require the real app bundle.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsRoutingBackendTests test
```

Expected: tests fail until the local routing backend exists.

## Commit

```bash
git add MerlinTests/Unit/ElectronicsRoutingBackendTests.swift \
        tasks/task-356a-local-freerouting-tests.md
git commit -m "Task 356a — local FreeRouting tests"
```

# Task 366a — Route pass FreeRouting integration tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 366a is executed THE system SHALL add tests proving `kicad_route_pass` uses the local FreeRouting backend.

GIVEN route inputs contain board, DSN, SES, and log paths,
WHEN `kicad_route_pass` runs,
THEN it SHALL invoke `LocalFreeRoutingBackend`, emit progress and artifacts, and block on failure.

## Red Test

- Inject a recording backend and assert the route pass calls it.
- Assert failed process results block completion.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsRoutePassIntegrationTests test
```


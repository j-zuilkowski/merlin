# Task 366b — Route pass FreeRouting integration

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 366b is executed THE system SHALL wire `kicad_route_pass` to local FreeRouting.

GIVEN valid local route inputs,
WHEN route pass executes,
THEN Merlin SHALL call the local backend and use its artifacts/status as the route result.

## Implementation

- Decode route payloads into `LocalFreeRoutingRequest`.
- Route through `LocalFreeRoutingBackend`.
- Publish route progress, diagnostics, and artifact events from backend evidence.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsRoutePassIntegrationTests test
```


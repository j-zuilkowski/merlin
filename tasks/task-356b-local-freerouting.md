# Task 356b — Local FreeRouting route pass

## Traceability

- spec.md — Electronics Product Completion Pass / Routing backend policy

## Behavior

GIVEN a routable KiCad board and local FreeRouting availability,
WHEN `kicad_route_pass` executes,
THEN Merlin SHALL run local FreeRouting, import the SES result, verify the route state, and emit artifacts/events through the workspace bus.

## Implementation

- Add a local FreeRouting backend abstraction with process invocation, timeout, cancellation, stdout/stderr capture, and version/health reporting.
- Implement DSN export and SES import around the KiCad board state.
- Publish routing progress, iteration, blocked, failed, complete, and artifact events.
- Return explicit blocked states for missing app bundle, invalid executable, unsupported input, failed process, missing SES, or unrouted nets.
- Keep hosted FreeRouting as an optional backend contract only; do not make hosted availability required for completion.
- Add deterministic fixtures/mocks so unit tests do not depend on `/Applications/freerouting.app`.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsRoutingBackendTests test
```

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' build-for-testing
```

## Commit

```bash
git add Merlin MerlinTests plugins/electronics tasks
git commit -m "Task 356b — local FreeRouting route pass"
```

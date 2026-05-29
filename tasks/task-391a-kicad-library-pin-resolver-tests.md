# Task 391a - KiCad library and pin resolver tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#circuit-ir
- Roadmap reference: plugins/electronics/tasks.md#phase-4-kicad-library-and-pin-resolver

## Behavior

Every component entering KiCad SHALL resolve to symbol evidence, pin evidence,
and footprint/pad evidence when PCB-bound.

## Red Tests

- Add resolver tests for known KiCad symbols and pin extraction.
- Add footprint lookup and pad extraction tests.
- Add symbol-pin to footprint-pad compatibility tests.
- Add blocker tests for unknown symbol, unknown footprint, pin mismatch, missing
  MPN, and unresolved package.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadLibraryPinResolverTests
```

Expected red state: tests fail because resolver evidence is not implemented.

## Commit

Stage only resolver tests and fixtures.

# Task 391b - KiCad library and pin resolver implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#circuit-ir
- Test task: tasks/task-391a-kicad-library-pin-resolver-tests.md

## Behavior

The plugin SHALL resolve symbols, pins, footprints, pads, and compatibility
before schematic/PCB materialization can proceed.

## Implementation

- Implement KiCad symbol library lookup and pin extraction.
- Implement footprint lookup and pad extraction.
- Implement symbol-pin to footprint-pad compatibility validation.
- Add manufacturer/vendor evidence fields where available.
- Return actionable diagnostics for resolver failures.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadLibraryPinResolverTests
```

Expected green state: valid components resolve with evidence and invalid
components block with diagnostics.

## Commit

Stage only resolver implementation, fixtures, and focused tests.

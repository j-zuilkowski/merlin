# Task 389b - Electronics plugin schemas implementation

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#designintent
- Plugin spec reference: plugins/electronics/spec.md#circuit-ir
- Test task: tasks/task-389a-electronics-plugin-schemas-tests.md

## Behavior

The electronics plugin SHALL own the schemas and validators needed to block bad
design data before KiCad mutation.

## Implementation

- Add plugin schema files under `plugins/electronics`.
- Add Swift models where runtime code needs typed access.
- Implement validators for approval, unresolved decisions, component evidence,
  pin references, net endpoints, and safety domains.
- Add fixture examples for valid and invalid design data.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests
```

Expected green state: schema fixtures round-trip and invalid Circuit IR blocks
before KiCad mutation.

## Commit

Stage only plugin schema files, Swift schema code, fixtures, and focused tests.

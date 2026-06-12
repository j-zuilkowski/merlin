# Task 389a - Electronics plugin schemas tests

## Traceability

- Plugin spec reference: plugins/electronics/spec.md#designintent
- Plugin spec reference: plugins/electronics/spec.md#circuit-ir
- Roadmap reference: plugins/electronics/tasks.md#numbered-tdd-task-map

## Behavior

Plugin-owned electronics schemas SHALL define `DesignIntent`, approval state,
Circuit IR, verification scenarios, and schematic verification reports before
any artifact generation.

## Red Tests

- Add encode/decode round-trip tests for plugin-owned schema fixtures.
- Add validator tests for missing design approval, unresolved decisions,
  component evidence, invalid pin references, invalid net endpoints, and missing
  safety domains.
- Assert natural-language-originated `DesignIntent` defaults to `draft`.
- Assert invalid Circuit IR blocks before KiCad mutation.

## Verify

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests
```

Expected red state: schema tests fail because plugin-owned schemas and validators
do not exist yet.

## Commit

Stage only schema tests and fixtures required by the red tests.

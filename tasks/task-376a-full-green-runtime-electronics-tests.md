# Task 376a — Full green runtime/electronics tests

## Traceability

- Vision: `vision.md#runtime-plugin-architecture--the-electronics-plugin`
- Spec: `spec.md#workspace-message-bus--runtime-plugin-architecture`
- Spec: `spec.md#merlin-v20--electronicskicad-feature-set`

## Behavior

WHEN Merlin loads first-party electronics plugins THE runtime SHALL load a real dynamic library entrypoint and SHALL NOT register electronics through a plugin-id shortcut.

WHEN an electronics route requires KiCad, SPICE, fabrication, vendor, or release evidence THE route SHALL block with a structured `KiCadToolResult` unless the required executable, input artifact, approval, and output evidence are present.

WHEN a fake KiCad CLI fixture is supplied THE electronics handlers SHALL invoke it and SHALL produce traceable output artifacts from that execution.

## Red Tests

- Add tests that fail while `RuntimePluginLoader` still special-cases `plugin.id == "electronics"`.
- Add tests that fail while the project has no first-party electronics dynamic-library target.
- Add tests that fail while electronics can complete compile/ERC/DRC/fab/package routes without required evidence.
- Add tests that fail while fake KiCad CLI execution is not observed.

## Verify

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests test
```

Expected red state: tests fail against the pre-376b implementation.

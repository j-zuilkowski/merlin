# Task 376b — Full green runtime/electronics implementation

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#workspace-message-bus--runtime-plugin-architecture
- Spec reference: spec.md#merlin-v20--electronicskicad-feature-set

## Behavior

WHEN Merlin discovers the electronics plugin THE runtime SHALL load the first-party dynamic library metadata path and SHALL use the dynamic entrypoint as the plugin load gate before registering electronics capabilities.

WHEN electronics handlers receive incomplete or unauthoritative input THE handlers SHALL return blocked `KiCadToolResult` payloads with actionable diagnostics and SHALL NOT fabricate completion artifacts.

WHEN electronics handlers receive valid local executable paths and artifacts THE handlers SHALL execute the local toolchain, write artifacts from that execution, and return `COMPLETE` only after output evidence exists.

## Implementation

- Remove the electronics plugin-id shortcut from `RuntimePluginLoader`.
- Add first-party dynamic-library build wiring and C entrypoint source for `libMerlinElectronicsPlugin.dylib`.
- Resolve plugin dynamic-library paths relative to the plugin manifest and bundled app resources.
- Make electronics route completion evidence-driven:
  - compile requires an existing design intent artifact and writes KiCad project files;
  - ERC/DRC/fab require a KiCad CLI path and project evidence;
  - SPICE requires an executable simulator and scenario evidence;
  - vendor order preparation requires a normalized BOM;
  - vendor submission and release packaging require explicit approval/evidence.
- Keep all route responses in the common `KiCadToolResult` envelope.

## Verify

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests test
xcodebuild -scheme MerlinTests -destination 'platform=macOS' test
```

Expected green state: focused and full suites pass.

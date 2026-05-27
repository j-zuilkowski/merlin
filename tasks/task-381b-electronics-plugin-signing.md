# Task 381b — Electronics plugin signing

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#workspace-message-bus--runtime-plugin-architecture
- Test task: tasks/task-381a-electronics-plugin-signing-tests.md

## Behavior

WHEN the first-party electronics plugin target builds THE copied repo dylib SHALL
remain byte-for-byte usable as the manifest target and SHALL be signed before any
runtime test attempts to load it.

GIVEN Merlin discovers `plugins/electronics/plugin.json`,
WHEN the manifest resolves `dynamic_library_path`,
THEN the resolved library SHALL pass the platform loader checks and expose the
plugin entrypoint.

## Implementation

- Update `project.yml` for the `MerlinElectronicsPlugin` post-build script to
  copy the product dylib and ad-hoc sign the copied
  `plugins/electronics/libMerlinElectronicsPlugin.dylib`.
- Add the copied dylib path as a script output so Xcode no longer reports the
  copy phase as always dirty.
- Preserve the existing manifest path unless runtime resolution is intentionally
  changed and covered by tests.
- Do not route active electronics through the archived
  `archive/legacy-merlin-kicad-mcp` package.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/WorkspaceRuntimePluginLaunchTests test
xcodebuild -scheme MerlinTests -destination 'platform=macOS' test
```

Expected green state: the focused runtime plugin launch test passes and the full
Merlin unit suite no longer fails on the electronics dylib.

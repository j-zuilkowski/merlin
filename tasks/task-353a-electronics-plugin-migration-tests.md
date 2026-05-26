# Task 353a — Electronics Plugin Migration Tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-plugin-implications

## Behavior

WHEN this task is executed THE system SHALL add failing tests for moving the
electronics/KiCad surface into a Tier-1 bus-backed plugin.

## Context

Task 352b complete: the first-party runtime plugin loader exists.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence step 27:

27. Then Electronics Migration

## Write to: MerlinTests/Unit/ElectronicsPluginMigrationTests.swift

Prove:

- `plugins/electronics` is the canonical first-party plugin location.
- The legacy `plugins/merlin-kicad-mcp` scaffold is no longer the architecture
  source of truth.
- The electronics plugin registers `domain.electronics` metadata, settings
  schema, verification capability, and bus-backed KiCad tool/workflow routes.
- KiCad/FreeRouting capabilities route through the workspace bus.
- Progress, routing iteration, artifacts, approval requests, and diagnostics
  publish bus events visible to all sessions in the same workspace.
- Vendor-order and manufacturing-release routes require
  `userApprovedIrreversible`.

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: BUILD FAILED with missing electronics plugin migration behavior.

## Commit

```bash
git add MerlinTests/Unit/ElectronicsPluginMigrationTests.swift \
        tasks/task-353a-electronics-plugin-migration-tests.md
git commit -m "Task 353a — electronics plugin migration tests (failing)"
```

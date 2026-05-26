# Task 353b — Electronics Plugin Migration

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-plugin-implications

## Behavior

WHEN this task is executed THE system SHALL migrate electronics/KiCad into a
first-party Tier-1 bus-backed plugin and complete the message bus sequence.

## Context

Task 353a complete: electronics migration tests are failing.

Recommended execution model: GPT-5.3-Codex.

This task covers implementation-sequence steps 24, 25, and 27:

24. Full Verification
25. Commit And Push Bus Foundation
27. Then Electronics Migration

## Add: plugins/electronics

Create the canonical first-party electronics plugin structure. Re-home the
Merlin-owned electronics/KiCad code so the plugin registers:

- `tool.kicad_check_version`
- `tool.kicad_ingest_schematic`
- `tool.kicad_build_intent_model`
- `tool.kicad_route_pass`
- `tool.kicad_run_erc`
- `tool.kicad_run_drc`
- `tool.kicad_export_fab`
- `workflow.schematic_to_pcb`
- `workflow.requirements_to_pcb`
- `verify.electronics`
- `settings.validate`

`kicad_route_pass` must support local FreeRouting and the optional hosted API
behind one bus address. Vendor ordering and manufacturing release require
explicit irreversible user approval.

## Retire Legacy Scaffold Status

The old `plugins/merlin-kicad-mcp` scaffold may remain only if it is a clearly
documented legacy/out-of-process transport adapter. It must not be the canonical
architecture source of truth.

## Final Verification

Run:

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```

```bash
xcodebuild -scheme Merlin build \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | tail -20
```

```bash
rg -n "message bus future-status|WorkspaceMessageBus future-status|not-implemented status|ToolRouter closure bypass|canonical legacy KiCad MCP scaffold" \
    spec.md vision.md FEATURES.md Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md plugins tasks
```

Expected: all tests/builds pass and stale-current references are gone.

## Commit And Push

```bash
git add Merlin plugins spec.md vision.md FEATURES.md Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md MerlinTests tasks
git commit -m "Task 353b — migrate electronics plugin to workspace bus"
git push
```

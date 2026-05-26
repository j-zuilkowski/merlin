# Task 354b — Document current bus status and archive legacy MCP scaffold

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#v5-domain-plugin-system--workspace-message-bus

## Behavior

WHEN task 354b is executed THE system SHALL document current bus status and archive the legacy MCP scaffold.

GIVEN the bus/plugin foundation has shipped,
WHEN a reader opens `vision.md`, `spec.md`, `FEATURES.md`, or the in-app manuals,
THEN the current status is clear: the bus foundation, bus-backed tool routing, workspace runtime,
Tier-1 loader, and electronics bus migration are implemented.

GIVEN the old KiCad MCP scaffold is no longer the canonical architecture,
WHEN a developer inspects active plugins,
THEN only `plugins/electronics` is active and the old MCP scaffold is preserved under `archive/`.

## Implementation

- Update current-status language in `vision.md` and `spec.md`.
- Keep the implementation sequence as historical/completed status, not future instructions.
- Move `plugins/merlin-kicad-mcp` to `archive/legacy-merlin-kicad-mcp`.
- Update current docs and tests to reference the archive only where historical context is needed.
- Do not mark full electronics/KiCad/FreeRouting product completion as done.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/MessageBusStatusArchiveTests test

xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DocumentationSweepTests test
```

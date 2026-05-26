# Task 354a — Documentation status and legacy archive tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#v5-domain-plugin-system--workspace-message-bus

## Behavior

WHEN task 354a is executed THE system SHALL add documentation status and legacy archive tests.

GIVEN the workspace message bus, Tier-1 loader, and electronics migration are implemented,
WHEN the documentation sweep runs,
THEN current architecture docs describe that work as implemented instead of future work.

GIVEN `plugins/electronics` is the canonical first-party electronics plugin,
WHEN the repository is scanned for active plugins,
THEN the legacy `plugins/merlin-kicad-mcp` MCP scaffold is no longer active under `plugins/`
and is preserved only as archived historical material.

## Red Test

Add focused tests that fail until:

- `vision.md` no longer says the message-bus/plugin implementation must start.
- `spec.md` no longer describes the message-bus implementation sequence as future work.
- `plugins/merlin-kicad-mcp` is absent from the active plugin tree.
- `archive/legacy-merlin-kicad-mcp` exists and preserves the legacy scaffold.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/MessageBusStatusArchiveTests test
```

# Task 354a — Documentation status and legacy archive tests

## Traceability

- vision.md — Runtime plugin architecture + electronics plugin
- spec.md — V5 domain plugin system / workspace message bus

## Behavior

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

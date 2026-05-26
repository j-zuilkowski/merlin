# Task 359b — Electronics completion documentation sweep

## Traceability

- spec.md — Electronics Product Completion Pass
- FEATURES.md — V2.0 Electronics Domain
- Merlin/Docs/UserGuide.md — Electronics / KiCad Domain
- Merlin/Docs/DeveloperManual.md — Electronics / KiCad Domain

## Behavior

GIVEN the electronics completion pass is implemented,
WHEN a user or developer reads current docs,
THEN the docs SHALL match the actual active architecture and behavior.

## Implementation

- Update `FEATURES.md`, `Merlin/Docs/UserGuide.md`, and `Merlin/Docs/DeveloperManual.md`.
- Replace stale current-status descriptions of `merlin-kicad-mcp` with the active bus-backed `plugins/electronics` architecture.
- Document local FreeRouting, optional hosted routing, explicit blocked/failure behavior, required artifacts, gatekeeping verification, approvals, and the electronics job/status panel.
- Keep archived MCP references historical only.
- Review code comments touched during the completion pass against the spec comment rules and add Developer Manual cross-references only where warranted.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DocumentationSweepTests test
```

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' build-for-testing
```

```bash
rg -n "powered by an external MCP server|delegated to `merlin-kicad-mcp`|plugins/merlin-kicad-mcp" \
  FEATURES.md Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md spec.md vision.md
```

Expected: tests and build pass; stale-current wording is gone or explicitly historical.

## Commit

```bash
git add FEATURES.md Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md \
        MerlinTests tasks
git commit -m "Task 359b — electronics completion docs"
```

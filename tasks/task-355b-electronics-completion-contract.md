# Task 355b — Electronics completion contract

## Traceability

- vision.md — Runtime plugin architecture + electronics plugin
- spec.md — Electronics Product Completion Pass

## Behavior

GIVEN the electronics plugin is the canonical active implementation,
WHEN Merlin loads the electronics domain,
THEN the plugin SHALL expose typed workflow, tool, artifact, status, and gate contracts for the completion pass.

## Implementation

- Add typed contracts for electronics job status, route status, blocked reasons, verification gates, artifact kinds, approval requests, and final reports.
- Register workflow routes for `workflow.requirements_to_pcb` and `workflow.schematic_to_pcb`.
- Register supporting KiCad/FreeRouting tool routes only through `WorkspaceMessageBus`.
- Convert missing-tooling and unsupported-version paths to explicit blocked/failed bus events.
- Add a production guard that prevents active routing through `archive/legacy-merlin-kicad-mcp`.
- Preserve the archive only as historical/reference material.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsCompletionContractTests test
```

```bash
rg -n "archive/legacy-merlin-kicad-mcp|plugins/merlin-kicad-mcp" \
  Merlin plugins/electronics | cat
```

Expected: tests pass; production references to the archive are absent except explicit test fixtures or documentation.

## Commit

```bash
git add Merlin MerlinTests plugins/electronics tasks
git commit -m "Task 355b — electronics completion contract"
```

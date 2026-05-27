# Task 385b — Electronics current-doc drift

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass
- Test task: tasks/task-385a-electronics-current-doc-drift-tests.md

## Behavior

WHEN users or maintainers read current Merlin docs THE docs SHALL consistently
describe the active electronics architecture as the bus-backed
`plugins/electronics` runtime plugin.

GIVEN the archived `merlin-kicad-mcp` scaffold still exists,
WHEN it is mentioned,
THEN the docs SHALL state it is historical reference and not the active runtime
route.

## Implementation

- Update `README.md`, `Requirements.md`, Merlin docs, and eval docs that still
  call `merlin-kicad-mcp` active/current.
- Preserve accurate references to KiCad CLI, FreeRouting, ngspice, and the
  KiCad MCP tooling concept where those are still part of the active
  bus-backed architecture.
- Replace stale install/setup instructions that point at
  `plugins/merlin-kicad-mcp` with instructions for the active electronics
  plugin and required external tools.
- Keep archived scaffold documentation under `archive/legacy-merlin-kicad-mcp`
  intact unless a link or label is actively misleading.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests \
  -only-testing:MerlinTests/ElectronicsGreenBoardTests test
rg -n 'built on `merlin-kicad-mcp`|merlin-kicad-mcp server registered|requires.*merlin-kicad-mcp|Register the merlin-kicad-mcp server|merlin-kicad-mcp \+ FreeRouting' \
  README.md Requirements.md Merlin/Docs merlin-eval spec.md vision.md
```

Expected green state: active docs consistently name `plugins/electronics`; any
remaining `merlin-kicad-mcp` references are explicitly historical, archived, or
fixture metadata.

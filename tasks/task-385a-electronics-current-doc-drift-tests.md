# Task 385a — Electronics current-doc drift tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass
- Prior finding: top-level docs still describe `merlin-kicad-mcp` as current

## Behavior

WHEN documentation describes the current electronics architecture THE docs SHALL
name `plugins/electronics` as the active runtime plugin surface and SHALL NOT
describe `merlin-kicad-mcp` as the current production route.

GIVEN archived MCP scaffold material remains in the repo,
WHEN docs mention `archive/legacy-merlin-kicad-mcp`,
THEN the mention SHALL clearly identify it as historical reference only.

## Red Tests

- Extend documentation sweep tests to cover active user-facing and eval docs:
  `README.md`, `Requirements.md`, `merlin-eval/README.md`,
  `merlin-eval/scenarios/S6-electronics.md`,
  `merlin-eval/BLOCKED.md`, and proving-run status docs.
- Fail on phrases that imply the current implementation is built on or requires
  active routing through `merlin-kicad-mcp`.
- Allow references to `archive/legacy-merlin-kicad-mcp` only when the same
  context says the scaffold is archived/historical/reference-only.
- Assert active docs name the current `plugins/electronics` runtime plugin and
  evidence-gated completion model.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests \
  -only-testing:MerlinTests/ElectronicsGreenBoardTests test
```

Expected red state: docs fail while top-level and eval docs still present
`merlin-kicad-mcp` as active/current.

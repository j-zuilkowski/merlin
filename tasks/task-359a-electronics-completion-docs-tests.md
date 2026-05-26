# Task 359a — Electronics completion docs tests

## Traceability

- spec.md — Electronics Product Completion Pass
- FEATURES.md — V2.0 Electronics Domain
- Merlin/Docs/UserGuide.md — Electronics / KiCad Domain
- Merlin/Docs/DeveloperManual.md — Electronics / KiCad Domain

## Behavior

GIVEN the electronics completion pass is implemented,
WHEN documentation sweep tests run,
THEN user and developer docs SHALL describe the active bus-backed plugin, local FreeRouting completion backend, gates, artifacts, and job panel without stale external-MCP-current wording.

## Red Test

Add failing documentation sweep tests that prove:

- user-facing docs do not say active electronics behavior is powered by `plugins/merlin-kicad-mcp`;
- docs identify `plugins/electronics` and the workspace bus as the active architecture;
- docs describe local FreeRouting as the required completion backend and hosted routing as optional/configured;
- docs list the required artifacts and gatekeeping behavior;
- docs mention the electronics job/status panel.

Suggested file:

- extend `MerlinTests/Unit/DocumentationSweepTests.swift`

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DocumentationSweepTests test
```

Expected: tests fail until documentation is reconciled.

## Commit

```bash
git add MerlinTests/Unit/DocumentationSweepTests.swift \
        tasks/task-359a-electronics-completion-docs-tests.md
git commit -m "Task 359a — electronics completion docs tests"
```

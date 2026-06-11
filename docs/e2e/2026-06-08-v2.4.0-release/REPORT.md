# Merlin v2.4.0 Release Evidence Report

## Summary

Overall status: **passed through gate #12**.

Gates #1-#12 are passed. This report summarizes the fixed v2.4.0 release
ledger evidence through the post-green screenshot and release-report stages.
Gate #13, the final safety check, was completed after this report was first
written. Tagging, pushing, and publishing remain pending.

## Environment

- Date: 2026-06-11
- Workspace: `/Users/jonzuilkowski/Documents/localProject/merlin`
- Release evidence root:
  `docs/e2e/2026-06-08-v2.4.0-release/`
- Branch: `codex/stabilize-merlin-e2e`
- Version under release validation: `2.4.0`

## Automated Gate Results

| Gate | Result | Evidence |
|---|---|---|
| 1. Core test target | PASS | `docs/e2e/2026-06-08-v2.4.0-release/logs/01-MerlinTests.log`; full suite passed 2,571 tests, 55 skipped, 0 failures |
| 2. GUI test target | PASS | `docs/e2e/2026-06-08-v2.4.0-release/logs/02-MerlinUITests.log`; full UI suite passed 12 tests, 0 failures |
| 3. Focused visual tests | PASS | `docs/e2e/2026-06-08-v2.4.0-release/logs/03-VisualLayoutTests.log`; focused visual suite passed 6 tests, 0 failures |
| 4. DeepSeek live agent/provider slice | PASS | `docs/e2e/2026-06-08-v2.4.0-release/logs/04-MerlinTests-Live.log`; DeepSeek provider and agent-loop slices passed |
| 5. Local-provider pairs | PASS | `docs/e2e/2026-06-08-v2.4.0-release/logs/05-local-providers.log`; LM Studio and Jan.ai smokes passed with cleanup |
| 6. llama.cpp router | PASS | `docs/e2e/2026-06-08-v2.4.0-release/logs/06-llamacpp-router.log`; explicit text, streaming, tool-call, and vision model checks passed |
| 7. xcalibre RAG | PASS | `docs/e2e/2026-06-08-v2.4.0-release/logs/07-xcalibre-rag.log`; health, OpenAPI, authenticated sentinel insert/search/delete, and cleanup passed |
| 8. Capability scenarios S1/S2 | PASS | `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner.log`; S1 passed in 676.582s, S2 passed in 244.910s; cleanup in `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner-cleanup.log` |
| 9. Electronics/KiCad deterministic checks | PASS | `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.log`; 343 focused electronics/KiCad tests passed, 5 skipped, 0 failures; AmpDemo PCB slice generated a populated board and clean DRC report |
| 10. KiCad release screenshots | PASS | `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/README.md`; generated schematic and PCB opened in KiCad GUI editors; routed/layer and 3D evidence captured |
| 11. README/GitHub screenshots | PASS | `docs/assets/screenshots/v2.4.0/`; full-size evidence captures in `docs/e2e/2026-06-08-v2.4.0-release/screenshots/readme/`; capture log `docs/e2e/2026-06-08-v2.4.0-release/logs/11-readme-screenshots.log` |
| 12. Release evidence report | PASS | This `REPORT.md`; fail-first guard `docs/e2e/2026-06-08-v2.4.0-release/logs/12-release-report.fail-first.log`; focused green guard `docs/e2e/2026-06-08-v2.4.0-release/logs/12-release-report.focused-green.log` |

## Screenshot Assets

README/GitHub release assets are committed under
`docs/assets/screenshots/v2.4.0/`:

- `merlin-workspace.png`
- `merlin-settings-providers.png`
- `merlin-settings-provider-slots.png`
- `kicad-schematic-editor.png`
- `kicad-pcb-editor.png`
- `kicad-3d-viewer.png`
- `kicad-routed-composite.png`

Evidence-only full-size Merlin GUI captures are retained under
`docs/e2e/2026-06-08-v2.4.0-release/screenshots/readme/`.

KiCad screenshot evidence is retained under
`docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/`.

## Electronics Boundary

The electronics domain is finished as evidence-gated workflow infrastructure,
not as a fabrication-ready board release. The current full GUI workflow proof
honestly stops at `COMPONENT_SELECTION_REVISION_BLOCKED` when concrete component
evidence is missing. The gate #10 generated `amp_low_voltage_audio` KiCad board
opens and renders in KiCad, but its copied `source/drc.json` reports 26 DRC violations.
That evidence is not a fabrication-ready claim.

## Cleanup State

Gate-owned cleanup logs record service and app cleanup at the relevant stages.
The gate #11 screenshot log records: No Merlin app processes remain. Earlier
release gate cleanup logs record local-provider and RAG shutdown. No 8081 or 8083 listeners remained after their gate-owned services stopped. Gate #13 must
perform the final repository-wide safety check again before tagging.

## Remaining Release Gates

- Gate #14: create tag `v2.4.0`.
- Gate #15: push branch and tag.
- Gate #16: publish GitHub Release `v2.4.0` with required screenshots and
  evidence assets.

## Post-Report Safety Update

Gate #13 passed after this report was written. Evidence:
`docs/e2e/2026-06-08-v2.4.0-release/logs/13-final-safety.log`.

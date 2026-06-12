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
| 10. KiCad release screenshots | PASS | Task 512 supersedes Task 511; `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/README.md`; stale screenshots were removed; refreshed `isolated_secondary` schematic and PCB opened in KiCad GUI editors; PCB evidence shows 72 track segments, 36 vias, and 0 unrouted items; routed/layer and 3D evidence captured |
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

The KiCad assets were refreshed again by Task 512 from the gate #10
`isolated_secondary` screenshot bundle after user review found the prior
evidence unusable. The public KiCad PCB asset now comes from a real PCB Editor
window that shows routed traces and vias, and the public schematic asset shows
visible connector symbols.

Evidence-only full-size Merlin GUI captures are retained under
`docs/e2e/2026-06-08-v2.4.0-release/screenshots/readme/`.

KiCad screenshot evidence is retained under
`docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/`.

## Electronics Boundary

The electronics domain is finished as evidence-gated workflow infrastructure,
not as a fabrication-ready board release. The current full GUI workflow proof
honestly stops at `COMPONENT_SELECTION_REVISION_BLOCKED` when concrete component
evidence is missing. The refreshed gate #10 generated `isolated_secondary`
KiCad board opens and renders in KiCad. Its copied gate #9 `source/drc.json`
reports 0 DRC violations, 0 unconnected items, and 0 schematic parity issues;
the copied-project KiCad CLI rerun in `source/drc-rerun.json` also reports 0
DRC violations and 0 unconnected items, with 59 schematic parity warnings. The
copied PCB contains 21 footprints, 62 pads, 72 track segments, and 36 vias.
That evidence is visual release proof, not a fabrication-ready claim.

## Cleanup State

Gate-owned cleanup logs record service and app cleanup at the relevant stages.
The gate #11 screenshot log records: No Merlin app processes remain. Earlier
release gate cleanup logs record local-provider and RAG shutdown. No 8081 or 8083 listeners remained after their gate-owned services stopped. Gate #13 must
perform the final repository-wide safety check again before tagging.

## Remaining Release Gates

- Gate #15: push branch and tag.
- Gate #16: publish GitHub Release `v2.4.0` with required screenshots and
  evidence assets.

## Post-Report Safety Update

Gate #13 passed after this report was written, then Task 513 reran it after
Task 512 repaired the KiCad release evidence. The refreshed safety log records
clean starting status at commit `f959ddfb6b7372189c078cd4206b921bcb45ce69`,
version `2.4.0` build `26`, release evidence present, 7 README screenshot
assets, no Merlin/KiCad app processes, no 8081/8083 listeners, and absent
local/remote `v2.4.0` tags. Evidence:
`docs/e2e/2026-06-08-v2.4.0-release/logs/13-final-safety.log`.

## Post-Safety Tag Update

Gate #14 passed after Task 513. Task 514 created the local `v2.4.0` tag. Pushing
the branch/tag and publishing the GitHub release remain pending.

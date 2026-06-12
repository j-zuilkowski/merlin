# v2.4.0 Release Run

This file is the resumable source of truth for the v2.4.0 release push. Do not
replace it with a new rolling checklist. Update one row at a time as each gate
runs, fails, is repaired, or passes.

## State Values

- `pending`: not run for this release attempt.
- `running`: currently executing.
- `passed`: command/action completed and evidence exists.
- `failed`: command/action failed; `Next repair` names the blocker to fix.
- `blocked`: cannot run until an earlier required state changes.
- `skipped-with-evidence`: allowed only for documented key-gated provider
  surfaces, with the missing key or environment evidence named.

## Full Green E2E Battery

| # | Gate | State | Evidence | Next repair |
|---|---|---|---|---|
| 1 | Core test target: `xcodegen generate` then full `MerlinTests` | passed | `docs/e2e/2026-06-08-v2.4.0-release/logs/01-MerlinTests.log`; `/tmp/merlin-derived-v240-full-core/Logs/Test/Test-MerlinTests-2026.06.08_15-03-02--0400.xcresult`; full suite passed 2,571 tests, 55 skipped, 0 failures. Focused window proof `/tmp/merlin-derived-task493-window-green/Logs/Test/Test-MerlinTests-2026.06.08_15-02-01--0400.xcresult` passed 30 tests. | none |
| 2 | GUI test target: full `MerlinUITests` | passed | `docs/e2e/2026-06-08-v2.4.0-release/logs/02-MerlinUITests.log`; `/tmp/merlin-derived-v240-ui/Logs/Test/Test-MerlinUITests-2026.06.08_15-06-46--0400.xcresult`; full UI suite passed 12 tests, 0 failures. | none |
| 3 | Focused visual target: `MerlinUITests/VisualLayoutTests` | passed | `docs/e2e/2026-06-08-v2.4.0-release/logs/03-VisualLayoutTests.log`; `/tmp/merlin-derived-v240-visual/Logs/Test/Test-MerlinUITests-2026.06.08_15-09-16--0400.xcresult`; focused visual suite passed 6 tests, 0 failures. | none |
| 4 | Live agent loop: DeepSeek-backed live tests when key is present | passed | `docs/e2e/2026-06-08-v2.4.0-release/logs/04-MerlinTests-Live.log`; fail-first compile evidence `docs/e2e/2026-06-08-v2.4.0-release/logs/04-MerlinTests-Live.fail-first.log`; `/tmp/merlin-derived-v240-live-deepseek/Logs/Test/Test-MerlinTests-Live-2026.06.08_15-13-52--0400.xcresult`; DeepSeek provider slice passed 3 tests, agent-loop slice passed 1 test, 0 failures. | none |
| 5 | Local-provider pairs smoke/load/shutdown | passed | `docs/e2e/2026-06-08-v2.4.0-release/logs/05-local-providers.log`; fail-first wrapper evidence `docs/e2e/2026-06-08-v2.4.0-release/logs/05-local-providers.fail-first.log`; LM Studio text/streaming/tool and explicit vision smokes passed; Jan text/streaming/tool smoke passed; Jan separate vision lifecycle smoke passed; ports 1234 and 1337 closed after cleanup. | none |
| 6 | llama.cpp router explicit model ID smoke | passed | `docs/e2e/2026-06-08-v2.4.0-release/logs/06-llamacpp-router.log`; `docs/e2e/2026-06-08-v2.4.0-release/logs/06-llamacpp-router-server.log`; router catalog exposed `default` first but smoke selected explicit `qwen3-coder-local` and `qwen3-vl-local`; completion, streaming, tool-call, and vision checks passed; port 8081 closed after cleanup. | none |
| 7 | xcalibre RAG health/search/cleanup | passed | `docs/e2e/2026-06-08-v2.4.0-release/logs/07-xcalibre-rag.log`; fail-first config evidence `docs/e2e/2026-06-08-v2.4.0-release/logs/07-xcalibre-rag.fail-first.log`; server log `docs/e2e/2026-06-08-v2.4.0-release/logs/07-xcalibre-server.log`; real sibling backend built and started on 8083; health/openapi passed; authenticated memory sentinel insert/search/delete passed; port 8083 closed after cleanup. | none |
| 8 | Capability scenarios S1/S2 convergence | passed | Deterministic runner: `scripts/release/run-capability-gate.sh`; live runner log `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner.log` records `testS1SwiftGUIDebugCycle` passing in 676.582s, `testS2RustDebugCycle` passing in 244.910s, and `** TEST SUCCEEDED **`; scenario artifacts `merlin-eval/results/S1-harness-2026-06-11T17-12-35Z.md` and `merlin-eval/results/S2-harness-2026-06-11T17-16-40Z.md`; cleanup evidence `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner-cleanup.log` records restored config/provider files, no release runner/services, and no 8081/8083 listeners; runner watchdog repair evidence `docs/e2e/2026-06-08-v2.4.0-release/logs/08-runner-watchdog.fail-first.log`, `08-runner-watchdog.focused-green.log`, `08-runner-watchdog.bash-n.log`; Task 503 focused green `docs/e2e/2026-06-08-v2.4.0-release/logs/08-task503.focused-green.log`; prior Task 500-502 fail-first and repair artifacts remain preserved. | none |
| 9 | Electronics/KiCad deterministic checks | passed | `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.fail-first-summary.log` records the initial stale handoff assertion failure in `FinalElectronicsDocumentationSweepTests.testElectronicsFinishChecklistMatchesFinalEvidenceContract`; focused repair evidence `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-doc-sweep.focused-green.log` passes the corrected doc sweep; refreshed gate evidence `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.log` passes 343 focused electronics/KiCad tests with 5 skips and 0 failures. It includes `EvidenceGatedComponentSelectionTests.testAmpDemoEvidenceBackedPCBCompilePlacesAllFootprintsAndRunsDRC`, which generated `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/pcb-slice/54F5F058-4CE3-4A2E-853E-74980AA944E8/isolated_secondary.kicad_pcb` and clean DRC report `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/7FB63521-6C6F-44D4-8EE3-83E02F54C269-drc-report.json`. | none |

## Post-Green Release Screenshots

These actions are blocked until every non-key-gated row in the Full Green E2E
Battery is `passed` and every allowed key-gated row is `skipped-with-evidence`.
Release screenshots are created only after the full battery is green.

| # | Gate | State | Evidence | Next repair |
|---|---|---|---|---|
| 10 | KiCad release screenshots: open generated schematic and generated PCB in KiCad; capture schematic editor, PCB editor, routed/layer, and 3D board screenshots when available | passed | Task 512 supersedes the Task 511 screenshots after user review found the prior bundle unusable. `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/README.md`; stale screenshots and sidecar files were removed; refreshed generated KiCad source copied under `screenshots/kicad/source/` from the final green `isolated_secondary` board; GUI screenshots `schematic-editor-screenshot.png`, `pcb-editor-screenshot.png`, and `board-3d-viewer-screenshot.png`; deterministic exports `schematic.pdf`, `schematic-svg/isolated_secondary.svg`, `schematic-svg/isolated_secondary.png`, `layers/routed-composite.svg`, `layers/front-copper.svg`, `layers/back-copper.svg`, PNG layer previews, and `board-3d-render.png`; command log `docs/e2e/2026-06-08-v2.4.0-release/logs/10-kicad-screenshots.log`. The copied board has 21 footprints, 62 pads, 72 track segments, and 36 vias. `source/drc.json` reports 0 DRC violations, 0 unconnected items, and 0 schematic parity issues. The copied-project rerun `source/drc-rerun.json` also reports 0 DRC violations and 0 unconnected items, with 59 schematic parity warnings. This is visual/generated-file evidence only, not a FAB_READY claim. | none |
| 11 | GitHub and README feature screenshots | passed | Public README/GitHub assets under `docs/assets/screenshots/v2.4.0/`: `merlin-workspace.png`, `merlin-settings-providers.png`, `merlin-settings-provider-slots.png`, Task 512-refreshed gate #10 `kicad-schematic-editor.png`, `kicad-pcb-editor.png`, `kicad-3d-viewer.png`, and `kicad-routed-composite.png`; evidence-only full-size Merlin captures under `docs/e2e/2026-06-08-v2.4.0-release/screenshots/readme/`; command/process cleanup log `docs/e2e/2026-06-08-v2.4.0-release/logs/11-readme-screenshots.log`; fail-first guard `docs/e2e/2026-06-08-v2.4.0-release/logs/11-readme-screenshots.fail-first.log`; focused green guard `docs/e2e/2026-06-08-v2.4.0-release/logs/11-readme-screenshots.focused-green.log`. | none |
| 12 | Release evidence report | passed | `docs/e2e/2026-06-08-v2.4.0-release/REPORT.md`; fail-first guard `docs/e2e/2026-06-08-v2.4.0-release/logs/12-release-report.fail-first.log`; focused green guard `docs/e2e/2026-06-08-v2.4.0-release/logs/12-release-report.focused-green.log`. | none |
| 13 | Final safety check: clean status, version 2.4.0, evidence present, no orphan services/helpers | passed | Task 513 reran this gate after Task 512 changed KiCad release evidence. `docs/e2e/2026-06-08-v2.4.0-release/logs/13-final-safety.log` records clean starting status at commit `f959ddfb6b7372189c078cd4206b921bcb45ce69`, version `2.4.0` build `26`, release evidence present, 7 README screenshot assets, no Merlin/KiCad app processes, no 8081/8083 listeners, and local/remote `v2.4.0` tags absent. Earlier fail-first guard `docs/e2e/2026-06-08-v2.4.0-release/logs/13-final-safety.fail-first.log`; focused green guard `docs/e2e/2026-06-08-v2.4.0-release/logs/13-final-safety.focused-green.log`. | none |
| 14 | Tag `v2.4.0` | pending | `git tag v2.4.0` | none yet |
| 15 | Push branch and tag | blocked | remote branch and tag | wait for #14 green |
| 16 | Publish GitHub Release `v2.4.0` with required release assets/screenshots | blocked | GitHub Release `v2.4.0` | wait for #15 green |

## Current Blocker

Gates #1-#13 are passed. Gate #13 was refreshed by Task 513 after the Task 512
KiCad evidence repair and records version `2.4.0`, release evidence presence,
screenshot asset count, clean starting status, no orphan Merlin/KiCad/helper
processes, and absent local/remote `v2.4.0` tags. The immediate blocker is gate
#14: create tag `v2.4.0`.

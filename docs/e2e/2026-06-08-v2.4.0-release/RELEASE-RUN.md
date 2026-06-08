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
| 8 | Capability scenarios S1/S2 convergence | pending | `docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-scenarios.log` | none yet |
| 9 | Electronics/KiCad deterministic checks | pending | `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.log` | none yet |

## Post-Green Release Screenshots

These actions are blocked until every non-key-gated row in the Full Green E2E
Battery is `passed` and every allowed key-gated row is `skipped-with-evidence`.
Release screenshots are created only after the full battery is green.

| # | Gate | State | Evidence | Next repair |
|---|---|---|---|---|
| 10 | KiCad release screenshots: open generated schematic and generated PCB in KiCad; capture schematic editor, PCB editor, routed/layer, and 3D board screenshots when available | blocked | `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/` | wait for #1-#9 green |
| 11 | GitHub and README feature screenshots | blocked | `docs/assets/screenshots/v2.4.0/` and `docs/e2e/2026-06-08-v2.4.0-release/screenshots/` | wait for #1-#10 green |
| 12 | Release evidence report | blocked | `docs/e2e/2026-06-08-v2.4.0-release/REPORT.md` | wait for #1-#11 green |
| 13 | Final safety check: clean status, version 2.4.0, evidence present, no orphan services/helpers | blocked | `docs/e2e/2026-06-08-v2.4.0-release/logs/13-final-safety.log` | wait for #1-#12 green |
| 14 | Tag `v2.4.0` | blocked | `git tag v2.4.0` | wait for #13 green |
| 15 | Push branch and tag | blocked | remote branch and tag | wait for #14 green |
| 16 | Publish GitHub Release `v2.4.0` with required release assets/screenshots | blocked | GitHub Release `v2.4.0` | wait for #15 green |

## Current Blocker

The immediate blocker is gate #8, the capability scenarios S1/S2 convergence
proof. Gate #10, the KiCad release screenshot step, is not valid until gates
#1-#9 are green.

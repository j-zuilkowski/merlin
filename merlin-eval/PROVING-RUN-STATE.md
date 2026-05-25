# Proving-Suite Run — Session Handoff

> Resume point for the autonomous proving-suite run. Read this top-to-bottom before
> doing anything. Nothing here is committed except the five fixes listed below.

## Mission

Run the Merlin proving suite (eval scenarios S1–S18) end-to-end, **all mechanisms except
M5** (M5 = manual runsheet — voice/visual/KiCad GUI — explicitly deferred). Loop:
**run → triage → fix → re-run**, autonomously, without stopping to ask.

The user **authorized direct Merlin source fixes** for this exercise: `edit → build →
test → commit`. This *overrides*, for this run only, the normal project rule that Claude
only authors task docs for Codex. **Never `git push`** — local commits only.

When a failure is hit, classify it: **harness/instrumentation defect** (fix the test
infra), **Merlin product bug** (fix the app), or **environment/capability** (flag, don't
force a code change). Never weaken an assertion to go green.

## Environment / facts

- Working dir: `~/Documents/localProject/merlin` (git repo). `merlin-eval/` is now
  *inside* it at `merlin/merlin-eval/` (relocated in task 332).
- macOS, Swift 5.10, xcodegen (`project.yml` is source of truth; run `xcodegen generate`
  after editing it or adding a source file).
- LM Studio running on `localhost:1234` — models: `qwen3-coder-next` (text),
  `qwen/qwen3-vl-8b` (vision), `qwopus3.5-27b…`. Merlin slots (config.toml):
  execute/orchestrate → `lmstudio:qwen3-coder-next`, vision → `lmstudio:qwen/qwen3-vl-8b`,
  reason → `deepseek:deepseek-v4-pro`.
- xcalibre-server repo at `~/Documents/localProject/xcalibre-server`; its `backend`
  binary is built at `target/debug/backend` (123 MB).
- DeepSeek API key is in `~/.merlin/api-keys.json` (`deepseek`, `deepseek-flash`) and the
  Keychain. `mlx_lm` is installed for `python3`.
- HEAD: `3f827e2`. Do not push.

## Build / run commands

```bash
cd ~/Documents/localProject/merlin
# Deterministic unit suite (M3/M4/S18 + 1807 tests)
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
# Compile gates
xcodebuild -scheme MerlinTests build-for-testing …          (same flags)
xcodebuild -scheme MerlinTests-Live build-for-testing …     (same flags)
# M1 capability scenarios (live)
RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live test … \
  -only-testing:MerlinE2ETests/CapabilityScenarioTests \
  -only-testing:MerlinE2ETests/AgenticLoopE2ETests
```
Long runs: launch with `run_in_background: true`. An M1 pass is ~45–90 min.
Logs from this session: `/tmp/merlin-pass1-unit.log`, `…-pass1-surface.log`,
`…-pass1-m1-real.log`, `…-pass2-m1.log`.

## Done

Deterministic suite: **green** — 1807 tests, 0 failures, 0 warnings.

Five fixes committed (HEAD = `f083394`):

| Commit | Fix |
|---|---|
| `73ef978` | HARNESS-2 — `MerlinTests-Live` scheme's `RUN_LIVE_TESTS` was a malformed nested mapping in `project.yml`; the live suite had silently never run. |
| `3dfd86c` | **M-1 (Merlin bug)** — `ShellTool.execute` called `Process.terminate()` on an unlaunched process when a shell tool was cancelled early → `NSInvalidArgumentException`, app crash. Guarded both `terminate()` calls with `process.isRunning`. |
| `068618c` | HARNESS-3 — `EvalLMStudio` (in `MerlinE2ETests/EvalSupport.swift`) filtered out the `lmstudio` provider because its `model` field is empty; now resolves the model from `slotAssignments`. |
| `3f827e2` | **M-2 (Merlin bug)** — `LoRATrainer` invoked bare `python` (absent on macOS) → `python3`. |
| `f083394` | HARNESS-4 — the harness ran `cargo`/`python3` via `/usr/bin/env`, which execs with the xctest process's minimal PATH (no `~/.cargo/bin`) → `env: cargo: No such file or directory`. Now routes through `zsh -c`. This masked S2 entirely. |

## M1 pass-2 results (all ran; no crash — M-1 confirmed fixed)

| Scenario | Outcome | Class | Next step |
|---|---|---|---|
| S1 | `NSError 260` reading `.merlin/project.toml` (ran 1823s) | **M-3** Merlin bug | see below |
| S2 | "failed" was HARNESS-4 only (`cargo` not found); Merlin made 93 tool calls | HARNESS-4 — fixed | re-run for first real verdict |
| S4 | `xcalibre-server did not become ready` (120s) | harness/server | investigate |
| S5 | `command not found: python` | M-2 — **fixed**, re-run | |
| S6 | Merlin never called KiCad MCP tools (ran 927s) | investigate | MCP launch / agent |
| S6-OCR | `NSError 260` reading `.merlin/override-log.jsonl` (905s) | **M-3** Merlin bug | see below |
| AgenticLoop | skipped — "No API key" | harness gate | see below |

## Open work — precise next steps

**M-3 (Merlin bug, highest priority — breaks S1 + S6-OCR and any project without a
`.merlin/` dir).** S1 and S6-OCR throw `NSError 260` (`NSFileReadNoSuchFileError`) for
`.merlin/project.toml` / `.merlin/override-log.jsonl`. The error propagates as a "caught
error" out of `EvalHarness.runScenario` (`MerlinE2ETests/EvalHarness.swift`), which only
explicitly throws `HarnessError`. `ProjectConfigLoader.load` and
`DisciplineEngine.gatingSchemes` are correctly guarded — the culprit is a *different*
unguarded read. Trace: `Merlin/Sessions/LiveSession.swift` (`final class LiveSession`
line 21; `func close() async` line 174 — note it is NOT `throws`, so work out the real
propagation path) and `OverrideAuditLog` / discipline teardown. Fix: guard the read(s)
(`fileExists` / `try?`) so a missing `.merlin/` file is treated as "discipline not
configured", not an error.

**S4.** `CapabilityScenarioTests.testS4RAGGrounding` builds `backend`, writes a temp
`config.toml`, launches it via `EvalService` with `CONFIG_PATH` + `APP_BIND_ADDR=
127.0.0.1:8094`, and polls `http://127.0.0.1:8094/api/docs/openapi.json` for 120s. It
timed out. Investigate: does `backend` actually start with that config (run it by hand
with the same env), and is `/api/docs/openapi.json` the correct readiness URL? Also:
the S4 evidence file (`merlin-eval/results/S4-harness-*.md`) shows Merlin reported the
RAG service unavailable at `localhost:8083` — the **default** port, not the test's
`8094`. So the `XCALIBRE_BASE_URL` env var the test sets is not reaching Merlin's
xcalibre client (read too early, or not read at all). Two distinct S4 problems.

**S6.** Merlin didn't call any `kicad_*` / `mcp:` tool. The test writes `.mcp.json`
pointing at `merlin/plugins/merlin-kicad-mcp/run`. Investigate whether the MCP server
launches/registers and why the agent never invokes it.

**AgenticLoop.** `AgenticLoopE2ETests.swift:12` skips with "No API key" though the
DeepSeek key is in `~/.merlin/api-keys.json` + Keychain. Its key check looks somewhere
the key is not — fix the gate to read Merlin's actual key store.

**HARNESS-1.** `SurfaceUITests.swift` + `VisualLayoutTests.swift` (in `MerlinE2ETests/`)
are XCUITests (`XCUIApplication()`) but `MerlinE2ETests` is `bundle.unit-test` → all 12
fail with "No target application path specified." Fix: add a `bundle.ui-testing` target
(`TEST_TARGET_NAME: Merlin`) and move those two files there. `AccessibilityID.swift`
(`Merlin/Support/`, Foundation-only) can be shared into it; `SettingsSection` lives in
`SettingsWindowView.swift` (not self-contained — extract it to its own file or hardcode
the pane labels). `GUIAutomationE2ETests` uses `XCUIApplication(bundleIdentifier:)` only
as a launcher + `@testable import Merlin` — keep it in `MerlinE2ETests` and replace the
launcher with `NSWorkspace`.

## S2 — corrected (no user decision involved)

An earlier draft of this doc wrongly called S2 a "model capability" outcome needing a
user decision. That was an unfounded guess — see HARNESS-4. S2 has **never produced a
real verdict**: pass-1 it died to the M-1 crash; pass-2 the harness `cargo test` check
could not find `cargo`. After HARNESS-4 (`f083394`) + a re-run, S2 yields its first
genuine result. The evidence file shows Merlin made 93 tool calls on the fixture.

## Constraints / deferred

- **No `git push`.** Local commits only.
- **M5** (manual runsheet) deferred by the user.
- **Task-doc sync deferred:** per `constitution.md`, the Merlin fixes need a `## Fixes` note
  in the relevant task docs (`ShellTool`, `LoRATrainer`, `EvalSupport`, the
  `MerlinTests-Live` scheme). Batch this at the end of the run.
- `Merlin.xcodeproj/project.pbxproj` shows as perpetually dirty (regenerated by
  `xcodegen`, gitignored-but-tracked) — do not commit it.

## Resume order

1. Fix **M-3** (trace `LiveSession.swift`), build, test, commit.
2. Investigate **S4** (server readiness + the `8083` vs `8094` port wiring) then **S6**;
   fix or mark BLOCKED.
3. Fix the **AgenticLoop** key gate.
4. Do **HARNESS-1** (ui-testing target).
5. Re-run **M1** (full) and **M2** (surface) — one clean pass each.
6. Write the final report; do the deferred task-doc `## Fixes` sync.

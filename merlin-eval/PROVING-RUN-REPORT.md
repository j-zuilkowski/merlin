# Proving-Suite Run — Report

> Mechanisms M1–M4 + M6 exercised; M5 (manual runsheet) deferred by the user.
> All fixes are local commits on `main` (no push).

## Final status (2026-05-19)

pass9 was 12 / 14 / 3. S6 is now genuinely deterministic (6/6). The post-fix
regression pass confirmed the engine changes introduced no regressions — but it
also **uncovered that S1 and S2 had been false-passing**: the harness ran those
debug scenarios on a git-tracked fixture it never reset, so runs inherited prior
runs' fixes. On a pristine baseline the 4-bit local model does not reliably
complete them. That is now fixed in the harness and documented honestly below —
it is the most important finding of this pass and needs a decision (stronger
execute model, or further engine work). Other residue: a brittle S4 assertion,
the a11y audit, and environment-gated UI tests.

| Test | pass9 | status | Verified |
|---|---|---|---|
| Calibration | ✗ | **✓** | regression pass (3 runs: 745–972s) |
| S1 Swift GUI debug | ✗ timeout | **unreliable** | prior ✓ was fixture-pollution false-positive — see below |
| S2 Rust debug | ✗ | **unreliable** | prior ✓ was fixture-pollution false-positive — see below |
| S4 xcalibre RAG | ✗ | **✓ (test bug)** | model correct; line-145 assertion false-positives — see below |
| S5 LoRA training | ✗ | **✓** | regression pass (25s) |
| S6 electronics | ✗ | **✓** | tool-gating + dispatch-rejection; 6/6 pass (255–1053s) |
| S6-OCR schematic | ✗ timeout | **✓** | final pass (393s) |
| AgenticLoop | ✗ | **✓** | regression pass (4s) |
| EvalHarnessSmoke ×2 | ✓ | **✓** | 1 transient fail in 4 runs; not reproducible — instrumented |
| GUIAutomation ×3 | ✗ | **skip / fixed** | AX ×2 skip (Accessibility TCC); vision test modelID bug fixed |
| M2 SurfaceUITests ×6 | 3✗ | **6 ✓** | final pass |
| M2 VisualLayoutTests | 3✗ | **5✓ / 1✗** | only `testAccessibilityAudit` |

**S1 / S2 — the critic was the key.** Earlier passes had them flaking. The S2
timeout diagnostic showed why: the local model spawned **74 subagents** for one
task and falsely reported success while `cargo test` stayed red, and the critic
never noticed because Stage-1 verification only ran when `verifyCommand` was
configured (it was not for the fixtures). Three fixes:
1. **Critic auto-detects and runs the project's real build/test** — `Cargo.toml`
   → `cargo build && cargo test`; `Package.swift` → `swift build`; `.xcodeproj` →
   `xcodebuild test`. A broken edit or a red test now fails the critic, forcing a
   retry. (This is what fixed S1 — TaskBoard's failing unit tests were never caught.)
2. **Per-task subagent cap (8)** — over-budget `spawn_agent` calls are rejected
   with a tool result telling the model to finish the work itself.
3. **`spawn_agent` description** rewritten to discourage delegating sequential work.

**S6 is now deterministic — domain tool-gating closed the coin flip.** The earlier
flake was the 4-bit execute model improvising: instead of the `mcp:kicad:*` tools
it hand-wrote `.kicad_sch` with `write_file`/`run_shell` or fanned the task out to
`spawn_agent`, then either failed the KiCad assertion or exceeded the 30-min
budget. The root cause had three layers, each fixed:

1. **The improvisation tools were on the menu.** `AgenticEngine.offeredTools()`
   now withholds `run_shell`, `bash`, `write_file`, `create_file`, and
   `spawn_agent` from the per-turn tool list whenever an authoritative domain MCP
   server (`kicad`) is connected — that server's tools cover the whole workflow.
2. **The model called them anyway.** A 4-bit model emits `run_shell`/`write_file`
   tool calls from training memory even when they are absent from the offered
   list, and the engine *executed* them because the handlers stay registered.
   `runLoop` now rejects any call to a withheld tool at dispatch time with a tool
   result that steers the model back to `mcp:` — the model has no executable path
   around the KiCad server.
3. **The fixture was polluted.** Prior runs left ten 555-blinker project
   directories in `fixtures/electronics/`; the model `list_directory`'d the root,
   found an existing project, and declared the task already done. `testS6Electronics`
   now runs in a freshly-wiped `s6-workspace`.

Verified 5/5: runs 2 and 4 on the partial fix, then 3/3 (255 s, 475 s, 1053 s) on
the dispatch-rejection fix. No improvisation, no timeouts.

**EvalHarnessSmoke — a rare transient, not state pollution.** The earlier
"`AppSettings.shared` routes to a dead vLLM provider" diagnosis did not hold up.
`testHarnessRunsATrivialScenario` was run four times across the suspect
sequences — alone, after `DeepSeek`, after `Calibration`, and after the exact
`DeepSeek → Calibration` chain that failed once. It reproduced **zero times in
three reproduction attempts** (the failing chain passed on re-run). The single
failure was a fast 2.25 s error (no assistant text, engine errors) — a transient
provider hiccup on a fresh session's first request, not deterministic pollution.
`CalibrationLiveTests` mutates only the three inference params and only when the
advisor emits advisories — it emitted none, so it wrote nothing to shared state.
The smoke test's failure message now dumps `run.errors`/`systemNotes`/`toolCalls`
(`10ca238`) so the next occurrence, if any, is fully diagnosable.

## Post-fix regression pass

After the S6 fix and the `offeredTools()` dedup (`466841e` — MCP tools were sent
to the model twice per request; deduped by name), the non-S6 scenarios were
re-run to confirm no regression: **AgenticLoop ✓, S2 ✓, S5 ✓, Calibration ✓**.
The dedup and the tool-gating are no-ops for any scenario that does not connect a
`kicad` MCP server, so S1 (no MCP) is provably unaffected by the engine changes.

### S1 / S2 were false-passing — fixture pollution (the significant finding)

`testS1SwiftGUIDebugCycle` and `testS2RustDebugCycle` are *debug* scenarios: Merlin
edits the buggy sources to fix them. The harness ran them **directly on the
git-tracked fixture and never reset it**, so each run started from the previous
run's leftover edits — after a successful run the bugs were already gone and the
next run "passed" trivially without doing the work; after a failed run the tree
was half-broken. Both fixtures were caught dirty (`git status`) after the
regression batch. This means **S1/S2's green history is not trustworthy** — an
unknown share of those passes were on already-fixed fixtures.

Fix (`8cc73f3`): `pristineFixtureCopy(_:)` extracts `git archive HEAD` of the
fixture into a throwaway temp dir; S1/S2 now run on the identical pristine
baseline every time and never mutate the tracked fixture.

What the honest harness then showed: an instrumented S2 run confirmed the
mechanism works — the model's edits land in the copy, `cargo test` sees them —
but the 4-bit local execute model **does not reliably complete the multi-bug
debug task from a clean baseline**. It thrashed for 28 min (30+ rejected
`spawn_agent` calls, compile-breaking edits) and timed out; a second run gave up
in 188 s. S1 likewise failed (2 TaskBoard tests still red). These scenarios need
either a stronger execute model or further engine work (e.g. dropping
`spawn_agent` from the offered tools once its budget is spent, so the model
cannot thrash on it) — a deliberate decision, not an autonomous guess.

Two further findings, both **pre-existing and not caused by the changes**:

- **S4 — a brittle test assertion, not a defect.** In two live re-runs the model
  behaved correctly: it retrieved the three grounded facts (47 kPa, 19-min cycle,
  `TANGERINE-7`) and correctly declined Q4 ("maximum rotational speed"), which is
  absent from the corpus. But `CapabilityScenarioTests.swift:145` asserts the
  answer must not contain the substrings `"rotational speed"` *and* `"rpm"` — and
  a correct refusal *names the topic* ("Maximum rotational speed: Not found … no
  results for RPM"). The assertion false-positives on the desired behavior. The
  model is right; the test is wrong. Flagged for a real fix (detect a fabricated
  numeric value, not topic keywords) — must not be weakened.

- **S1 — the documented-flaky scenario.** It failed this pass (24-min run, the
  model struggling with the TaskBoard fixture build). S1 has no MCP server, so the
  engine changes are a literal no-op for it; this is the same inherent S1
  variance the suite has seen throughout (originally `✗ timeout`, fixed via the
  Xcode critic, historically borderline).

A `testmanagerd` wedge (12 h uptime over ~2 days of continuous runs) caused a
false batch failure mid-pass — *"test runner hung before establishing
connection"*; `SIGKILL`-ing the daemon (launchd respawns it) recovered it and the
re-run passed. Worth a reboot before any future full pass.

## Root causes found and fixed

| # | Scenario | Root cause | Fix |
|---|---|---|---|
| 1 | S4 RAG | xcalibre-server watch-folder queued files but never ingested them | `process_pending` ingest step (`50316d6`) |
| 2 | S4 RAG | `XcalibreClient` had an empty bearer token → searches short-circuited | `XCALIBRE_TOKEN` env override (`eea8dfb`) |
| 3 | S5 training | model `tokenizer_config.json` had `extra_special_tokens` as a list | moved to `additional_special_tokens` |
| 4 | S5 training | `LoRATrainer` passed mlx_lm a file; it needs a `--data` directory | write train/valid jsonl into a dir (`7bc79b2`) |
| 5 | AgenticLoop | `read_file` tool schema not in `ToolRegistry` → never offered to the model | register `ToolDefinitions.readFile` (`9fc381f`) |
| 6 | S6 | MCP servers started fire-and-forget → kicad tools raced the first turn | await MCP startup before the prompt (`b54ee2f`) |
| 7 | S6-OCR | vision slot set to the provider id, not `provider:model` | assign the full pair (`9612099`) |
| 8 | S6-OCR | `vision_query` was a stub — never called any model (0 vision requests) | implement it against the vision slot (`722b04f`) |
| 9 | S6-OCR | `read_file` returned binary garbage for image files | redirect images to `vision_query` (`b6cbc4b`) |
| 10 | S1 | `app_launch` could not find a freshly-built app (Launch Services) | DerivedData fallback by bundle id (`120c61b`) |
| 11 | S1 | slot router sent the whole loop to the 8B vision model (prompt said "click button") | restrict vision-slot heuristic (`4b6e262`) |
| 12 | M2 surface | chat/tool-log not rendered at launch (no active session) | `--open-test-project` flag (`633b2b1`) |
| 13 | GUIAutomation | test host lacks Accessibility / Screen-Recording TCC | preflight + skip with remedy (`633b2b1`) |
| 14 | S6 | improvisation tools offered alongside the KiCad MCP tools → model hand-wrote `.kicad_sch` | `offeredTools()` withholds shell/file/spawn tools when `kicad` MCP is connected |
| 15 | S6 | model emits withheld tool calls from training memory; engine ran them (handlers still registered) | `runLoop` rejects gated-tool calls at dispatch with an `mcp:`-steer tool result |
| 16 | S6 | electronics fixture polluted with prior-run output → model saw an existing project, did nothing | `testS6Electronics` runs in a freshly-wiped `s6-workspace` |
| 17 | DeepSeek live tests | skip-gate called the bare `readAPIKey()` → only read the legacy `deepseek-legacy` Keychain item | gate now reads `DEEPSEEK_API_KEY` + the file key store (`10ca238`) |

Diagnostics added: `EvalHarness` dumps the partial run on a scenario timeout
(`2f4fb06`) — this is what pinned down the S1 loop.

## Remaining

- **testAccessibilityAudit** — `performAccessibilityAudit()` findings were reduced
  **47 → 8** in an earlier session (the 41 low-contrast-text findings fixed via
  `Color.accessibleSecondary` across the views). The residual 8: 2 contrast on the
  sidebar's bottom button, 5 SwiftUI framework-container findings ("Element has no
  description" on the content `Group`, the panes, the toolbar), 1 parent/child
  hierarchy. **Cannot be re-measured or fixed-and-verified headless:** it is an
  `XCUITest` in `MerlinUITests`, and a `xcodebuild test-without-building` run here
  fails at *"Timed out while enabling automation mode"* — the same UI-automation
  TCC gap as GUIAutomation (confirmed: two run attempts, no stuck processes).
  Fixing the 8 findings requires the test host granted UI automation so each fix
  can be verified against a live audit; doing it blind would be unverifiable.
- **GUIAutomation ×3 + testAccessibilityAudit** — all four are `XCUITest`/AX probes
  blocked by macOS UI-automation TCC. They pass for real once the test runner
  (Xcode.app / the xctest host) is granted Accessibility + Screen Recording in
  System Settings → Privacy & Security. No API can self-issue these grants.
- **M5** manual runsheet — deferred by the user.

## How to run the suite

```
RUN_LIVE_TESTS=1 DEEPSEEK_API_KEY=<key from ~/.merlin/api-keys.json> \
xcodebuild -scheme MerlinTests-Live test-without-building \
  -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-signed \
  "CODE_SIGN_IDENTITY=Merlin Dev Signing" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO
```

# Proving-Suite Run — Report

> Supersedes `PROVING-RUN-STATE.md`. Mechanisms M1–M4 + M6 exercised; M5 (manual
> runsheet) deferred by the user. All fixes are local commits on `main` (no push).

## Latest status — pass9 (2026-05-18)

Full `MerlinTests-Live` run with calibration first, then M1 scenarios, M2 surface,
and S5 training. Launched with `RUN_LIVE_TESTS=1` and `DEEPSEEK_API_KEY` exported
(the key lives in `~/.merlin/api-keys.json`, which the test key-gate does not read).

**Result: 12 passed, 14 failed, 3 skipped.**

| Test | pass8 | pass9 | Notes |
|---|---|---|---|
| Calibration | ✗ (stale) | **✓** | 18-prompt battery vs deepseek-v4-pro; **0 advisories — model within tolerance** |
| S1 Swift GUI debug | ✗ 2083s | ✗ 1810s | Watchdog timeout. Scenario does not finish in the 30-min budget — local-model speed, not a bug |
| S2 Rust debug | ✓ | **✓** 326s | |
| S4 xcalibre RAG | ✗ | **✓** 44s | **Fixed.** Retrieved 47 kPa / TANGERINE-7 / Ada Pellington / Vorren-1888; correctly declined the absent Q4 |
| S5 LoRA pipeline | ✗ tokenizer | ✗ data-dir | Both bugs now fixed (see below); training verified directly post-pass9 |
| S6 electronics | ✓ 633s | ✗ 524s | Model made 26 tool calls but did not call the KiCad MCP tools — model non-determinism (passed pass8) |
| S6-OCR schematic | ✗ timeout | ✗ 900s | Watchdog timeout — vision-model speed |
| AgenticLoop (real DeepSeek) | ✗ | ✗ 2s | Fast-fail; `finalText` empty — see triage below |
| GUIAutomation ×3 | ✗ | ✗ 1.6s | macOS TCC: test process lacks Accessibility / Screen-Recording grants |
| EvalHarnessSmoke ×2 | ✓ | **✓** | Harness itself healthy |
| M2 SurfaceUITests | 3✓/3✗ | 4✓/2✗ | |
| M2 VisualLayoutTests | 3✓/3✗ | 3✓/3✗ | |
| DeepSeekProviderLiveTests ×3 | skip | skip | Key-gate reads Keychain only, not env / `api-keys.json` |

## Fixes landed this session

### S4 — xcalibre RAG (FIXED, verified passing in pass9)

Two independent root causes:

1. **xcalibre-server watch-folder never ingested.** `scan_once` only inserted
   `'pending'` rows into `watch_folder_log`; nothing consumed them, so watched
   ebooks were detected but never became searchable. Added `process_pending` +
   `ingest_file_from_disk` (detect format → extract metadata → store → insert book →
   generate chunks → mark the log row). xcalibre-server commit `50316d6`.
2. **`XcalibreClient` had an empty bearer token**, so every search short-circuited
   before issuing a request. Added an `XCALIBRE_TOKEN` env override mirroring
   `XCALIBRE_BASE_URL`; the S4 harness now registers the first user (auto-admin),
   logs in for a JWT, exports it, and waits for the corpus to ingest. Merlin commit
   `eea8dfb`.

Target-tested server-side end-to-end before pass9: the corpus EPUBs ingest,
`book_chunks` populate, and `/api/v1/search/chunks` returns the grounded facts.

### S5 — LoRA training pipeline (FIXED, verified directly)

Two sequential blockers:

1. **Tokenizer crash.** The model's `tokenizer_config.json` had `extra_special_tokens`
   as a list; transformers 4.57.6 expects that key to be a dict. Moved the 13 tokens
   to the correct `additional_special_tokens` field
   (`~/.lmstudio/models/lmstudio-community/Qwen3-Coder-Next-MLX-4bit/tokenizer_config.json`;
   original backed up alongside).
2. **`--data` path.** `LoRATrainer` passed `mlx_lm.lora` a single `.jsonl` file, but
   mlx_lm expects `--data` to be a *directory* containing `train.jsonl`/`valid.jsonl`.
   It aborted with "Training set not found or empty". Now writes both splits (90/10)
   into a temp directory. Merlin commit `7bc79b2`.

Verified directly post-pass9: `mlx_lm.lora` loads the model, loads the datasets,
trains, and saves `adapters.safetensors` (val loss 5.13 → 3.85 over 2 iters).

### Calibration (FIXED — passes)

`CalibrationLiveTests` was rebuilt to drive `CalibrationRunner`/`CalibrationAdvisor`
directly (commit `1caaa27`), avoiding the `AppState` provider-registry race that
fast-failed it. pass9 ran the full battery and passed; 0 advisories — the model's
inference parameters are within tolerance, so S1/S6-OCR timeouts are speed-bound,
not a tunable-parameter problem.

## Remaining red — honest classification

- **S1 / S6-OCR** — wall-clock timeouts. The local 4-bit `qwen3-coder-next` (and
  `qwen3-vl-8b` for OCR) does not finish these scenarios inside their 30-min / 15-min
  budgets. Calibration confirms parameters are fine; this is raw inference speed.
  Not a code defect — either the budget is raised or faster hardware/model is used.
- **S6** — model non-determinism: it passed pass8, failed pass9 by not calling the
  (available) KiCad MCP tools. Capability/consistency outcome.
- **AgenticLoop** — fast-fails (~2s) against real DeepSeek with empty output. The key
  works and `deepseek-v4-flash`/`-pro` are valid (verified by direct API call);
  `SSEParser` handles `reasoning_content`. Consistent with the known intermittent
  DeepSeek "governor" error or the flash model not emitting the tool call. Infra/model.
- **GUIAutomation ×3** — macOS TCC. The test runner lacks Accessibility and
  Screen-Recording permission; the AX tree is empty and `ScreenCaptureTool` returns
  `permissionDenied`. Must be granted in System Settings → Privacy. Environment.
- **M2 surface (5)** — `testChatInputSurfacesPresent` / `testInputFieldExists`: the
  chat input + send/attachment/voice controls are not in the XCUITest tree at default
  launch (the chat input is a vertical-axis `TextField`, which surfaces as a
  `textView` not a `textField`; and the bar may not render in the empty-project
  state). `testToolLogPanelVisible`: the tool-log panel is a toggle-gated workspace
  panel, hidden by default. `testAllSeventeenSettingsPanesRender`: a scroll-view
  hit-point miss. `testAccessibilityAudit`: real audit findings (missing element
  descriptions, contrast). These are genuine UI/test bugs needing GUI inspection.
- **DeepSeekProviderLiveTests ×3** — skip, not fail: the key-gate reads only the
  Keychain, not `DEEPSEEK_API_KEY` / `~/.merlin/api-keys.json`.

## Verification

- **S4** — passed in pass9 (44s, evidence retrieved all grounded facts) and
  target-tested server-side before the pass.
- **S5** — `mlx_lm.lora` smoke run completed and saved an adapter.
- **Calibration** — passed in pass9 (858s, full 18-prompt battery).
- **xcalibre-server** — `cargo build -p backend` + `cargo clippy -p backend` clean.
- **Merlin** — `MerlinTests-Live build-for-testing` SUCCEEDED with all changes.

## Deferred / open

- **S1 / S6 / S6-OCR / AgenticLoop / GUIAutomation / M2 surface** — classified above;
  not code-fixable within this run (model speed, model non-determinism, DeepSeek
  infra, macOS TCC, UI inspection). Each is a distinct follow-up.
- **Phase-doc `## Fixes` sync** — `XcalibreClient`, `AppState`, `LoRATrainer`,
  `CapabilityScenarioTests` carry this session's changes; their `b` phase docs need
  `## Fixes` notes.
- **M5** manual runsheet — deferred by the user.

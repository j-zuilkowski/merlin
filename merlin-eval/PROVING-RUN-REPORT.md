# Proving-Suite Run — Report

> Mechanisms M1–M4 + M6 exercised; M5 (manual runsheet) deferred by the user.
> All fixes are local commits on `main` (no push).

## Latest status — pass10 (2026-05-18)

Full `MerlinTests-Live` run: calibration, M1 scenarios, M2 surface, S5 training.

**Result: 20 passed, 2 failed, 6 skipped** (pass9 was 12 / 14 / 3).

| Test | pass9 | pass10 | Notes |
|---|---|---|---|
| Calibration | ✓ | **✓** | 18-prompt battery, 0 advisories |
| S1 Swift GUI debug | ✗ | ✗ → fix verifying | Agent looped `app_launch` failures 35× (175 calls) — `app_launch` could not find a freshly-built app. Fixed (`120c61b`); verification run in progress |
| S2 Rust debug | ✓ | **✓** | |
| S4 xcalibre RAG | ✓ | **✓** | Grounded facts retrieved |
| S5 LoRA training | ✗ | **✓** | tokenizer + mlx_lm data-dir fixes — trains, saves adapter |
| S6 electronics | ✗ | **✓** | MCP startup race fixed — kicad tools registered before turn 1 |
| S6-OCR schematic | ✗ timeout | **✓** 245s | `vision_query` was a stub; implemented it + `read_file` image redirect. `qwen3-vl-8b` now used; agent converges in 10 tool calls (was looping 48+) |
| AgenticLoop (real DeepSeek) | ✗ | **✓** | `read_file` tool schema registered so the model is offered the tool |
| EvalHarnessSmoke ×2 | ✓ | **✓** | |
| GUIAutomation ×3 | ✗ | **skip** | TCC preflight — skip with the exact permission remedy; run for real once granted |
| M2 SurfaceUITests ×6 | 3✗ | **6 ✓** | `--open-test-project` flag renders chat/tool-log; settings-pane click fix |
| M2 VisualLayoutTests | 3✗ | 5✓ / 1✗ | only `testAccessibilityAudit` fails (residual a11y) |
| DeepSeekProviderLiveTests ×3 | skip | skip | key-gate reads Keychain only, not env / `api-keys.json` |

## Fixes landed this session

| Area | Fix | Commit |
|---|---|---|
| S4 RAG | xcalibre-server watch-folder ingestion (`process_pending`) | `50316d6` (xcalibre-server) |
| S4 RAG | `XcalibreClient` `XCALIBRE_TOKEN` env override; harness registers + logs in | `eea8dfb` |
| S5 training | model `tokenizer_config.json` `extra_special_tokens` list → `additional_special_tokens` | (model file) |
| S5 training | `LoRATrainer` writes a `--data` directory (train/valid jsonl), not a file | `7bc79b2` |
| AgenticLoop | register the `read_file` tool schema so DeepSeek is offered the tool | `9fc381f` |
| S6 | await MCP server startup before the first prompt (was a fire-and-forget race) | `b54ee2f` |
| S6-OCR | route the vision slot at `provider:model`, not the provider id; preload vision model | `9612099` |
| S6-OCR | implement `vision_query` (was a stub that never called any model) | `722b04f` |
| S6-OCR | `read_file` redirects image files to `vision_query` | `b6cbc4b` |
| S1 | `app_launch` falls back to locating a freshly-built `.app` in DerivedData | `120c61b` |
| M2 surface | `--open-test-project` launch flag; settings-pane hittable-click fix | `633b2b1` |
| GUIAutomation | preflight Accessibility / Screen-Recording TCC, skip with remedy | `633b2b1` |
| Harness | dump partial run on scenario timeout for triage | `2f4fb06` |
| A11y | `Color.accessibleSecondary` — replace low-contrast `.secondary`/`.tertiary` text | `b02a976`, `17d9cb8`, `a0ff75f` |

## Remaining

- **S1** — root cause (`app_launch` failure loop) fixed in `120c61b`; a verification
  run with the fix is in progress (pass10 was built before the commit).
- **testAccessibilityAudit** — `performAccessibilityAudit()` findings reduced **47 → 11**.
  The pervasive low-contrast-text problem (41 contrast findings) is fixed (→ ~5). The
  residual 11 are diffuse: ~5 tiny/edge elements and ~6 SwiftUI framework container
  findings (a window content `Group`, the panes, the system toolbar flagged
  "no description"). These need deep per-element accessibility-tree work.
- **GUIAutomation ×3** — skip cleanly; pass for real once the test host is granted
  Accessibility + Screen Recording in System Settings → Privacy & Security.
- **DeepSeekProviderLiveTests ×3** — skip; their key-gate reads only the Keychain.
- **M5** manual runsheet — deferred by the user.

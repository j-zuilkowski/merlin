# Proving-Suite Run — Report

> Mechanisms M1–M4 + M6 exercised; M5 (manual runsheet) deferred by the user.
> All fixes are local commits on `main` (no push).

## Final status (2026-05-18)

Every proving-suite scenario now passes or skips gracefully. The only failing
test is `testAccessibilityAudit` (a reduced set of residual findings).

| Test | pass9 | now | Verified |
|---|---|---|---|
| Calibration | ✗ | **✓** | pass10 (884s) |
| S1 Swift GUI debug | ✗ timeout | **✓** | verify run (1565s) |
| S2 Rust debug | ✓ | **✓** | pass10 |
| S4 xcalibre RAG | ✗ | **✓** | pass10 (59s) |
| S5 LoRA training | ✗ | **✓** | pass10 (33s) |
| S6 electronics | ✗ | **✓** | pass10 (1190s) |
| S6-OCR schematic | ✗ timeout | **✓** | pass10 (245s) |
| AgenticLoop | ✗ | **✓** | pass10 (3s) |
| EvalHarnessSmoke ×2 | ✓ | **✓** | pass10 |
| GUIAutomation ×3 | ✗ | **skip** w/ remedy | pass10 — run for real once TCC granted |
| M2 SurfaceUITests ×6 | 3✗ | **6 ✓** | pass10 |
| M2 VisualLayoutTests | 3✗ | 5✓ / 1✗ | only `testAccessibilityAudit` fails |

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

Diagnostics added: `EvalHarness` dumps the partial run on a scenario timeout
(`2f4fb06`) — this is what pinned down the S1 loop.

## Remaining

- **testAccessibilityAudit** — `performAccessibilityAudit()` findings reduced
  **47 → 8**. The pervasive low-contrast-text problem (41 contrast findings) is
  fixed via `Color.accessibleSecondary` applied across the views. The residual 8:
  2 contrast on the sidebar's bottom button, 5 SwiftUI framework container
  findings ("Element has no description" on the content `Group`, the panes, the
  toolbar), 1 parent/child hierarchy. These need deep per-element accessibility-
  tree work; the framework-container findings are not user-facing defects.
- **GUIAutomation ×3** — pass for real once the test host is granted Accessibility
  + Screen Recording in System Settings → Privacy & Security.
- **DeepSeekProviderLiveTests ×3** — skip; their key-gate reads only the Keychain,
  not `DEEPSEEK_API_KEY` / `~/.merlin/api-keys.json`.
- **M5** manual runsheet — deferred by the user.

## How to run the suite

```
RUN_LIVE_TESTS=1 DEEPSEEK_API_KEY=<key from ~/.merlin/api-keys.json> \
xcodebuild -scheme MerlinTests-Live test-without-building \
  -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-signed \
  "CODE_SIGN_IDENTITY=Merlin Dev Signing" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO
```

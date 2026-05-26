# Merlin Full GUI E2E Audit - 2026-05-26

## Summary

This audit exercised Merlin through automated tests, live-provider tests, direct local provider smoke tests, xcalibre-server RAG HTTP verification, and manual human-style GUI operation with screenshots.

Overall status: **partially green, with S2 repaired and verified**. Core unit/integration tests are green, DeepSeek live tests are green, llama.cpp router text and vision are green, xcalibre-server RAG is reachable by HTTP, and the isolated S2 Rust debug cycle now passes with the real sibling `xcalibre-server` backend. The remaining known gaps from this audit are S1 local-execute reliability, the UI test runner bootstrap crash, and the settings/UI issues listed below.

## Environment

- Date: 2026-05-26
- Workspace: `/Users/jonzuilkowski/Documents/localProject/merlin`
- Derived data: `/tmp/merlin-e2e-derived`
- Derived app: `/tmp/merlin-e2e-derived/Build/Products/Debug/Merlin.app`
- Local provider constraint: one local provider pair at a time
- Local provider pair:
  - Execute: `llama.cpp` router model `qwen3-coder-local`
  - Vision: `llama.cpp` router model `qwen3-vl-local`
- Critic/reason/reference provider: DeepSeek
- RAG server: xcalibre-server from `/Users/jonzuilkowski/Documents/localProject/xcalibre-server`

## Automated Results

| Area | Result | Evidence |
|---|---|---|
| Unit and integration tests | PASS | latest rerun: executed 2116 tests, 51 skipped, 0 failures |
| Live build-for-testing | PASS | `logs/xcodebuild-MerlinTests-Live-build-for-testing.log`: test build succeeded |
| DeepSeek live provider tests | PASS | `logs/xcodebuild-MerlinTests-Live-rerun.log`: 3 tests, 0 failures |
| Agentic loop with real DeepSeek | PASS | `logs/xcodebuild-MerlinTests-Live-rerun.log`: passed |
| llama.cpp router text smoke | PASS | `logs/llamacpp-router.log`; response returned `MERLIN_LOCAL_TEXT_OK` |
| llama.cpp router vision smoke | PASS | `logs/llamacpp-router.log`; response returned `MERLIN_LOCAL_VISION_OK` |
| llama.cpp one-loaded-model behavior | PASS | `logs/llamacpp-models-after-smoke.json`; text model unloaded after vision model loaded |
| xcalibre-server health and search API | PASS | `logs/xcalibre-server.log`, `logs/xcalibre-rag-sentinel.json`; sentinel chunk returned |
| Merlin live RAG path inside capability scenario | PASS for S2 rerun | `rerun-live-20260526T153909Z/logs/xcalibre-openapi.json`; S2 ran against configured `http://127.0.0.1:8083` xcalibre-server |
| Capability scenario S1 | FAIL | `logs/xcodebuild-MerlinTests-Live-rerun.log`; `TaskBoardTests must pass after Merlin's fixes` |
| Capability scenario S2 | PASS | `S2-RERUN.md`; isolated rerun passed in 269.698s after project-root tool scoping, configured xcalibre-server endpoint use, llama.cpp context recovery, and bounded planner default fixes |
| UI test runner | FAIL | `logs/xcodebuild-MerlinUITests-selective.log`; runner crashed before establishing connection |

## Manual GUI Coverage

The derived app was launched directly and operated through the macOS UI. Screenshots were captured for the major functions reached during the run.

| Surface | Result | Screenshot |
|---|---|---|
| Main workspace and slot status | PASS | `screenshots/01-main-slot-status.jpg` |
| File viewer | PASS | `screenshots/02-file-viewer.jpg` |
| Terminal pane | PASS | `screenshots/03-terminal-pane.jpg` |
| Terminal command execution | PASS | `screenshots/04-terminal-run-pwd.jpg` |
| CAG metrics pane | PASS | `screenshots/05-cag-metrics-pane.jpg` |
| Electronics jobs pane | PASS | `screenshots/06-electronics-jobs-pane.jpg` |
| Side chat pane | PASS | `screenshots/07-side-chat-pane.jpg` |
| Memories sheet | PASS | `screenshots/08-memories-sheet.jpg` |
| Settings General | PASS | `screenshots/09-settings-general.jpg` |
| Settings Providers | PASS with issues noted below | `screenshots/10-settings-providers.jpg` |

## Hidden / Debug-Only UI Audit

Result: **no unreachable hidden UI elements were found in normal visible app operation**, and no unused `AccessibilityID` constants were found.

Static checks performed:

- Enumerated `AccessibilityID` constants and verified source references.
- Searched app and test sources for hidden/debug/test-only UI patterns:
  - `--...` launch flags
  - `show...ForTesting`
  - `forTesting`
  - `#if DEBUG`
  - `debugOnly`
  - `accessibilityHidden`
  - `.hidden(`
  - `opacity(0)`
  - `isHidden`

Findings:

1. `--open-test-project` exists in `Merlin/Views/ContentView.swift` and `Merlin/Views/WorkspaceView.swift`.
2. `--show-auth-popup-for-testing` exists in `Merlin/App/AppState.swift`.
3. `#if DEBUG` file-backed API key behavior exists in `Merlin/Keychain/KeychainManager.swift`.

These are test/debug hooks rather than hidden visible controls. If the project standard is "no debug/test-only launch hooks in a release-capable binary," the two launch flags should be moved behind a stronger test-only build gate or replaced with a dedicated UI-test harness mechanism.

## Defects and Risks Found

1. Full live capability is not green with the local execute model. S2 now passes, but S1 still fails because the local execute model does not complete the Swift GUI debug cycle successfully.
2. The UI test runner crashes before bootstrapping. This prevents relying on the XCTest UI suite for exhaustive GUI coverage until the runner startup issue is fixed.
3. The Providers settings UI has a likely copy/paste label defect: the Mistral.rs section exposes `Load Parameters - lmstudio`.
4. The llama.cpp runtime settings panel did not visibly reflect the temporary explicit models directory and router preset path used for the test; it displayed default-looking paths. This needs verification against the settings model.
5. Multiple Merlin builds share `com.merlin.app`, which confused app attachment during manual automation and can cause the installed `/Applications/Merlin.app` to be opened or inspected instead of the derived app.
6. The llama.cpp router exposes a `default` model entry in `/v1/models` in addition to explicit router models. Merlin selected explicit IDs during this audit, but the provider should continue to avoid accidental selection of the router artifact.

## RAG Fixture

xcalibre-server was started from the xcalibre repo, not from the Merlin repo. A temporary token and memory chunk were inserted, queried, and then removed.

Sentinel text:

```text
Merlin E2E RAG sentinel: the slot status panel uses red orange green and grey dots; xcalibre retrieval should return this sentence for sentinel queries.
```

Cleanup completed:

- Restored original `~/.merlin/config.toml`.
- Restored original `~/Library/Application Support/Merlin/providers.json`.
- Removed the temporary xcalibre API token.
- Removed the temporary xcalibre memory chunk.
- Stopped xcalibre-server.
- Stopped llama.cpp router.
- Stopped derived Merlin app instances.

## Artifacts

- Test matrix: `TEST-MATRIX.md`
- llama.cpp router preset: `llamacpp-router-models.ini`
- Vision smoke request: `vision-smoke-request.json`
- Logs: `logs/`
- Screenshots: `screenshots/`
- Capability reports:
  - `../../../../merlin-eval/results/S1-harness-2026-05-26T14-15-41Z.md`
  - `../../../../merlin-eval/results/S1-harness-2026-05-26T14-21-52Z.md`
  - `../../../../merlin-eval/results/S2-harness-2026-05-26T15-44-02Z.md`

## Recommended Next Work

1. Repair the UI test runner bootstrap failure so GUI coverage can be automated instead of relying mainly on manual Computer Use operation.
2. Improve local execute model reliability for S1 or route S1 to a model/profile that can complete the required Swift GUI debug cycle under the one-local-pair constraint.
3. Fix the Mistral.rs settings label artifact.
4. Verify and fix llama.cpp runtime settings persistence/display for models directory and router preset.
5. Add a distinct bundle identifier or launch/attachment guard for derived test builds to avoid automation attaching to the installed app.
6. Decide whether test-only launch flags are acceptable in release-capable builds; if not, move them behind a stricter test harness boundary.

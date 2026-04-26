# Codex Paste List — Merlin

Model: gpt-5.4-mini
Invocation pattern: paste phase file content into Codex app prompt field.
Each phase is independent. Complete and verify before moving to the next.

---

```bash
# ── PHASE 00 — Preflight (run this first, before touching Codex) ─────
cd ~/Documents/localProject/merlin
bash phases/phase-00-preflight.sh
# Must exit 0 before continuing. Warnings are non-fatal but note them.
# Script auto-installs: xcodegen
# Script checks: macOS 14+, Xcode 15+, CLT, Swift, Homebrew, Codex CLI,
#                LM Studio + Qwen2.5-VL model, DeepSeek key, disk space,
#                project directory integrity
# Manual actions the script cannot do for you:
#   - Grant Accessibility permission to Merlin.app (after first build)
#   - Grant Screen Recording permission to Merlin.app (after first build)
#   - Load Qwen2.5-VL-72B-Instruct-Q4_K_M in LM Studio (~43GB download)

# ── SETUP ────────────────────────────────────────────────────────────

# Codex context file — paste HANDOFF.md content before each phase prompt.
cat phases/HANDOFF.md

# ── PHASE 01 — Scaffold (xcodegen) ───────────────────────────────────
# Paste into Codex:
cat phases/phase-01-scaffold.md
# CHECKPOINT (manual): xcodegen generate
# CHECKPOINT: xcodebuild -scheme MerlinTests build-for-testing succeeds

# ── PHASE 02a — Shared Types Tests ──────────────────────────────────
cat phases/phase-02a-shared-types-tests.md
# CHECKPOINT: file compiles with missing-type errors (not logic errors)

# ── PHASE 02b — Shared Types Implementation ──────────────────────────
cat phases/phase-02b-shared-types.md
# CHECKPOINT: swift test --filter SharedTypesTests → 5 pass

# ── PHASE 03a — Provider Tests ───────────────────────────────────────
cat phases/phase-03a-provider-tests.md
# CHECKPOINT: compiles with missing-type errors

# ── PHASE 03b — DeepSeekProvider + SSEParser ────────────────────────
cat phases/phase-03b-deepseek-provider.md
# CHECKPOINT: swift test --filter ProviderTests → 5 pass

# ── PHASE 04 — LMStudioProvider ─────────────────────────────────────
cat phases/phase-04-lmstudio-provider.md
# CHECKPOINT: swift build passes; live test skips without RUN_LIVE_TESTS

# ── PHASE 05 — KeychainManager ──────────────────────────────────────
cat phases/phase-05-keychain.md
# CHECKPOINT: swift test --filter KeychainTests → 3 pass

# ── PHASE 06 — Tool Definitions ─────────────────────────────────────
cat phases/phase-06-tool-definitions.md
# CHECKPOINT: ToolDefinitions.all has 33 entries; swift build passes

# ── PHASE 07a — FileSystem + Shell Tests ────────────────────────────
cat phases/phase-07a-filesystem-shell-tests.md
# CHECKPOINT: compiles with missing-type errors

# ── PHASE 07b — FileSystem + Shell Implementation ───────────────────
cat phases/phase-07b-filesystem-shell.md
# CHECKPOINT: swift test --filter FileSystemToolTests → 5 pass
#             swift test --filter ShellToolTests → 4 pass

# ── PHASE 08a — Xcode Tools Tests ───────────────────────────────────
cat phases/phase-08a-xcode-tools-tests.md
# CHECKPOINT: compiles with missing-type errors

# ── PHASE 08b — Xcode Tools Implementation ──────────────────────────
cat phases/phase-08b-xcode-tools.md
# CHECKPOINT: swift test --filter XcodeToolTests → pass (fixture may skip)

# ── PHASE 09a — AX + ScreenCapture Tests ────────────────────────────
cat phases/phase-09a-ax-screencapture-tests.md
# CHECKPOINT: compiles with missing-type errors

# ── PHASE 09b — AXInspectorTool + ScreenCaptureTool ─────────────────
cat phases/phase-09b-ax-screencapture.md
# CHECKPOINT: swift test --filter AXInspectorTests → pass (Accessibility granted)
#             swift test --filter ScreenCaptureTests → pass or skip

# ── PHASE 10 — CGEventTool + VisionQueryTool ────────────────────────
cat phases/phase-10-cgevent-vision.md
# CHECKPOINT: swift test --filter CGEventToolTests → 2 pass

# ── PHASE 11 — AppControlTools + ToolDiscovery ──────────────────────
cat phases/phase-11-appcontrol-discovery.md
# CHECKPOINT: swift test --filter AppControlTests → pass
#             swift test --filter ToolDiscoveryTests → pass

# ── PHASE 12a — Auth Tests ──────────────────────────────────────────
cat phases/phase-12a-auth-tests.md
# CHECKPOINT: compiles with missing-type errors

# ── PHASE 12b — PatternMatcher + AuthMemory ─────────────────────────
cat phases/phase-12b-auth-impl.md
# CHECKPOINT: swift test --filter PatternMatcherTests → 5 pass
#             swift test --filter AuthMemoryTests → 3 pass

# ── PHASE 13a — AuthGate Tests ──────────────────────────────────────
cat phases/phase-13a-authgate-tests.md
# CHECKPOINT: compiles with missing-type errors

# ── PHASE 13b — AuthGate Implementation ─────────────────────────────
cat phases/phase-13b-authgate-impl.md
# CHECKPOINT: swift test --filter AuthGateTests → 4 pass

# ── PHASE 14a — ContextManager Tests ────────────────────────────────
cat phases/phase-14a-contextmanager-tests.md
# CHECKPOINT: compiles with missing-type errors

# ── PHASE 14b — ContextManager Implementation ───────────────────────
cat phases/phase-14b-contextmanager-impl.md
# CHECKPOINT: swift test --filter ContextManagerTests → 5 pass

# ── PHASE 15 — ToolRouter ───────────────────────────────────────────
cat phases/phase-15-toolrouter.md
# CHECKPOINT: swift test --filter ToolRouterTests → 2 pass

# ── PHASE 16 — ThinkingModeDetector ─────────────────────────────────
cat phases/phase-16-thinking-detector.md
# CHECKPOINT: swift test --filter ThinkingModeDetectorTests → 6 pass

# ── PHASE 17a — AgenticEngine Tests ─────────────────────────────────
cat phases/phase-17a-agenticengine-tests.md
# CHECKPOINT: compiles with missing-type errors

# ── PHASE 17b — AgenticEngine Implementation ────────────────────────
cat phases/phase-17b-agenticengine-impl.md
# CHECKPOINT: swift test --filter AgenticEngineTests → 4 pass

# ── PHASE 18 — Sessions ─────────────────────────────────────────────
cat phases/phase-18-sessions.md
# CHECKPOINT: swift test --filter SessionSerializationTests → 4 pass

# ── PHASE 19 — AppState + Entry Point ───────────────────────────────
cat phases/phase-19-appstate-entrypoint.md
# CHECKPOINT: swift build passes; app launches without crash

# ── PHASE 19b — Tool Handler Registration ───────────────────────────
cat phases/phase-19b-tool-registration.md
# CHECKPOINT: ToolDefinitions.all.count == 37 matches registered handlers
#             swift build — zero errors

# ── PHASE 20 — ContentView + ChatView + ProviderHUD ─────────────────
cat phases/phase-20-chatview.md
# CHECKPOINT: app shows chat UI; send button calls engine.send

# ── PHASE 21 — ToolLogView + ScreenPreviewView ──────────────────────
cat phases/phase-21-secondary-views.md
# CHECKPOINT: 3-panel layout visible
#             swift test --filter VisualLayoutTests/testNoWidgetsClipped → pass
#             swift test --filter VisualLayoutTests/testAccessibilityAudit → pass

# ── PHASE 22 — AuthPopupView + FirstLaunchSetup ─────────────────────
cat phases/phase-22-authpopup.md
# CHECKPOINT: auth popup appears and responds to keyboard shortcuts
#             first-launch setup saves key and dismisses

# ── PHASE 23 — TestTargetApp ────────────────────────────────────────
cat phases/phase-23-test-fixture-app.md
# CHECKPOINT: TestTargetApp builds and shows all 8 elements
#             E2E tests skip cleanly without RUN_LIVE_TESTS

# ── PHASE 24 — Live Tests + Final E2E ───────────────────────────────
cat phases/phase-24-live-e2e.md
# CHECKPOINT (requires RUN_LIVE_TESTS=1 + DEEPSEEK_API_KEY):
#   DeepSeekProviderLiveTests → 3 pass
#   AgenticLoopE2ETests → 1 pass (reads real file via real API)
#   GUIAutomationE2ETests → pass (with Accessibility + LM Studio running)

# ── DONE ─────────────────────────────────────────────────────────────
# Final: swift test (MerlinTests scheme) → all unit + integration pass
#        swift build → zero errors, zero warnings
```

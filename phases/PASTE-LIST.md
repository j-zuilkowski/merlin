# Codex Paste List — Merlin

Model: gpt-5.4-mini
Invocation: paste the content of each phase file directly into the Codex prompt.
No terminal trips, no HANDOFF.md references — every file is self-contained.
Each file includes its own context header, full task, verify step, and git commit.

---

```bash
# ── PHASE 00 — Preflight (run once in terminal before starting Codex) ───
cd ~/Documents/localProject/merlin
bash phases/phase-00-preflight.sh
# Must exit 0. Warnings are non-fatal.

# ── HOW TO RUN EACH PHASE ──────────────────────────────���─────────────────
# In Codex, paste the content of each phase file:
#   cat phases/phase-XX-name.md
# Codex reads the instructions, writes the files, runs the verify step,
# and commits. Then move to the next phase.

# ── PHASE 01 — Scaffold (xcodegen) ──────────────────────��────────────────
cat phases/phase-01-scaffold.md
# Verify: xcodegen generate + xcodebuild -scheme MerlinTests build-for-testing → BUILD SUCCEEDED
# Commit: git commit -m "Phase 01 — xcodegen scaffold"

# ── PHASE 02a — Shared Types Tests ───────────────────────────────────────
cat phases/phase-02a-shared-types-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 02a

# ── PHASE 02b — Shared Types Implementation ──────────────────────────────
cat phases/phase-02b-shared-types.md
# Verify: SharedTypesTests → 5 pass
# Commit: Phase 02b

# ── PHASE 03a — Provider Tests ───────────────────────────────────────────
cat phases/phase-03a-provider-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 03a

# ── PHASE 03b — DeepSeekProvider + SSEParser ─────────────────────────────
cat phases/phase-03b-deepseek-provider.md
# Verify: ProviderTests → 5 pass
# Commit: Phase 03b

# ── PHASE 04 — LMStudioProvider ──────────────────────────────────────────
cat phases/phase-04-lmstudio-provider.md
# Verify: BUILD SUCCEEDED; live test skips without RUN_LIVE_TESTS
# Commit: Phase 04

# ── PHASE 05 — KeychainManager ───────────────────────────────────────────
cat phases/phase-05-keychain.md
# Verify: KeychainTests → 3 pass
# Commit: Phase 05

# ── PHASE 06 — Tool Definitions ──────────────────────────────────────────
cat phases/phase-06-tool-definitions.md
# Verify: BUILD SUCCEEDED; ToolDefinitions.all.count == 37
# Commit: Phase 06

# ── PHASE 07a — FileSystem + Shell Tests ─────────────────────────────────
cat phases/phase-07a-filesystem-shell-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 07a

# ── PHASE 07b — FileSystem + Shell Implementation ────────────────────────
cat phases/phase-07b-filesystem-shell.md
# Verify: FileSystemToolTests → 5 pass; ShellToolTests → 4 pass
# Commit: Phase 07b

# ── PHASE 08a — Xcode Tools Tests ────────────────────────────────────────
cat phases/phase-08a-xcode-tools-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 08a

# ── PHASE 08b — Xcode Tools Implementation ───────────────────────────────
cat phases/phase-08b-xcode-tools.md
# Verify: XcodeToolTests → pass (fixture test may skip)
# Commit: Phase 08b

# ── PHASE 09a — AX + ScreenCapture Tests ─────────────────────────────────
cat phases/phase-09a-ax-screencapture-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 09a

# ── PHASE 09b — AXInspectorTool + ScreenCaptureTool ──────────────────────
cat phases/phase-09b-ax-screencapture.md
# Verify: AXInspectorTests → pass (needs Accessibility); ScreenCaptureTests → pass or skip
# Commit: Phase 09b

# ── PHASE 10 — CGEventTool + VisionQueryTool ──────────────────────────────
cat phases/phase-10-cgevent-vision.md
# Verify: CGEventToolTests → 2 pass
# Commit: Phase 10

# ── PHASE 11 — AppControlTools + ToolDiscovery ────────────────────────────
cat phases/phase-11-appcontrol-discovery.md
# Verify: AppControlTests → pass; ToolDiscoveryTests → pass
# Commit: Phase 11

# ── PHASE 12a — Auth Tests ────────────────────────────────────────────────
cat phases/phase-12a-auth-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 12a

# ── PHASE 12b — PatternMatcher + AuthMemory ───────────────────────────────
cat phases/phase-12b-auth-impl.md
# Verify: PatternMatcherTests → 5 pass; AuthMemoryTests → 3 pass
# Commit: Phase 12b

# ── PHASE 13a — AuthGate Tests ────────────────────────────────────────────
cat phases/phase-13a-authgate-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 13a

# ── PHASE 13b — AuthGate Implementation ───────────────────────────────────
cat phases/phase-13b-authgate-impl.md
# Verify: AuthGateTests → 4 pass
# Commit: Phase 13b

# ── PHASE 14a — ContextManager Tests ──────────────────────────────────────
cat phases/phase-14a-contextmanager-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 14a

# ── PHASE 14b — ContextManager Implementation ─────────────────────────────
cat phases/phase-14b-contextmanager-impl.md
# Verify: ContextManagerTests → 5 pass
# Commit: Phase 14b

# ── PHASE 15 — ToolRouter ─────────────────────────────────────────────────
cat phases/phase-15-toolrouter.md
# Verify: ToolRouterTests → 2 pass
# Commit: Phase 15

# ── PHASE 16 — ThinkingModeDetector ───────────────────────────────────────
cat phases/phase-16-thinking-detector.md
# Verify: ThinkingModeDetectorTests → 6 pass
# Commit: Phase 16

# ── PHASE 17a — AgenticEngine Tests ───────────────────────────────────────
cat phases/phase-17a-agenticengine-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 17a

# ── PHASE 17b — AgenticEngine Implementation ──────────────────────────────
cat phases/phase-17b-agenticengine-impl.md
# Verify: AgenticEngineTests → 4 pass; zero warnings
# Commit: Phase 17b

# ── PHASE 18 — Sessions ───────────────────────────────────────────────────
cat phases/phase-18-sessions.md
# Verify: SessionSerializationTests → 4 pass
# Commit: Phase 18

# ── PHASE 19 — AppState + Entry Point ─────────────────────────────────────
cat phases/phase-19-appstate-entrypoint.md
# Verify: BUILD SUCCEEDED
# Commit: Phase 19

# ── PHASE 19b — Tool Handler Registration ─────────────────────────────────
cat phases/phase-19b-tool-registration.md
# Verify: BUILD SUCCEEDED; 37 handlers registered
# Commit: Phase 19b

# ── PHASE 20 — ContentView + ChatView + ProviderHUD ───────────────────────
cat phases/phase-20-chatview.md
# Verify: BUILD SUCCEEDED
# Commit: Phase 20

# ── PHASE 21 — ToolLogView + ScreenPreviewView ────────────────────────────
cat phases/phase-21-secondary-views.md
# Verify: BUILD SUCCEEDED; VisualLayoutTests → testNoWidgetsClipped + testAccessibilityAudit pass
# Commit: Phase 21

# ── PHASE 22 — AuthPopupView + FirstLaunchSetup ───────────────────────────
cat phases/phase-22-authpopup.md
# Verify: BUILD SUCCEEDED
# Commit: Phase 22

# ── PHASE 23 — TestTargetApp ──────────────────────────────────────────────
cat phases/phase-23-test-fixture-app.md
# Verify: BUILD SUCCEEDED; GUIAutomationE2ETests skip without RUN_LIVE_TESTS
# Commit: Phase 23

# ── PHASE 24 — Live Tests + Final E2E ─────────────────────────────────────
cat phases/phase-24-live-e2e.md
# Verify (requires RUN_LIVE_TESTS=1 + DEEPSEEK_API_KEY):
#   DeepSeekProviderLiveTests → 3 pass
#   AgenticLoopE2ETests → 1 pass (reads real file via real API)
#   GUIAutomationE2ETests → pass (with Accessibility + LM Studio running)
# Commit: Phase 24

# ── PHASE 25a — RAG Integration Tests ────────────────────────────────────────
cat phases/phase-25a-rag-tests.md
# Verify: BUILD FAILED with errors for XcalibreClient, RAGChunk, RAGBook, RAGTools,
#         CapturingProvider (expected)
# Commit: Phase 25a

# ── PHASE 25b — RAG Integration Implementation ────────────────────────────────
cat phases/phase-25b-rag-impl.md
# Verify: TEST BUILD SUCCEEDED; XcalibreClientTests → 10 pass; RAGToolsTests → 11 pass;
#         RAGEngineTests → 3 pass
# Commit: Phase 25b

# ── PHASE 26a — Multi-Provider Tests ─────────────────────────────────────────
cat phases/phase-26a-provider-tests.md
# Verify: BUILD FAILED with errors for ProviderRegistry, OpenAICompatibleProvider,
#         AnthropicSSEParser, AnthropicMessageEncoder, AnthropicProvider,
#         AgenticEngine.shouldUseThinking(for:) (expected)
# Commit: Phase 26a

# ── PHASE 26b — Multi-Provider Implementation ─────────────────────────────────
cat phases/phase-26b-provider-impl.md
# Verify: TEST BUILD SUCCEEDED; ProviderRegistryTests → 14 pass;
#         OpenAICompatibleProviderTests → 5 pass; AnthropicSSEParserTests → 7 pass;
#         AnthropicMessageEncoderTests → 5 pass; AnthropicProviderRequestTests → 4 pass;
#         AgenticEngineProviderTests → 4 pass
# Commit: Phase 26b

# ── PHASE 27a — Model Picker Tests ───────────────────────────────────────────
cat phases/phase-27a-model-picker-tests.md
# Verify: BUILD FAILED with errors for ProviderRegistry.knownModels (expected)
# Commit: Phase 27a

# ── PHASE 27b — Model Picker Implementation ───────────────────────────────────
cat phases/phase-27b-model-picker.md
# Verify: BUILD SUCCEEDED; ProviderModelPickerTests → 8 pass
# Commit: Phase 27b

# ── PHASE 28a — Menu Tests ────────────────────────────────────────────────────
cat phases/phase-28a-menu-tests.md
# Verify: BUILD FAILED with errors for AgenticEngine.cancel(), AppState.newSession(),
#         AppState.stopEngine(), Notification.Name.merlinNewSession (expected)
# Commit: Phase 28a

# ── PHASE 28b — Menu Implementation ──────────────────────────────────────────
cat phases/phase-28b-menu.md
# Verify: BUILD SUCCEEDED; AgenticEngineCancelTests → 3 pass;
#         AppStateSessionTests → 4 pass
# Commit: Phase 28b

# ── DONE ──────────────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings
```

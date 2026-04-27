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
# Verify: BUILD SUCCEEDED; ToolDefinitions.all is non-empty
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
# Verify: BUILD SUCCEEDED; all built-in handlers registered
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

# ════════════════════════════════════════════════════════════════════════════
# VERSION 2
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 29 — ProjectRef + ProjectPickerView + WindowGroup ──────────────────
cat phases/phase-29-project-picker.md
# Verify: BUILD SUCCEEDED; project picker shown at launch; workspace window opens per project
# Commit: Phase 29

# ── PHASE 30a — SessionManager Tests ─────────────────────────────────────────
cat phases/phase-30a-session-manager-tests.md
# Verify: BUILD FAILED with errors for SessionManager, LiveSession (expected)
# Commit: Phase 30a

# ── PHASE 30b — SessionManager Implementation ─────────────────────────────────
cat phases/phase-30b-session-manager.md
# Verify: BUILD SUCCEEDED; SessionManagerTests → 8 pass
# Commit: Phase 30b

# ── PHASE 31a — Permission Mode Tests ────────────────────────────────────────
cat phases/phase-31a-permission-mode-tests.md
# Verify: BUILD FAILED with errors for PermissionMode (expected)
# Commit: Phase 31a

# ── PHASE 31b — Permission Mode Implementation ───────────────────────────────
cat phases/phase-31b-permission-mode.md
# Verify: BUILD SUCCEEDED; PermissionModeTests → 6 pass
# Commit: Phase 31b

# ── PHASE 32a — StagingBuffer Tests ──────────────────────────────────────────
cat phases/phase-32a-staging-buffer-tests.md
# Verify: BUILD FAILED with errors for StagingBuffer, StagedChange, ChangeKind (expected)
# Commit: Phase 32a

# ── PHASE 32b — StagingBuffer Implementation ─────────────────────────────────
cat phases/phase-32b-staging-buffer.md
# Verify: BUILD SUCCEEDED; StagingBufferTests → 10 pass
# Commit: Phase 32b

# ── PHASE 33a — DiffEngine Tests ─────────────────────────────────────────────
cat phases/phase-33a-diff-engine-tests.md
# Verify: BUILD FAILED with errors for DiffEngine, DiffHunk, DiffLine (expected)
# Commit: Phase 33a

# ── PHASE 33b — DiffEngine + DiffPane ────────────────────────────────────────
cat phases/phase-33b-diff-pane.md
# Verify: BUILD SUCCEEDED; DiffEngineTests → 9 pass
# Commit: Phase 33b

# ── PHASE 34 — ChatView v2 (stop button + scroll lock) ───────────────────────
cat phases/phase-34-chatview-v2.md
# Verify: BUILD SUCCEEDED; stop button appears while streaming; scroll lock banner works
# Commit: Phase 34

# ── PHASE 35a — Inline Diff Comment Tests ────────────────────────────────────
cat phases/phase-35a-diff-comment-tests.md
# Verify: BUILD FAILED with errors for DiffComment, StagingBuffer.addComment (expected)
# Commit: Phase 35a

# ── PHASE 35b — Inline Diff Commenting ───────────────────────────────────────
cat phases/phase-35b-diff-comment.md
# Verify: BUILD SUCCEEDED; DiffCommentTests → 6 pass
# Commit: Phase 35b

# ── PHASE 36a — CLAUDEMDLoader Tests ─────────────────────────────────────────
cat phases/phase-36a-claude-md-tests.md
# Verify: BUILD FAILED with errors for CLAUDEMDLoader (expected)
# Commit: Phase 36a

# ── PHASE 36b — CLAUDEMDLoader Implementation ────────────────────────────────
cat phases/phase-36b-claude-md.md
# Verify: BUILD SUCCEEDED; CLAUDEMDLoaderTests → 8 pass
# Commit: Phase 36b

# ── PHASE 37a — Context Injection Tests ──────────────────────────────────────
cat phases/phase-37a-context-injection-tests.md
# Verify: BUILD FAILED with errors for ContextInjector, AttachmentError (expected)
# Commit: Phase 37a

# ── PHASE 37b — Context Injection Implementation ─────────────────────────────
cat phases/phase-37b-context-injection.md
# Verify: BUILD SUCCEEDED; ContextInjectionTests → 8 pass
# Commit: Phase 37b

# ── PHASE 38a — SkillsRegistry Tests ─────────────────────────────────────────
cat phases/phase-38a-skills-registry-tests.md
# Verify: BUILD FAILED with errors for SkillsRegistry, Skill, SkillFrontmatter (expected)
# Commit: Phase 38a

# ── PHASE 38b — SkillsRegistry Implementation ────────────────────────────────
cat phases/phase-38b-skills-registry.md
# Verify: BUILD SUCCEEDED; SkillsRegistryTests → 10 pass
# Commit: Phase 38b

# ── PHASE 39a — Skill Invocation Tests ───────────────────────────────────────
cat phases/phase-39a-skill-invocation-tests.md
# Verify: BUILD FAILED with errors for AgenticEngine.invokeSkill (expected)
# Commit: Phase 39a

# ── PHASE 39b — Skill Invocation + Built-in Skills ───────────────────────────
cat phases/phase-39b-skill-invocation.md
# Verify: BUILD SUCCEEDED; SkillInvocationTests → 4 pass
# Commit: Phase 39b

# ── PHASE 40a — MCPBridge Tests ──────────────────────────────────────────────
cat phases/phase-40a-mcp-bridge-tests.md
# Verify: BUILD FAILED with errors for MCPConfig, MCPServerConfig, MCPBridge (expected)
# Commit: Phase 40a

# ── PHASE 40b — MCPBridge Implementation ─────────────────────────────────────
cat phases/phase-40b-mcp-bridge.md
# Verify: BUILD SUCCEEDED; MCPBridgeTests → 9 pass
# Commit: Phase 40b

# ── PHASE 41a — SchedulerEngine Tests ────────────────────────────────────────
cat phases/phase-41a-scheduler-tests.md
# Verify: BUILD FAILED with errors for SchedulerEngine, ScheduledTask, ScheduleCadence (expected)
# Commit: Phase 41a

# ── PHASE 41b — SchedulerEngine Implementation ───────────────────────────────
cat phases/phase-41b-scheduler.md
# Verify: BUILD SUCCEEDED; SchedulerEngineTests → 6 pass
# Commit: Phase 41b

# ── PHASE 42a — PRMonitor Tests ──────────────────────────────────────────────
cat phases/phase-42a-pr-monitor-tests.md
# Verify: BUILD FAILED with errors for PRMonitor, PRStatus, ChecksState (expected)
# Commit: Phase 42a

# ── PHASE 42b — PRMonitor Implementation ─────────────────────────────────────
cat phases/phase-42b-pr-monitor.md
# Verify: BUILD SUCCEEDED; PRMonitorTests → 9 pass
# Commit: Phase 42b

# ── PHASE 43a — Connectors Tests ─────────────────────────────────────────────
cat phases/phase-43a-connectors-tests.md
# Verify: BUILD FAILED with errors for ConnectorCredentials, GitHubConnector (expected)
# Commit: Phase 43a

# ── PHASE 43b — Connectors Implementation ────────────────────────────────────
cat phases/phase-43b-connectors.md
# Verify: BUILD SUCCEEDED; ConnectorCredentialsTests → 4 pass; ConnectorProtocolTests → 5 pass
# Commit: Phase 43b

# ── DONE (v2) ─────────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 3
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 44a — TOMLDecoder Tests ────────────────────────────────────────────
cat phases/phase-44a-toml-decoder-tests.md
# Verify: BUILD FAILED with errors for TOMLDecoder, TOMLValue, TOMLLexer (expected)
# Commit: Phase 44a

# ── PHASE 44b — TOMLDecoder Implementation ───────────────────────────────────
cat phases/phase-44b-toml-decoder.md
# Verify: BUILD SUCCEEDED; TOMLDecoderTests → ~25 pass
# Commit: Phase 44b

# ── PHASE 45a — ToolRegistry Tests ───────────────────────────────────────────
cat phases/phase-45a-tool-registry-tests.md
# Verify: BUILD FAILED with errors for ToolRegistry (expected)
# Commit: Phase 45a

# ── PHASE 45b — ToolRegistry Implementation ──────────────────────────────────
cat phases/phase-45b-tool-registry.md
# Verify: BUILD SUCCEEDED; ToolRegistryTests → pass; migrated off ToolDefinitions.all count
# Commit: Phase 45b

# ── PHASE 46a — AppSettings Tests ────────────────────────────────────────────
cat phases/phase-46a-appsettings-tests.md
# Verify: BUILD FAILED with errors for AppSettings, SettingsProposal (expected)
# Commit: Phase 46a

# ── PHASE 46b — AppSettings + config.toml + Settings Window + Appearance ─────
cat phases/phase-46b-appsettings.md
# Verify: BUILD SUCCEEDED; AppSettingsTests → pass; Settings window opens via Cmd+,
# Commit: Phase 46b

# ── PHASE 47a — Memories Tests ───────────────────────────────────────────────
cat phases/phase-47a-memories-tests.md
# Verify: BUILD FAILED with errors for MemoryEngine, MemoryStore (expected)
# Commit: Phase 47a

# ── PHASE 47b — AI-Generated Memories ────────────────────────────────────────
cat phases/phase-47b-memories.md
# Verify: BUILD SUCCEEDED; MemoryEngineTests → pass
# Commit: Phase 47b

# ── PHASE 48a — Hooks Tests ──────────────────────────────────────────────────
cat phases/phase-48a-hooks-tests.md
# Verify: BUILD FAILED with errors for HookEngine, HookDefinition, HookDecision (expected)
# Commit: Phase 48a

# ── PHASE 48b — Hooks Implementation ─────────────────────────────────────────
cat phases/phase-48b-hooks.md
# Verify: BUILD SUCCEEDED; HookEngineTests → pass
# Commit: Phase 48b

# ── PHASE 49a — Thread Automations Tests ─────────────────────────────────────
cat phases/phase-49a-thread-automations-tests.md
# Verify: BUILD FAILED with errors for ThreadAutomation, SchedulerEngine.resume (expected)
# Commit: Phase 49a

# ── PHASE 49b — Thread Automations ───────────────────────────────────────────
cat phases/phase-49b-thread-automations.md
# Verify: BUILD SUCCEEDED; ThreadAutomationTests → pass
# Commit: Phase 49b

# ── PHASE 50a — Web Search Tests ─────────────────────────────────────────────
cat phases/phase-50a-web-search-tests.md
# Verify: BUILD FAILED with errors for WebSearchTool, BraveSearchClient (expected)
# Commit: Phase 50a

# ── PHASE 50b — Web Search Tool ──────────────────────────────────────────────
cat phases/phase-50b-web-search.md
# Verify: BUILD SUCCEEDED; WebSearchTests → pass
# Commit: Phase 50b

# ── PHASE 51 — Reasoning Effort + Personalization + Context Usage Indicator ──
cat phases/phase-51-agent-settings.md
# Verify: BUILD SUCCEEDED; reasoning effort picker renders; standing instructions inject
# Commit: Phase 51

# ── PHASE 52 — Toolbar Actions + Notifications ───────────────────────────────
cat phases/phase-52-toolbar-notifications.md
# Verify: BUILD SUCCEEDED; toolbar actions render; notifications fire on completion
# Commit: Phase 52

# ── PHASE 53 — Floating Pop-out Window + Voice Dictation ─────────────────────
cat phases/phase-53-popout-voice.md
# Verify: BUILD SUCCEEDED; thread detaches to floating window; Ctrl+M opens voice input
# Commit: Phase 53

# ── DONE (v3) ─────────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 4
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 54a — AgentDefinition + AgentRegistry Tests ─────────────────────────
cat phases/phase-54a-agent-definition-tests.md
# Verify: BUILD FAILED (AgentDefinition, AgentRole, AgentRegistry not defined)
# Commit: Phase 54a — AgentRegistryTests (failing)

# ── PHASE 54b — AgentDefinition + AgentRegistry Implementation ────────────────
cat phases/phase-54b-agent-definition.md
# Verify: BUILD SUCCEEDED; all AgentRegistryTests pass
# Commit: Phase 54b — AgentDefinition + AgentRegistry

# ── PHASE 55a — SubagentEngine V4a Tests ──────────────────────────────────────
cat phases/phase-55a-subagent-engine-tests.md
# Verify: BUILD FAILED (SubagentEngine, SubagentEvent not defined)
# Commit: Phase 55a — SubagentEngineTests (failing)

# ── PHASE 55b — SubagentEngine V4a Implementation ─────────────────────────────
cat phases/phase-55b-subagent-engine.md
# Verify: BUILD SUCCEEDED; all SubagentEngineTests pass
# Commit: Phase 55b — SubagentEngine V4a

# ── PHASE 56 — SubagentStream UI ──────────────────────────────────────────────
cat phases/phase-56-subagent-stream-ui.md
# Verify: BUILD SUCCEEDED; all SubagentBlockViewModelTests pass
# Commit: Phase 56 — SubagentStreamUI

# ── PHASE 57a — WorktreeManager Tests ─────────────────────────────────────────
cat phases/phase-57a-worktree-manager-tests.md
# Verify: BUILD FAILED (WorktreeManager, WorktreeError not defined)
# Commit: Phase 57a — WorktreeManagerTests (failing)

# ── PHASE 57b — WorktreeManager Implementation ────────────────────────────────
cat phases/phase-57b-worktree-manager.md
# Verify: BUILD SUCCEEDED; all WorktreeManagerTests pass
# Commit: Phase 57b — WorktreeManager

# ── PHASE 58a — WorkerSubagentEngine Tests ────────────────────────────────────
cat phases/phase-58a-subagent-worker-tests.md
# Verify: BUILD FAILED (WorkerSubagentEngine not defined)
# Commit: Phase 58a — WorkerSubagentEngineTests (failing)

# ── PHASE 58b — WorkerSubagentEngine Implementation ───────────────────────────
cat phases/phase-58b-subagent-worker.md
# Verify: BUILD SUCCEEDED; all WorkerSubagentEngineTests pass
# Commit: Phase 58b — WorkerSubagentEngine V4b

# ── PHASE 59 — SubagentSidebar UI ─────────────────────────────────────────────
cat phases/phase-59-subagent-sidebar-ui.md
# Verify: BUILD SUCCEEDED; all SubagentSidebarViewModelTests pass
# Commit: Phase 59 — SubagentSidebar UI

# ── DONE (v4) ─────────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings
```

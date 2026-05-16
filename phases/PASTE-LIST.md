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

# ════════════════════════════════════════════════════════════════════════════
# VERSION 4 (continued) — Skills, Vision, Memory, Settings, Workspace, Wiring
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 60a — Skill Compaction Tests ───────────────────────────────────────
cat phases/phase-60a-skill-compaction-tests.md
# Verify: BUILD FAILED with errors for SkillCompactionEngine (expected)
# Commit: Phase 60a — SkillCompactionTests (failing)

# ── PHASE 60b — Skill Compaction Implementation ───────────────────────────────
cat phases/phase-60b-skill-compaction.md
# Verify: BUILD SUCCEEDED; SkillCompactionTests → pass
# Commit: Phase 60b — Skill Compaction

# ── PHASE 61a — Vision Attachment Tests ──────────────────────────────────────
cat phases/phase-61a-vision-attachment-tests.md
# Verify: BUILD FAILED with errors for ContextInjector vision methods (expected)
# Commit: Phase 61a — ContextInjectorVisionTests (failing)

# ── PHASE 61b — Vision Attachment Implementation ──────────────────────────────
cat phases/phase-61b-vision-attachment.md
# Verify: BUILD SUCCEEDED; ContextInjectorVisionTests → pass
# Commit: Phase 61b — Vision Attachment

# ── PHASE 62a — Memory Generation Tests ──────────────────────────────────────
cat phases/phase-62a-memory-generation-tests.md
# Verify: BUILD FAILED with errors for MemoryEngine generation methods (expected)
# Commit: Phase 62a — MemoryGenerationTests (failing)

# ── PHASE 62b — Memory Generation Implementation ─────────────────────────────
cat phases/phase-62b-memory-generation.md
# Verify: BUILD SUCCEEDED; MemoryGenerationTests → pass
# Commit: Phase 62b — Memory Generation

# ── PHASE 63a — Memory Injection Tests ───────────────────────────────────────
cat phases/phase-63a-memory-injection-tests.md
# Verify: BUILD FAILED with errors for MemoryEngine injection methods (expected)
# Commit: Phase 63a — MemoryInjectionTests (failing)

# ── PHASE 63b — Memory Injection Implementation ───────────────────────────────
cat phases/phase-63b-memory-injection.md
# Verify: BUILD SUCCEEDED; MemoryInjectionTests → pass
# Commit: Phase 63b — Memory Injection

# ── PHASE 64 — SettingsSection Enum ──────────────────────────────────────────
cat phases/phase-64-settings-section-enum.md
# Verify: BUILD SUCCEEDED; settings navigation includes all sections
# Commit: Phase 64 — SettingsSection Enum

# ── PHASE 65 — Agent Settings Section ────────────────────────────────────────
cat phases/phase-65-agent-settings.md
# Verify: BUILD SUCCEEDED; Agent settings section renders in Settings window
# Commit: Phase 65 — Agent Settings Section

# ── PHASE 66 — Memories Settings Section ─────────────────────────────────────
cat phases/phase-66-memories-settings.md
# Verify: BUILD SUCCEEDED; Memories settings section renders
# Commit: Phase 66 — Memories Settings Section

# ── PHASE 67 — MCP Settings Section ──────────────────────────────────────────
cat phases/phase-67-mcp-settings.md
# Verify: BUILD SUCCEEDED; MCP settings section renders
# Commit: Phase 67 — MCP Settings Section

# ── PHASE 68 — Skills Settings Section ───────────────────────────────────────
cat phases/phase-68-skills-settings.md
# Verify: BUILD SUCCEEDED; Skills settings section renders
# Commit: Phase 68 — Skills Settings Section

# ── PHASE 69 — Web Search Settings Section ───────────────────────────────────
cat phases/phase-69-search-settings.md
# Verify: BUILD SUCCEEDED; Web Search settings section renders
# Commit: Phase 69 — Web Search Settings Section

# ── PHASE 70 — Permissions Settings Section ──────────────────────────────────
cat phases/phase-70-permissions-settings.md
# Verify: BUILD SUCCEEDED; Permissions settings section renders
# Commit: Phase 70 — Permissions Settings Section

# ── PHASE 71 — Advanced + Connectors Settings ────────────────────────────────
cat phases/phase-71-advanced-connectors-settings.md
# Verify: BUILD SUCCEEDED; Advanced and Connectors settings sections render
# Commit: Phase 71 — Advanced + Connectors Settings

# ── PHASE 72a — WorkspaceLayoutManager Tests ─────────────────────────────────
cat phases/phase-72a-workspace-layout-tests.md
# Verify: BUILD FAILED with errors for WorkspaceLayoutManager (expected)
# Commit: Phase 72a — WorkspaceLayoutManagerTests (failing)

# ── PHASE 72b — WorkspaceLayoutManager Implementation ────────────────────────
cat phases/phase-72b-workspace-layout.md
# Verify: BUILD SUCCEEDED; WorkspaceLayoutManagerTests → pass
# Commit: Phase 72b — WorkspaceLayoutManager

# ── PHASE 73 — FilePane ───────────────────────────────────────────────────────
cat phases/phase-73-file-pane.md
# Verify: BUILD SUCCEEDED; FilePane renders inline file viewer
# Commit: Phase 73 — FilePane

# ── PHASE 74 — TerminalPane ───────────────────────────────────────────────────
cat phases/phase-74-terminal-pane.md
# Verify: BUILD SUCCEEDED; TerminalPane renders inline PTY terminal
# Commit: Phase 74 — TerminalPane

# ── PHASE 75 — PreviewPane ────────────────────────────────────────────────────
cat phases/phase-75-preview-pane.md
# Verify: BUILD SUCCEEDED; PreviewPane renders HTML/Markdown via WKWebView
# Commit: Phase 75 — PreviewPane

# ── PHASE 76 — SideChat ──────────────────────────────────────────────────────
cat phases/phase-76-side-chat.md
# Verify: BUILD SUCCEEDED; SideChat renders independent secondary chat panel
# Commit: Phase 76 — SideChat

# ── PHASE 77 — WorkspaceView Wiring ──────────────────────────────────────────
cat phases/phase-77-workspace-wiring.md
# Verify: BUILD SUCCEEDED; all panes wire into WorkspaceView with layout persistence
# Commit: Phase 77 — WorkspaceView Wiring

# ── PHASE 78 — Fix MerlinApp Settings Scene ──────────────────────────────────
cat phases/phase-78-fix-settings-scene.md
# Verify: BUILD SUCCEEDED; Settings window opens correctly from menu
# Commit: Phase 78 — Fix Settings Scene

# ── PHASE 79a — Subagent Chat Integration Tests ───────────────────────────────
cat phases/phase-79a-subagent-chat-tests.md
# Verify: BUILD FAILED with errors for subagent chat integration (expected)
# Commit: Phase 79a — SubagentChatIntegrationTests (failing)

# ── PHASE 79b — Subagent Chat Integration ────────────────────────────────────
cat phases/phase-79b-subagent-chat.md
# Verify: BUILD SUCCEEDED; SubagentChatIntegrationTests → pass
# Commit: Phase 79b — Subagent Chat Integration

# ── PHASE 80a — DisabledSkillNames Enforcement Tests ─────────────────────────
cat phases/phase-80a-disabled-skills-tests.md
# Verify: BUILD FAILED with errors for disabled skill enforcement (expected)
# Commit: Phase 80a — DisabledSkillNamesTests (failing)

# ── PHASE 80b — DisabledSkillNames Enforcement ───────────────────────────────
cat phases/phase-80b-disabled-skills.md
# Verify: BUILD SUCCEEDED; DisabledSkillNamesTests → pass
# Commit: Phase 80b — DisabledSkillNames Enforcement

# ── PHASE 81 — Scheduler Settings + Wiring ───────────────────────────────────
cat phases/phase-81-scheduler-settings.md
# Verify: BUILD SUCCEEDED; Scheduler settings section renders; SchedulerEngine wired
# Commit: Phase 81 — Scheduler Settings + Wiring

# ── PHASE 82 — ContextUsageTracker: Wire Into ProviderHUD ────────────────────
cat phases/phase-82-context-usage-indicator.md
# Verify: BUILD SUCCEEDED; context usage indicator appears in ProviderHUD
# Commit: Phase 82 — ContextUsageTracker

# ── PHASE 83 — Voice Dictation Button ────────────────────────────────────────
cat phases/phase-83-voice-dictation-button.md
# Verify: BUILD SUCCEEDED; microphone button appears in ChatView input area
# Commit: Phase 83 — Voice Dictation Button

# ── PHASE 84 — FloatingWindowManager ─────────────────────────────────────────
cat phases/phase-84-floating-window.md
# Verify: BUILD SUCCEEDED; floating window opens from menu item and keyboard shortcut
# Commit: Phase 84 — FloatingWindowManager

# ── PHASE 85 — ThreadAutomationEngine Wiring ─────────────────────────────────
cat phases/phase-85-thread-automations.md
# Verify: BUILD SUCCEEDED; ThreadAutomationEngine wired into LiveSession
# Commit: Phase 85 — ThreadAutomationEngine Wiring

# ── PHASE 86 — ToolbarActionStore Wiring ─────────────────────────────────────
cat phases/phase-86-toolbar-actions.md
# Verify: BUILD SUCCEEDED; toolbar actions render and fire from ChatView toolbar
# Commit: Phase 86 — ToolbarActionStore Wiring

# ── PHASE 87 — PRMonitor Wiring ───────────────────────────────────────────────
cat phases/phase-87-pr-monitor.md
# Verify: BUILD SUCCEEDED; PRMonitor wired into AppState
# Commit: Phase 87 — PRMonitor Wiring

# ── PHASE 88a — AppSettings Additions Tests ───────────────────────────────────
cat phases/phase-88a-appsettings-additions-tests.md
# Verify: BUILD FAILED with errors for keepAwake, permissionMode, notifications, messageDensity (expected)
# Commit: Phase 88a — AppSettingsAdditionsTests (failing)

# ── PHASE 88b — AppSettings Additions Implementation ─────────────────────────
cat phases/phase-88b-appsettings-additions.md
# Verify: BUILD SUCCEEDED; AppSettingsAdditionsTests → pass
# Commit: Phase 88b — AppSettings Additions

# ── PHASE 89 — General + Appearance Settings ─────────────────────────────────
cat phases/phase-89-settings-general-appearance.md
# Verify: BUILD SUCCEEDED; General and Appearance settings sections complete
# Commit: Phase 89 — General + Appearance Settings

# ── PHASE 90 — Advanced Settings ─────────────────────────────────────────────
cat phases/phase-90-advanced-settings.md
# Verify: BUILD SUCCEEDED; Advanced settings section complete
# Commit: Phase 90 — Advanced Settings

# ── PHASE 91 — Register Built-in Tools at Launch ─────────────────────────────
cat phases/phase-91-tool-registry-launch.md
# Verify: BUILD SUCCEEDED; all built-in tools registered via ToolRegistry at launch
# Commit: Phase 91 — Tool Registry Launch

# ── PHASE 92 — Apply messageDensity to ChatView ───────────────────────────────
cat phases/phase-92-message-density-chat.md
# Verify: BUILD SUCCEEDED; message density setting applied to ChatView rows
# Commit: Phase 92 — Message Density ChatView

# ── PHASE 93 — Keep Awake (IOPMAssertion) ────────────────────────────────────
cat phases/phase-93-keep-awake.md
# Verify: BUILD SUCCEEDED; IOPMAssertion held while keepAwake is enabled
# Commit: Phase 93 — Keep Awake

# ── PHASE 94 — Notifications Enabled Guard ───────────────────────────────────
cat phases/phase-94-notifications-enabled-guard.md
# Verify: BUILD SUCCEEDED; NotificationEngine gated on notificationsEnabled setting
# Commit: Phase 94 — Notifications Enabled Guard

# ── PHASE 95 — Default Permission Mode ───────────────────────────────────────
cat phases/phase-95-default-permission-mode.md
# Verify: BUILD SUCCEEDED; defaultPermissionMode applied to new sessions
# Commit: Phase 95 — Default Permission Mode

# ── PHASE 96 — AgentRegistry Launch Registration ─────────────────────────────
cat phases/phase-96-agent-registry-launch.md
# Verify: BUILD SUCCEEDED; AgentRegistry.registerBuiltins() called at launch
# Commit: Phase 96 — AgentRegistry Launch

# ── PHASE 97 — HookEngine Main Loop Wiring ───────────────────────────────────
cat phases/phase-97-hook-engine-main-loop.md
# Verify: BUILD SUCCEEDED; HookEngine wired into AgenticEngine main loop
# Commit: Phase 97 — HookEngine Main Loop Wiring

# ── PHASE 98 — Apply AppTheme + Font Settings to UI ──────────────────────────
cat phases/phase-98-appearance-application.md
# Verify: BUILD SUCCEEDED; AppTheme and font settings applied throughout UI
# Commit: Phase 98 — Appearance Application

# ── DONE (v4 complete) ────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 5 — Supervisor-Worker Multi-LLM + Domain Plugin System
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 99a — DomainRegistry + DomainPlugin Tests ───────────────────────────
cat phases/phase-99a-domain-registry-tests.md
# Verify: BUILD FAILED — DomainRegistry, DomainPlugin, DomainTaskType, DomainManifest, MCPDomainAdapter not defined (expected)
# Commit: Phase 99a — DomainRegistryTests + DomainManifestTests (failing)

# ── PHASE 99b — DomainRegistry + DomainPlugin + MCPDomainAdapter + SoftwareDomain ──
cat phases/phase-99b-domain-registry.md
# Verify: BUILD SUCCEEDED; DomainRegistryTests → 5 pass; DomainManifestTests → 2 pass
# Commit: Phase 99b — DomainRegistry + DomainPlugin + MCPDomainAdapter + SoftwareDomain

# ── PHASE 100a — AgenticEngine Role Slot Routing Tests ────────────────────────
cat phases/phase-100a-role-slot-routing-tests.md
# Verify: BUILD FAILED — AgentSlot, AgenticEngine slot init not defined (expected)
# Commit: Phase 100a — AgenticEngineSlotTests (failing)

# ── PHASE 100b — AgenticEngine Role Slot Routing ──────────────────────────────
cat phases/phase-100b-role-slot-routing.md
# Verify: BUILD SUCCEEDED; AgenticEngineSlotTests → 7 pass; zero warnings
# Commit: Phase 100b — AgenticEngine role slot routing (execute/reason/orchestrate/vision)

# ── PHASE 101a — ModelPerformanceTracker Tests ────────────────────────────────
cat phases/phase-101a-performance-tracker-tests.md
# Verify: BUILD FAILED — OutcomeSignals, ModelPerformanceTracker not defined (expected)
# Commit: Phase 101a — ModelPerformanceTrackerTests (failing)

# ── PHASE 101b — ModelPerformanceTracker ──────────────────────────────────────
cat phases/phase-101b-performance-tracker.md
# Verify: BUILD SUCCEEDED; ModelPerformanceTrackerTests → 6 pass; zero warnings
# Commit: Phase 101b — ModelPerformanceTracker

# ── PHASE 102a — CriticEngine Tests ───────────────────────────────────────────
cat phases/phase-102a-critic-engine-tests.md
# Verify: BUILD FAILED — CriticResult, CriticEngine, ShellRunning not defined (expected)
# Commit: Phase 102a — CriticEngineTests (failing)

# ── PHASE 102b — CriticEngine (Stage 1 + Stage 2) ────────────────────────────
cat phases/phase-102b-critic-engine.md
# Verify: BUILD SUCCEEDED; CriticEngineTests → 5 pass; zero warnings
# Commit: Phase 102b — CriticEngine (Stage 1 domain verification + Stage 2 reason slot)

# ── PHASE 103a — PlannerEngine Tests ──────────────────────────────────────────
cat phases/phase-103a-planner-tests.md
# Verify: BUILD FAILED — ComplexityTier, ClassifierResult, PlannerEngine, PlanStep not defined (expected)
# Commit: Phase 103a — PlannerEngineTests (failing)

# ── PHASE 103b — PlannerEngine ────────────────────────────────────────────────
cat phases/phase-103b-planner-engine.md
# Verify: BUILD SUCCEEDED; PlannerEngineTests → 7 pass; zero warnings
# Commit: Phase 103b — PlannerEngine

# ── PHASE 104a — System Prompt Addendum Tests ─────────────────────────────────
cat phases/phase-104a-system-prompt-addendum-tests.md
# Verify: BUILD FAILED — ProviderConfig.systemPromptAddendum, String.addendumHash, buildSystemPromptForTesting not defined (expected)
# Commit: Phase 104a — SystemPromptAddendumTests (failing)

# ── PHASE 104b — System Prompt Addendum ───────────────────────────────────────
cat phases/phase-104b-system-prompt-addendum.md
# Verify: BUILD SUCCEEDED; SystemPromptAddendumTests → 7 pass; all prior tests pass
# Commit: Phase 104b — system_prompt_addendum injection

# ── PHASE 105a — V5 AgenticEngine Run Loop Tests ──────────────────────────────
cat phases/phase-105a-v5-runloop-tests.md
# Verify: BUILD FAILED — protocols and engine test hooks not defined (expected)
# Commit: Phase 105a — AgenticEngineV5Tests (failing)

# ── PHASE 105b — V5 AgenticEngine Run Loop ────────────────────────────────────
cat phases/phase-105b-v5-runloop.md
# Verify: BUILD SUCCEEDED; AgenticEngineV5Tests → 6 pass; all prior tests pass
# Commit: Phase 105b — V5 AgenticEngine run loop (planner + critic + tracker + memory write)

# ── PHASE 106a — V5 Settings UI Tests ────────────────────────────────────────
cat phases/phase-106a-v5-settings-ui-tests.md
# Verify: BUILD FAILED — RoleSlotSettingsView, PerformanceDashboardView, AppSettings new properties not defined (expected)
# Commit: Phase 106a — V5SettingsUITests (failing)

# ── PHASE 106b — V5 Settings UI ──────────────────────────────────────────────
cat phases/phase-106b-v5-settings-ui.md
# Verify: BUILD SUCCEEDED; V5SettingsUITests → all pass; Settings UI renders
# Commit: Phase 106b — V5 Settings UI (role slot assignment + domain selector + performance dashboard)

# ── PHASE 107a — V5 Skill Frontmatter Tests ───────────────────────────────────
cat phases/phase-107a-skill-frontmatter-v5-tests.md
# Verify: BUILD FAILED — SkillFrontmatter.role, SkillFrontmatter.complexity not defined (expected)
# Commit: Phase 107a — SkillFrontmatterV5Tests (failing)

# ── PHASE 107b — V5 Skill Frontmatter ─────────────────────────────────────────
cat phases/phase-107b-skill-frontmatter-v5.md
# Verify: BUILD SUCCEEDED; SkillFrontmatterV5Tests → 6 pass; zero warnings
# Commit: Phase 107b — Skill frontmatter role: and complexity: declarations

# ── DONE (v5 core) ────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# VERSION 5 — RAG Memory Extension
# ════════════════════════════════════════════════════════════════════════════
# Prereq: xcalibre Phase 18 shipped (POST /api/v1/memory, GET /api/v1/search/chunks?source=all)

# ── PHASE 108a — RAG Source Attribution Tests ─────────────────────────────────
cat phases/phase-108a-rag-source-attribution-tests.md
# Verify: BUILD FAILED — AgentEvent.ragSources not defined; RAGSourcesView not defined (expected)
# Commit: Phase 108a — RAGSourceAttributionTests (failing)

# ── PHASE 108b — RAG Source Attribution ───────────────────────────────────────
cat phases/phase-108b-rag-source-attribution.md
# Verify: BUILD SUCCEEDED; RAGSourceAttributionTests → 4 pass; all prior tests pass
# Commit: Phase 108b — RAG source attribution (.ragSources event + Sources footer in chat)

# ── PHASE 109a — Project Path AppSettings Tests ───────────────────────────────
cat phases/phase-109a-project-path-tests.md
# Verify: BUILD FAILED — AppSettings.projectPath not defined; serializedTOML/applyTOML mismatch (expected)
# Commit: Phase 109a — ProjectPathSettingsTests (failing)

# ── PHASE 109b — Project Path AppSettings Wiring ──────────────────────────────
cat phases/phase-109b-project-path.md
# Verify: BUILD SUCCEEDED; ProjectPathSettingsTests → all pass; all prior tests pass
# Commit: Phase 109b — AppSettings.projectPath wired into engine and Settings UI

# ── PHASE 110a — Memory Browser Tests ─────────────────────────────────────────
cat phases/phase-110a-memory-browser-tests.md
# Verify: BUILD FAILED — XcalibreClient.searchMemory not defined; MemoryBrowserView not defined (expected)
# Commit: Phase 110a — MemoryBrowserTests (failing)

# ── PHASE 110b — Memory Browser ───────────────────────────────────────────────
cat phases/phase-110b-memory-browser.md
# Verify: BUILD SUCCEEDED; MemoryBrowserTests → 5 pass; all prior tests pass
# Commit: Phase 110b — Memory browser (searchMemory convenience + MemoryBrowserView)

# ── PHASE 111a — rag_search Tool Source/ProjectPath Tests ─────────────────────
cat phases/phase-111a-rag-search-tool-tests.md
# Verify: BUILD FAILED — RAGTools.search signature mismatch; Args.source not defined (expected)
# Commit: Phase 111a — RAGSearchToolTests (failing)

# ── PHASE 111b — rag_search Tool Source/ProjectPath ───────────────────────────
cat phases/phase-111b-rag-search-tool.md
# Verify: BUILD SUCCEEDED; RAGSearchToolTests → 6 pass; all prior tests pass
# Commit: Phase 111b — rag_search tool: source + project_path parameters

# ── PHASE 112a — RAG Settings Tests ──────────────────────────────────────────
cat phases/phase-112a-rag-settings-tests.md
# Verify: BUILD FAILED — AppSettings.ragRerank, AppSettings.ragChunkLimit not defined (expected)
# Commit: Phase 112a — RAGSettingsTests (failing)

# ── PHASE 112b — RAG Settings ─────────────────────────────────────────────────
cat phases/phase-112b-rag-settings.md
# Verify: BUILD SUCCEEDED; RAGSettingsTests → all pass; all prior tests pass
# Commit: Phase 112b — ragRerank + ragChunkLimit configurable (default off, safe for RTX 2070)

# ── DONE (v5 RAG memory extension) ────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass; zero warnings
#
# Hardware upgrade path (RTX 5080 + Mistral-7B):
#   xcalibre config.toml: [llm.librarian] model = "mistral-7b-instruct-q4_k_m"
#   ~/.merlin/config.toml: rag_rerank = true / rag_chunk_limit = 10
#   No code changes required.
#
# V6 LoRA Self-Training — deferred pending hardware upgrade.

# ════════════════════════════════════════════════════════════════════════════
# VERSION 5 — V5 Loose Ends (performance data integrity)
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 113a — OutcomeRecord Persistence Tests ──────────────────────────────
cat phases/phase-113a-outcome-record-persistence-tests.md
# Verify: BUILD FAILED — ModelPerformanceTracker.records(for:taskType:) and
#         ModelPerformanceTracker.exportTrainingData(minScore:) not defined (expected)
# Commit: Phase 113a — OutcomeRecordPersistenceTests (failing)

# ── PHASE 113b — OutcomeRecord Persistence ────────────────────────────────────
cat phases/phase-113b-outcome-record-persistence.md
# Verify: BUILD SUCCEEDED; OutcomeRecordPersistenceTests → 6 pass; all prior tests pass
# Commit: Phase 113b — OutcomeRecord persistence (V6 training data survives restarts)

# ── PHASE 114a — StagingBuffer OutcomeSignals Tests ───────────────────────────
cat phases/phase-114a-staging-buffer-signals-tests.md
# Verify: BUILD FAILED — StagingBuffer.acceptedCount, rejectedCount,
#         editedOnAcceptCount, resetSessionCounts() not defined (expected)
# Commit: Phase 114a — StagingBufferSignalsTests (failing)

# ── PHASE 114b — StagingBuffer OutcomeSignals Wiring ──────────────────────────
cat phases/phase-114b-staging-buffer-signals.md
# Verify: BUILD SUCCEEDED; StagingBufferSignalsTests → 9 pass; all prior tests pass
# Commit: Phase 114b — StagingBuffer accept/reject wired into OutcomeSignals

# ── PHASE 115a — Critic-Gated Memory Tests ────────────────────────────────────
cat phases/phase-115a-critic-gated-memory-tests.md
# Verify: BUILD FAILED — AgenticEngine.lastCriticVerdict not defined (expected)
# Commit: Phase 115a — CriticGatedMemoryTests (failing)

# ── PHASE 115b — Critic-Gated Memory Write ────────────────────────────────────
cat phases/phase-115b-critic-gated-memory.md
# Verify: BUILD SUCCEEDED; CriticGatedMemoryTests → 7 pass; all prior tests pass
# Commit: Phase 115b — critic-gated memory write (suppress xcalibre write on critic .fail)

# ── DONE (v5 loose ends) ──────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass; zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 6 — LoRA Self-Training (MLX-LM on M4 Mac)
# ════════════════════════════════════════════════════════════════════════════
# Hardware: M4 Mac 128 GB unified memory (already present)
# Prereq: python -m mlx_lm installed; base model downloaded via mlx_lm
# All features default-off (loraEnabled = false). App builds and ships cleanly
# with everything disabled.

# ── PHASE 116a — LoRA AppSettings Tests ──────────────────────────────────────
cat phases/phase-116a-lora-appsettings-tests.md
# Verify: BUILD FAILED — AppSettings.loraEnabled (and 6 other properties) not defined (expected)
# Commit: Phase 116a — LoRASettingsTests (failing)

# ── PHASE 116b — LoRA AppSettings ────────────────────────────────────────────
cat phases/phase-116b-lora-appsettings.md
# Verify: BUILD SUCCEEDED; LoRASettingsTests → 10 pass; all prior tests pass
# Commit: Phase 116b — LoRA AppSettings (loraEnabled + 6 sub-settings, [lora] TOML section)

# ── PHASE 117a — OutcomeRecord Training Fields Tests ─────────────────────────
cat phases/phase-117a-outcome-record-training-fields-tests.md
# Verify: BUILD FAILED — OutcomeRecord.prompt, OutcomeRecord.response not defined (expected)
# Commit: Phase 117a — OutcomeRecordTrainingFieldsTests (failing)

# ── PHASE 117b — OutcomeRecord Training Fields ────────────────────────────────
cat phases/phase-117b-outcome-record-training-fields.md
# Verify: BUILD SUCCEEDED; OutcomeRecordTrainingFieldsTests → 6 pass; all prior tests pass
# Commit: Phase 117b — OutcomeRecord prompt/response fields; record() captures conversation text

# ── PHASE 118a — LoRATrainer Tests ───────────────────────────────────────────
cat phases/phase-118a-lora-trainer-tests.md
# Verify: BUILD FAILED — LoRATrainer, LoRATrainingResult, ShellRunnerProtocol not defined (expected)
# Commit: Phase 118a — LoRATrainerTests (failing)

# ── PHASE 118b — LoRATrainer ──────────────────────────────────────────────────
cat phases/phase-118b-lora-trainer.md
# Verify: BUILD SUCCEEDED; LoRATrainerTests → 5 pass; all prior tests pass
# Commit: Phase 118b — LoRATrainer (JSONL export + mlx_lm.lora shell invocation)

# ── PHASE 119a — LoRACoordinator Tests ───────────────────────────────────────
cat phases/phase-119a-lora-coordinator-tests.md
# Verify: BUILD FAILED — LoRACoordinator not defined (expected)
# Commit: Phase 119a — LoRACoordinatorTests (failing)

# ── PHASE 119b — LoRACoordinator ─────────────────────────────────────────────
cat phases/phase-119b-lora-coordinator.md
# Verify: BUILD SUCCEEDED; LoRACoordinatorTests → 4 pass; all prior tests pass
# Commit: Phase 119b — LoRACoordinator (threshold-gated auto-train trigger, concurrent-safe)

# ── PHASE 120a — LoRA Provider Routing Tests ─────────────────────────────────
cat phases/phase-120a-lora-provider-routing-tests.md
# Verify: BUILD FAILED — AgenticEngine.loraProvider not defined (expected)
# Commit: Phase 120a — LoRAProviderRoutingTests (failing)

# ── PHASE 120b — LoRA Provider Routing ───────────────────────────────────────
cat phases/phase-120b-lora-provider-routing.md
# Verify: BUILD SUCCEEDED; LoRAProviderRoutingTests → 4 pass; all prior tests pass
# Commit: Phase 120b — LoRA provider routing (execute slot → mlx_lm.server when adapter loaded)

# ── PHASE 121a — LoRA Settings UI Tests ──────────────────────────────────────
cat phases/phase-121a-lora-settings-ui-tests.md
# Verify: BUILD FAILED — LoRASettingsSection not defined (expected)
# Commit: Phase 121a — LoRASettingsUITests (failing)

# ── PHASE 121b — LoRA Settings UI ────────────────────────────────────────────
cat phases/phase-121b-lora-settings-ui.md
# Verify: BUILD SUCCEEDED; LoRASettingsUITests → 4 pass; all prior tests pass
# Commit: Phase 121b — LoRA Settings UI (master toggle + training config + status row)

# ── DONE (v6 LoRA self-training) ──────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass; zero warnings
#
# To activate after model download:
#   1. pip install mlx-lm
#   2. python -m mlx_lm.convert --hf-path <model> --mlx-path ~/.merlin/lora/base
#   3. Open Settings → LoRA; enable, set base model path and adapter path
#   4. Run sessions until sample count reaches loraMinSamples
#   5. Training fires automatically (or tap Train Now)
#   6. Start server: python -m mlx_lm.server --model <base> --adapter-path <adapter> --port 8080
#   7. Enable Auto-load adapter; set server URL to http://localhost:8080

# ── V6 LOOSE END — Memory → xcalibre RAG indexing ────────────────────────────
# Accepted AI-generated memories now also write to xcalibre-server as factual RAG
# chunks, so they surface via semantic search rather than always being injected verbatim.

# ── V7 Inference Parameter Expansion ─────────────────────────────────────────
# Expands CompletionRequest with all llama.cpp/LM Studio sampling params,
# adds AppSettings inference defaults, and introduces ModelParameterAdvisor
# for automatic detection of bad settings from observed model behaviour.

# ── PHASE 123a — Sampling Params Tests ───────────────────────────────────────
cat phases/phase-123a-sampling-params-tests.md
# Verify: BUILD FAILED — CompletionRequest.topK etc. not defined (expected)
# Commit: Phase 123a — CompletionRequestSamplingParamsTests (failing)

# ── PHASE 123b — Sampling Params Implementation ───────────────────────────────
cat phases/phase-123b-sampling-params.md
# Verify: BUILD SUCCEEDED; CompletionRequestSamplingParamsTests → 13 pass; all prior tests pass
# Commit: Phase 123b — expand CompletionRequest with 8 sampling params; AppSettings inference defaults

# ── PHASE 124a — ModelParameterAdvisor Tests ─────────────────────────────────
cat phases/phase-124a-parameter-advisor-tests.md
# Verify: BUILD FAILED — ModelParameterAdvisor, ParameterAdvisory not defined (expected)
# Commit: Phase 124a — ModelParameterAdvisorTests (failing)

# ── PHASE 124b — ModelParameterAdvisor Implementation ────────────────────────
cat phases/phase-124b-parameter-advisor.md
# Verify: BUILD SUCCEEDED; ModelParameterAdvisorTests → 12 pass; all prior tests pass
# Commit: Phase 124b — ModelParameterAdvisor (truncation, variance, repetition, context overflow)

# ── V6 LOOSE END — Memory → xcalibre RAG indexing ────────────────────────────
# ── PHASE 122a — Memory Xcalibre Index Tests ─────────────────────────────────
cat phases/phase-122a-memory-xcalibre-index-tests.md
# Verify: BUILD FAILED — MemoryEngine has no setXcalibreClient method (expected)
# Commit: Phase 122a — MemoryXcalibreIndexTests (failing)

# ── PHASE 122b — Memory Xcalibre Index ───────────────────────────────────────
cat phases/phase-122b-memory-xcalibre-index.md
# Verify: BUILD SUCCEEDED; MemoryXcalibreIndexTests → 6 pass; all prior tests pass
# Commit: Phase 122b — approved memories indexed in xcalibre-server as factual RAG chunks

# ── V7 Local Model Management ─────────────────────────────────────────────────
# Unified LocalModelManagerProtocol across all 6 local providers (LM Studio, Ollama,
# Jan, LocalAI, Mistral.rs, vLLM). Runtime reload where supported; restart instructions
# where not. AppState registry + ApplyAdvisory routing. ModelControlView UI.

# ── PHASE 125a — LocalModelManagerProtocol Tests ─────────────────────────────
cat phases/phase-125a-local-model-manager-protocol-tests.md
# Verify: BUILD FAILED — LocalModelManagerProtocol, LoadParam, LocalModelConfig etc. not defined (expected)
# Commit: Phase 125a — LocalModelManagerProtocolTests (failing)

# ── PHASE 125b — LocalModelManagerProtocol + LMStudio + Ollama ───────────────
cat phases/phase-125b-local-model-manager-protocol.md
# Verify: BUILD SUCCEEDED; LocalModelManagerProtocolTests → 22 pass; all prior tests pass
# Commit: Phase 125b — LocalModelManagerProtocol + LMStudioModelManager + OllamaModelManager

# ── PHASE 126a — Extended Provider Manager Tests ─────────────────────────────
cat phases/phase-126a-local-model-manager-extended-tests.md
# Verify: BUILD FAILED — JanModelManager, LocalAIModelManager, MistralRSModelManager, VLLMModelManager not defined (expected)
# Commit: Phase 126a — LocalModelManagerExtendedTests (failing)

# ── PHASE 126b — Jan, LocalAI, MistralRS, vLLM Managers ─────────────────────
cat phases/phase-126b-local-model-manager-extended.md
# Verify: BUILD SUCCEEDED; LocalModelManagerExtendedTests → 20 pass; all prior tests pass
# Commit: Phase 126b — Jan/LocalAI/MistralRS/vLLM model managers

# ── PHASE 127a — Model Manager Wiring Tests ──────────────────────────────────
cat phases/phase-127a-model-manager-wiring-tests.md
# Verify: BUILD FAILED — AppState.localModelManagers, applyAdvisory, AgenticEngine.isReloadingModel not defined (expected)
# Commit: Phase 127a — ModelManagerWiringTests (failing)

# ── PHASE 127b — Model Manager Wiring ────────────────────────────────────────
cat phases/phase-127b-model-manager-wiring.md
# Verify: BUILD SUCCEEDED; ModelManagerWiringTests → 9 pass; all prior tests pass
# Commit: Phase 127b — model manager wiring: AppState registry, applyAdvisory, engine reload pause

# ── PHASE 128a — Model Control UI Tests ──────────────────────────────────────
cat phases/phase-128a-model-control-ui-tests.md
# Verify: BUILD FAILED — ModelControlView, RestartInstructionsSheet, ModelControlSectionView not defined (expected)
# Commit: Phase 128a — ModelControlViewTests (failing)

# ── PHASE 128b — Model Control UI ────────────────────────────────────────────
cat phases/phase-128b-model-control-ui.md
# Verify: BUILD SUCCEEDED; ModelControlViewTests → 6 pass; all prior tests pass
# Commit: Phase 128b — ModelControlView: per-provider load param editor + restart instructions sheet

# ── PHASE 132 — V7 Documentation & Code Comment Update ───────────────────────
cat phases/phase-132-v7-docs.md
# Verify: BUILD SUCCEEDED; zero warnings; all prior tests pass
# Commit: Phase 132 — V7 docs + code comments: inference params, ModelParameterAdvisor, LocalModelManagerProtocol, ModelControlView

# ── DONE (v7 Local Model Management) ─────────────────────────────────────────
# All 6 local providers unified under LocalModelManagerProtocol.
# AppState registry routes advisories to manager.reload() or surfaces restart instructions.
# ModelControlView shows editable load params per provider in Settings → Providers.
# AgenticEngine pauses run loop during reload to prevent mid-generation context mutations.

# ── V8 /calibrate — Cross-Provider Model Calibration ─────────────────────────
# /calibrate fires an 18-prompt battery against the active local model and a chosen
# reference provider (Anthropic, OpenAI, DeepSeek, etc.) in parallel, critic-scores
# all responses, and maps gaps to ParameterAdvisory items (context length, temperature,
# max tokens, repeat penalty) that flow into the existing applyAdvisory() pipeline.

# ── PHASE 129a — CalibrationRunner Tests ─────────────────────────────────────
cat phases/phase-129a-calibration-runner-tests.md
# Verify: BUILD FAILED — CalibrationCategory, CalibrationPrompt, CalibrationResponse,
#         CalibrationReport, CalibrationSuite, CalibrationRunner not defined (expected)
# Commit: Phase 129a — CalibrationRunnerTests (failing)

# ── PHASE 129b — CalibrationRunner Implementation ────────────────────────────
cat phases/phase-129b-calibration-runner.md
# Verify: BUILD SUCCEEDED; CalibrationRunnerTests → 14 pass; all prior tests pass
# Commit: Phase 129b — CalibrationTypes + CalibrationSuite (18-prompt battery) + CalibrationRunner

# ── PHASE 130a — CalibrationAdvisor Tests ────────────────────────────────────
cat phases/phase-130a-calibration-advisor-tests.md
# Verify: BUILD FAILED — CalibrationAdvisor, CategoryScores not defined (expected)
# Commit: Phase 130a — CalibrationAdvisorTests (failing)

# ── PHASE 130b — CalibrationAdvisor Implementation ───────────────────────────
cat phases/phase-130b-calibration-advisor.md
# Verify: BUILD SUCCEEDED; CalibrationAdvisorTests → 14 pass; all prior tests pass
# Commit: Phase 130b — CalibrationAdvisor: maps score gaps to ParameterAdvisory

# ── PHASE 131a — Calibration Skill & UI Tests ────────────────────────────────
cat phases/phase-131a-calibration-skill-tests.md
# Verify: BUILD FAILED — CalibrationCoordinator, CalibrationSheet, CalibrationProgressInfo,
#         CalibrationProviderPickerView, CalibrationProgressView, CalibrationReportView,
#         AppState.calibrationCoordinator not defined (expected)
# Commit: Phase 131a — CalibrationSkillTests (failing)

# ── PHASE 131b — Calibration Skill & UI Implementation ───────────────────────
cat phases/phase-131b-calibration-skill.md
# Verify: BUILD SUCCEEDED; CalibrationSkillTests → 9 pass; all prior tests pass
# Commit: Phase 131b — /calibrate skill: provider picker, runner wiring, report view with apply-all

# ── PHASE 133 — V8 Documentation & Code Comment Update ───────────────────────
cat phases/phase-133-v8-docs.md
# Verify: BUILD SUCCEEDED; zero warnings; all prior tests pass
# Commit: Phase 133 — V8 docs + code comments: CalibrationSuite, CalibrationRunner, CalibrationAdvisor, CalibrationCoordinator, report views

# ── DONE (v8 /calibrate) ──────────────────────────────────────────────────────
# To use: type /calibrate in the chat bar; pick a reference provider; tap Start.
# Results show overall score gap, per-category breakdown, and one-tap parameter fixes.
# All fixes route through applyAdvisory() — runtime reload where supported, restart
# instructions where not (same path as ModelControlView and PerformanceDashboard).

# ── V9 Local Memory Store — MemoryBackendPlugin system ───────────────────────
# Replaces xcalibre-server as the memory write target. Merlin now stores approved
# memories and episodic session summaries in a local SQLite database using
# NLContextualEmbedding (macOS 14+, 512-dim, on-device, no external deps).
# xcalibre-server is retained for optional book-content RAG search only.
# Memory backend is a pluggable actor protocol — "local-vector" is the default;
# "null" disables persistence. Active plugin is persisted in AppSettings (config.toml).

# ── PHASE 134a — MemoryBackendPlugin Protocol Tests ──────────────────────────
Read phases/phase-134a-memory-backend-plugin-tests.md and execute.
# Verify: BUILD FAILED — MemoryChunk, MemorySearchResult, MemoryBackendPlugin,
#         MemoryBackendRegistry, NullMemoryPlugin not defined (expected)
# Commit: Phase 134a — MemoryBackendPlugin tests (failing)

# ── PHASE 134b — MemoryBackendPlugin Protocol Implementation ─────────────────
Read phases/phase-134b-memory-backend-plugin.md and execute.
# Verify: BUILD SUCCEEDED; all 134a tests pass; zero warnings
# Commit: Phase 134b — MemoryBackendPlugin: protocol, registry, NullMemoryPlugin

# ── PHASE 135a — LocalVectorPlugin Tests ─────────────────────────────────────
Read phases/phase-135a-local-vector-plugin-tests.md and execute.
# Verify: BUILD FAILED — EmbeddingProviderProtocol, LocalVectorPlugin not defined (expected)
# Commit: Phase 135a — LocalVectorPlugin tests (failing)

# ── PHASE 135b — LocalVectorPlugin Implementation ────────────────────────────
Read phases/phase-135b-local-vector-plugin.md and execute.
# Verify: BUILD SUCCEEDED; all 135a tests pass; zero warnings
# Commit: Phase 135b — LocalVectorPlugin: SQLite + NLContextualEmbedding cosine search

# ── PHASE 136a — MemoryEngine Backend Wiring Tests ───────────────────────────
Read phases/phase-136a-memory-engine-backend-wiring-tests.md and execute.
# Verify: BUILD FAILED — MemoryEngine.setMemoryBackend not defined (expected)
# Commit: Phase 136a — MemoryEngine backend wiring tests (failing)

# ── PHASE 136b — MemoryEngine Backend Wiring ─────────────────────────────────
Read phases/phase-136b-memory-engine-backend-wiring.md and execute.
# Verify: BUILD SUCCEEDED; all 136a tests pass; zero warnings
# Commit: Phase 136b — MemoryEngine: replace xcalibre write with MemoryBackendPlugin

# ── PHASE 137a — AgenticEngine Memory Plugin Tests ───────────────────────────
Read phases/phase-137a-agenticengine-memory-plugin-tests.md and execute.
# Verify: BUILD FAILED — AgenticEngine.setMemoryBackend not defined (expected)
# Commit: Phase 137a — AgenticEngine memory plugin tests (failing)

# ── PHASE 137b — AgenticEngine Memory Plugin Wiring ──────────────────────────
Read phases/phase-137b-agenticengine-memory-plugin.md and execute.
# Verify: BUILD SUCCEEDED; all 137a tests pass; zero warnings
# Commit: Phase 137b — AgenticEngine: local memory plugin for writes + merged RAG search

# ── PHASE 138a — Memory Backend AppSettings Wiring Tests ─────────────────────
Read phases/phase-138a-memory-backend-appsettings-tests.md and execute.
# Verify: BUILD FAILED — AppSettings.memoryBackendID, AppState.memoryRegistry not defined (expected)
# Commit: Phase 138a — memory backend AppSettings wiring tests (failing)

# ── PHASE 138b — Memory Backend AppSettings Wiring ───────────────────────────
Read phases/phase-138b-memory-backend-appsettings.md and execute.
# Verify: BUILD SUCCEEDED; all 138a tests pass; zero warnings
# Commit: Phase 138b — AppSettings.memoryBackendID + AppState memory registry wiring

# ── PHASE 139 — V9 Documentation & Code Comment Update ───────────────────────
Read phases/phase-139-v9-docs.md and execute.
# Verify: BUILD SUCCEEDED; zero warnings; all prior tests pass
# Commit: Phase 139 — V9 docs + code comments: local memory store plugin system

# ── PHASE 140a — Circuit Breaker Tests ───────────────────────────────────────
Read phases/phase-140a-circuit-breaker-tests.md and execute.
# Verify: BUILD FAILED — AgenticEngine.consecutiveCriticFailures,
#         AppSettings.agentCircuitBreakerThreshold not defined (expected)
# Commit: Phase 140a — circuit breaker tests (failing)

# ── PHASE 140b — Circuit Breaker Implementation ───────────────────────────────
Read phases/phase-140b-circuit-breaker.md and execute.
# Verify: BUILD SUCCEEDED; all 140a tests pass; zero warnings
# Commit: Phase 140b — reasoning-layer circuit breaker: warn after N consecutive critic failures

# ── PHASE 141a — Grounding Confidence Tests ──────────────────────────────────
Read phases/phase-141a-grounding-confidence-tests.md and execute.
# Verify: BUILD FAILED — GroundingReport, AgentEvent.groundingReport,
#         AppSettings.ragFreshnessThresholdDays, AppSettings.ragMinGroundingScore not defined (expected)
# Commit: Phase 141a — grounding confidence signal tests (failing)

# ── PHASE 141b — Grounding Confidence Implementation ─────────────────────────
Read phases/phase-141b-grounding-confidence.md and execute.
# Verify: BUILD SUCCEEDED; all 141a tests pass; zero warnings
# Commit: Phase 141b — GroundingReport: per-turn grounding confidence signal

# ── PHASE 142a — Semantic Fault Injection Tests ──────────────────────────────
Read phases/phase-142a-semantic-fault-injection-tests.md and execute.
# Verify: BUILD FAILED — StalenessInjectingMemoryBackend, TruncatingMockProvider,
#         EmptyToolResultRouter, DroppingContextManager not defined (expected)
# Commit: Phase 142a — semantic fault injection tests (failing)

# ── PHASE 142b — Semantic Fault Injection Implementation ─────────────────────
Read phases/phase-142b-semantic-fault-injection.md and execute.
# Verify: BUILD SUCCEEDED; all 142a tests pass; zero warnings
# Commit: Phase 142b — semantic fault injection test doubles: stale retrieval, truncation, empty tools, context drop

# ── DONE (v9 Local Memory Store) ──────────────────────────────────────────────
# Memory is fully local: SQLite at ~/.merlin/memory.sqlite, embedded with Apple
# NLContextualEmbedding, retrieved by cosine similarity. xcalibre-server is now
# optional book-content only. Backend is swappable via Settings → Memory.
#
# Behavioral reliability (v9 additions, phases 140–142):
# - Circuit breaker (phase 140): halt/warn after N consecutive critic failures
# - Grounding confidence signal (phase 141): GroundingReport per turn
# - Semantic fault injection (phase 142): test doubles for stale retrieval,
#   token pressure, empty tool results, context drop
# All four mitigations from "Context Decay, Orchestration Drift, and the Rise of
# Silent Failures in AI Systems" (VentureBeat, 2025) are implemented and documented.

# ── PHASE 143a — Dynamic Model Fetch Tests ───────────────────────────────────
Read phases/phase-143a-dynamic-model-fetch-tests.md and execute.
# Verify: BUILD FAILED — dynamic model fetch symbols not defined (expected)
# Commit: Phase 143a — dynamic model fetch tests (failing)

# ── PHASE 143b — Dynamic Model Fetch ─────────────────────────────────────────
Read phases/phase-143b-dynamic-model-fetch.md and execute.
# Verify: BUILD SUCCEEDED; all 143a tests pass; zero warnings
# Commit: Phase 143b — Dynamic model fetch

# ── PHASE 144a — Virtual Provider ID Tests ───────────────────────────────────
Read phases/phase-144a-virtual-provider-id-tests.md and execute.
# Verify: BUILD FAILED — VirtualProviderID symbols not defined (expected)
# Commit: Phase 144a — virtual provider ID tests (failing)

# ── PHASE 144b — Virtual Provider IDs ────────────────────────────────────────
Read phases/phase-144b-virtual-provider-id.md and execute.
# Verify: BUILD SUCCEEDED; all 144a tests pass; zero warnings
# Commit: Phase 144b — Virtual provider IDs, delete LMStudioProvider

# ── PHASE 145a — Provider Routing Cleanup Tests ──────────────────────────────
Read phases/phase-145a-provider-routing-cleanup-tests.md and execute.
# Verify: BUILD FAILED — routing cleanup symbols not defined (expected)
# Commit: Phase 145a — provider routing cleanup tests (failing)

# ── PHASE 145b — Provider Routing Cleanup ────────────────────────────────────
Read phases/phase-145b-provider-routing-cleanup.md and execute.
# Verify: BUILD SUCCEEDED; all 145a tests pass; zero warnings
# Commit: Phase 145b — Remove proProvider/flashProvider/visionProvider, simplify routing

# ── PHASE 146a — Provider Settings UI Tests ──────────────────────────────────
Read phases/phase-146a-provider-settings-ui-tests.md and execute.
# Verify: BUILD FAILED — ProviderSettingsView symbols not defined (expected)
# Commit: Phase 146a — provider settings UI tests (failing)

# ── PHASE 146b — Provider Settings UI ────────────────────────────────────────
Read phases/phase-146b-provider-settings-ui.md and execute.
# Verify: BUILD SUCCEEDED; all 146a tests pass; zero warnings
# Commit: Phase 146b — Provider settings UI with dynamic model picker

# ── PHASE 147a — Adaptive Loop Ceiling Tests ─────────────────────────────────
Read phases/phase-147a-adaptive-loop-ceiling-tests.md and execute.
# Verify: BUILD FAILED — adaptive ceiling symbols not defined (expected)
# Commit: Phase 147a — adaptive loop ceiling tests (failing)

# ── PHASE 147b — Adaptive Loop Ceiling ───────────────────────────────────────
Read phases/phase-147b-adaptive-loop-ceiling.md and execute.
# Verify: BUILD SUCCEEDED; all 147a tests pass; zero warnings
# Commit: Phase 147b — Adaptive loop ceiling based on project size

# ── PHASE 148a — Document Verification Tests ─────────────────────────────────
Read phases/phase-148a-document-verification-tests.md and execute.
# Verify: BUILD FAILED — document verification symbols not defined (expected)
# Commit: Phase 148a — document verification tests (failing)

# ── PHASE 148b — Document Verification ───────────────────────────────────────
Read phases/phase-148b-document-verification.md and execute.
# Verify: BUILD SUCCEEDED; all 148a tests pass; zero warnings
# Commit: Phase 148b — Two-tier document verification (truncation fix, firing condition, structured prompt, verdict parsing)

# ── PHASE 149a — LM Studio Context Auto-Resize Tests ─────────────────────────
Read phases/phase-149a-lmstudio-context-autoresize-tests.md and execute.
# Verify: BUILD FAILED — ensureContextLength not defined (expected)
# Commit: Phase 149a — LM Studio context auto-resize tests (failing)

# ── PHASE 149b — LM Studio Context Auto-Resize ───────────────────────────────
Read phases/phase-149b-lmstudio-context-autoresize.md and execute.
# Verify: BUILD SUCCEEDED; all 149a tests pass; zero warnings
# Commit: Phase 149b — LM Studio context auto-resize

# ── PHASE 150a — Loop Continuation Tests ─────────────────────────────────────
Read phases/phase-150a-loop-continuation-tests.md and execute.
# Verify: BUILD SUCCEEDED; tests compile but LoopContinuationTests fail at runtime (expected)
# Commit: Phase 150a — LoopContinuationTests (failing)

# ── PHASE 150b — Loop Continuation and Near-Ceiling Warning ──────────────────
Read phases/phase-150b-loop-continuation.md and execute.
# Verify: BUILD SUCCEEDED; all 6 LoopContinuationTests pass; zero warnings
# Commit: Phase 150b — loop continuation and near-ceiling warning

# ── PHASE 166a — WKWebView Chat Renderer Tests ───────────────────────────────
Read phases/phase-166a-wkwebview-chat-tests.md and execute.
# Verify: BUILD FAILED — ConversationHTMLRenderer type missing (expected)
# Commit: Phase 166a — ConversationHTMLRendererTests (failing)

# ── PHASE 166b — WKWebView Chat Renderer Implementation ──────────────────────
Read phases/phase-166b-wkwebview-chat.md and execute.
# Verify: BUILD SUCCEEDED; all ConversationHTMLRendererTests pass
# Manual: drag-select text across multiple messages works
# Commit: Phase 166b — WKWebView conversation renderer (cross-message selection)

# ── V1.5 — Session History & Archive ─────────────────────────────────────────

# ── PHASE 181a — Session Archive Tests ───────────────────────────────────────
Read phases/phase-181a-session-archive-tests.md and execute.
# Verify: BUILD FAILED — Session.archived, SessionStore.scopedDirectoryName,
#         archive/unarchive, activeSessions, archivedSessions,
#         migrateLegacyIfNeeded not found (expected)
# Commit: Phase 181a — SessionArchiveTests (failing)

# ── PHASE 181b — Session Archive Implementation ───────────────────────────────
Read phases/phase-181b-session-archive.md and execute.
# Verify: BUILD SUCCEEDED; all SessionArchiveTests pass
# Commit: Phase 181b — Session.archived + SessionStore project-scoped path + archive/unarchive

# ── PHASE 182a — Session Restore Tests ───────────────────────────────────────
Read phases/phase-182a-session-restore-tests.md and execute.
# Verify: BUILD FAILED — ContextManager.load, SessionManager.restore,
#         SessionManager.sessionStore not found (expected)
# Commit: Phase 182a — SessionRestoreTests (failing)

# ── PHASE 182b — Session Restore Implementation ───────────────────────────────
Read phases/phase-182b-session-restore.md and execute.
# Verify: BUILD SUCCEEDED; all SessionRestoreTests pass
# Commit: Phase 182b — ContextManager.load + LiveSession initial messages + SessionManager.restore

# ── PHASE 183a — Session Sidebar Helper Tests ─────────────────────────────────
Read phases/phase-183a-session-sidebar-tests.md and execute.
# Verify: BUILD FAILED — RelativeTimestampFormatter not found (expected)
# Commit: Phase 183a — SessionSidebarHelpersTests (failing)

# ── PHASE 183b — Session Sidebar Implementation ───────────────────────────────
Read phases/phase-183b-session-sidebar.md and execute.
# Verify: BUILD SUCCEEDED; all SessionSidebarHelpersTests pass
# Manual: Prior Sessions section visible, archive/recall context menus work,
#         timestamps display correctly, Resume opens live session with history
# Commit: Phase 183b — SessionSidebar Prior Sessions + archive/recall + timestamps

# ── PHASE 184 — Version Bump to v1.5.0 ───────────────────────────────────────
Read phases/phase-184-version-bump-v1-5.md and execute.
# Verify: BUILD SUCCEEDED; About Merlin shows 1.5.0
# Commit: Bump version to 1.5.0 (build 4)
# Tag: v1.5.0

# ── DONE (v1.5 Session History & Archive) ─────────────────────────────────────
# Phases 181–184 add session history and archive/recall to the sidebar:
# - 181: Session.archived field; SessionStore scoped per-project directory;
#   archive/unarchive/activeSessions/archivedSessions; legacy migration
# - 182: ContextManager.load for bulk message injection; LiveSession accepts
#   initialMessages + shared sessionStore; SessionManager.restore cold-restores
#   a persisted session as a new LiveSession with auto-compaction
# - 183: RelativeTimestampFormatter; SessionSidebar Prior Sessions section with
#   timestamps, archived collapse, context menus (Resume/Archive/Recall/Delete)
# - 184: Marketing version 1.5.0, build 4, tag v1.5.0

# ── V1.6 — Multi-Project Workspace + Session Auto-Labeling ───────────────────

# ── PHASE 185a — WorkspaceCoordinator Tests ───────────────────────────────────
Read phases/phase-185a-workspace-coordinator-tests.md and execute.
# Verify: BUILD FAILED — WorkspaceCoordinator not found (expected)
# Commit: Phase 185a — WorkspaceCoordinatorTests (failing)

# ── PHASE 185b — WorkspaceCoordinator Implementation ─────────────────────────
Read phases/phase-185b-workspace-coordinator.md and execute.
# Verify: BUILD SUCCEEDED; all WorkspaceCoordinatorTests pass
# Commit: Phase 185b — WorkspaceCoordinator: multi-project state, persistence, activeProjectManager

# ── PHASE 186b — Multi-Project UI ────────────────────────────────────────────
Read phases/phase-186b-multiproject-ui.md and execute.
# Verify: BUILD SUCCEEDED, zero warnings
# Manual: single workspace window; picker sheet on first launch; project sections
#   in sidebar; project header popover (New Session / Close Project); terminal
#   and side chat follow active project; relaunch restores all open projects;
#   Cmd+N opens picker sheet
# Commit: Phase 186b — Single-window multi-project: coordinator-driven UI, picker sheet, persistence

# ── PHASE 187a — Session Title Tests ─────────────────────────────────────────
Read phases/phase-187a-session-title-tests.md and execute.
# Verify: BUILD FAILED — AgenticEngine.onTitleUpdate / applyTitleUpdateIfNeeded not found (expected)
# Commit: Phase 187a — SessionTitleTests (failing)

# ── PHASE 187b — Session Title Auto-Labeling ──────────────────────────────────
Read phases/phase-187b-session-title.md and execute.
# Verify: BUILD SUCCEEDED; all SessionTitleTests pass
# Manual: send first message in new session → sidebar label updates to message text
# Commit: Phase 187b — Session title auto-labeling from first user message

# ── PHASE 188 — Version Bump to v1.6.0 ───────────────────────────────────────
Read phases/phase-188-version-bump-v1-6.md and execute.
# Verify: BUILD SUCCEEDED; CFBundleShortVersionString == 1.6.0
# Commit: Bump version to 1.6.0 (build 5)
# Tag: v1.6.0

# ── PHASE 189 — Crash Fix: ChatView + Version Bump to v1.6.1 ─────────────────
Read phases/phase-189-crash-fix-chatview-v1-6-1.md and execute.
# Fix: ChatView @EnvironmentObject SessionManager → @FocusedObject; WorkspaceView exposes activeManager
# Verify: BUILD SUCCEEDED; CFBundleShortVersionString == 1.6.1; app launches without trapping
# Commit: Bump version to 1.6.1 (build 6) — patch fix for ChatView crash
# Tag: v1.6.1

# ── DONE (v1.6 Multi-Project Workspace) ───────────────────────────────────────
# Phases 185–189:
# - 185: WorkspaceCoordinator — [SessionManager], activeProjectManager, persistence
#   to ~/.merlin/workspace.json; first-launch auto-opens picker; relaunch restores
#   all previous projects (no auto live sessions — resume from Prior Sessions)
# - 186: Single workspace window (WindowGroup id:"workspace", no per-project WindowGroup);
#   SessionSidebar per-project sections; project label → popover (New Session / Close Project);
#   bottom button → New Project Workspace picker sheet; SideChatPane uses active
#   project path; TerminalPane follows active project; MerlinApp simplified;
#   MerlinCommands uses WorkspaceCoordinator
#   ADDENDUM (2fddbac): ChatView @FocusedObject crash fix + WorkspaceView activeManager
# - 187: AgenticEngine.onTitleUpdate + applyTitleUpdateIfNeeded; LiveSession wires
#   callback; sessions auto-titled from first user message (50 chars, like Claude/Codex)
# - 188: Marketing version 1.6.0, build 5, tag v1.6.0
# - 189: Crash fix — ChatView EnvironmentObject → FocusedObject; version 1.6.1, build 6, tag v1.6.1

# ── DONE (v10 Reliability & Orchestration) ────────────────────────────────────
# Phases 143–150 close two categories of silent failure:
#
# Provider layer (143–149):
# - Dynamic model fetch (143): ProviderRegistry pulls live model lists from LM Studio
# - Virtual provider IDs (144): decouple slot assignments from physical provider URLs
# - Provider routing cleanup (145): single selectProvider() path, no proProvider/flashProvider
# - Provider settings UI (146): dynamic model picker with live fetch
# - Adaptive loop ceiling (147): ceiling scales with project size (10–80 iterations)
# - Document verification (148): critic fires for all substantial output; no truncation
# - LM Studio context auto-resize (149): critic queries /api/v0/models and reloads
#   with nextPowerOf2 context length before Stage 2 — fixes error 4865 (n_keep >= n_ctx)
#
# Engine orchestration (150):
# - Plan batching: large plans are split across turns via [CONTINUATION] inject;
#   continuation turns bypass re-planning and use the high-stakes loop ceiling
# - Near-ceiling warning: ⚠️ system note + system prompt addendum when
#   loopsRemaining ≤ nearCeilingThreshold; fires once per turn
#
# ── DONE (v1.9.1 Prompt Compression) ─────────────────────────────────────────
# Phases 205–207 add three-layer prompt compression to keep per-turn cost linear:
#
# Mid-loop compaction (205):
# - compactIfNeededMidLoop(): fires inside while-true execute loop when
#   estimatedTokens > midLoopCompactionThreshold (default 40,000)
# - Removes oldest complete tool-exchange groups; inserts static sentinel
#
# LLM summarisation (206):
# - compactWithSummaryIfNeeded(provider:): async replacement for the sync call
# - Extracts removable exchange text, calls provider for narrative digest
# - customDigest replaces static sentinel in system message
# - Falls back to exchangeText prefix on provider error
#
# Instruction distillation (207):
# - distilledCoreSystemPrompt: compact 3-line version of 18-line coreSystemPrompt
# - refreshDistilledClaudeMD(using:): one-shot provider call to compress CLAUDE.md;
#   cached against SHA256 hash — re-distils only when content changes
# - buildStablePrefix() branches on AppSettings.shared.promptCompressionEnabled
# - AppSettings: promptCompressionEnabled @Published var, persisted as
#   prompt_compression_enabled in config.toml
# - Toggle: Settings → Agent → Prompt Compression
#
# v1.9.1, build 14

# ── NEXT (Merlin v2.0 Electronics/KiCad Foundation) ─────────────────────────
# Phase 208 establishes the first implementation contracts for the v2.0
# Electronics/KiCad feature set.
#
# IMPORTANT for Merlin execution:
# Do not run phases 209–218 in a single prompt. Use:
#   phases/RUN-209-218-BATCHES.md
# and execute one A/B pair per turn, compacting or starting a fresh turn between pairs.

# ── PHASE 208a — KiCad Core Contracts Tests ────────────────────────────────
Read phases/phase-208a-merlin-v2-kicad-core-contracts-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad v2.0 core-contract symbols
# Commit: Phase 208a — KiCadV2CoreContractsTests (failing)

# ── PHASE 208b — KiCad Core Contracts ──────────────────────────────────────
Read phases/phase-208b-merlin-v2-kicad-core-contracts.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadV2CoreContractsTests pass
# Commit: Phase 208b — Merlin v2.0 KiCad core contracts

# ── PHASE 209a — KiCad MCP Tooling Boundary Tests ──────────────────────────
Read phases/phase-209a-kicad-mcp-tooling-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad MCP tooling symbols
# Commit: Phase 209a — KiCadMCPToolingTests (failing)

# ── PHASE 209b — KiCad MCP Tooling Boundary ────────────────────────────────
Read phases/phase-209b-kicad-mcp-tooling.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadMCPToolingTests pass
# Commit: Phase 209b — KiCad MCP tooling boundary

# ── PHASE 210a — KiCad Artifact Schemas Tests ──────────────────────────────
Read phases/phase-210a-kicad-artifact-schemas-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad artifact schema/store symbols
# Commit: Phase 210a — KiCadArtifactSchemasTests (failing)

# ── PHASE 210b — KiCad Artifact Schemas ────────────────────────────────────
Read phases/phase-210b-kicad-artifact-schemas.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadArtifactSchemasTests pass
# Commit: Phase 210b — KiCad artifact schemas and store

# ── PHASE 211a — KiCad Schematic Parser Tests ──────────────────────────────
Read phases/phase-211a-kicad-schematic-parser-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad schematic parser symbols
# Commit: Phase 211a — KiCadSchematicParserTests (failing)

# ── PHASE 211b — KiCad Schematic Parser ────────────────────────────────────
Read phases/phase-211b-kicad-schematic-parser.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadSchematicParserTests pass
# Commit: Phase 211b — KiCad schematic parser and writer

# ── PHASE 212a — Schematic Extraction Policy Tests ─────────────────────────
Read phases/phase-212a-schematic-extraction-policy-tests.md and execute.
# Verify: BUILD FAILED with missing schematic extraction policy symbols
# Commit: Phase 212a — SchematicExtractionPolicyTests (failing)

# ── PHASE 212b — Schematic Extraction Policy ───────────────────────────────
Read phases/phase-212b-schematic-extraction-policy.md and execute.
# Verify: BUILD SUCCEEDED; all SchematicExtractionPolicyTests pass
# Commit: Phase 212b — schematic extraction policy and clarification planning

# ── PHASE 213a — Components/Footprints/BOM Tests ───────────────────────────
Read phases/phase-213a-components-footprints-bom-tests.md and execute.
# Verify: BUILD FAILED with missing component/footprint/BOM policy symbols
# Commit: Phase 213a — ComponentsFootprintsBOMTests (failing)

# ── PHASE 213b — Components/Footprints/BOM ─────────────────────────────────
Read phases/phase-213b-components-footprints-bom.md and execute.
# Verify: BUILD SUCCEEDED; all ComponentsFootprintsBOMTests pass
# Commit: Phase 213b — components footprints libraries and BOM policy

# ── PHASE 214a — Board/Routing Policy Tests ────────────────────────────────
Read phases/phase-214a-board-routing-policy-tests.md and execute.
# Verify: BUILD FAILED with missing board/routing policy symbols
# Commit: Phase 214a — BoardRoutingPolicyTests (failing)

# ── PHASE 214b — Board/Routing Policy ──────────────────────────────────────
Read phases/phase-214b-board-routing-policy.md and execute.
# Verify: BUILD SUCCEEDED; all BoardRoutingPolicyTests pass
# Commit: Phase 214b — board profiles net classes placement and routing policy

# ── PHASE 215a — Verification/Fab Policy Tests ─────────────────────────────
Read phases/phase-215a-verification-fab-policy-tests.md and execute.
# Verify: BUILD FAILED with missing verification/fab policy symbols
# Commit: Phase 215a — VerificationFabPolicyTests (failing)

# ── PHASE 215b — Verification/Fab Policy ───────────────────────────────────
Read phases/phase-215b-verification-fab-policy.md and execute.
# Verify: BUILD SUCCEEDED; all VerificationFabPolicyTests pass
# Commit: Phase 215b — verification gates fabrication and visual QA policy

# ── PHASE 216a — Vendor Order/Approval Tests ───────────────────────────────
Read phases/phase-216a-vendor-order-approval-tests.md and execute.
# Verify: BUILD FAILED with missing vendor/order/approval symbols
# Commit: Phase 216a — VendorOrderApprovalTests (failing)

# ── PHASE 216b — Vendor Order/Approval ─────────────────────────────────────
Read phases/phase-216b-vendor-order-approval.md and execute.
# Verify: BUILD SUCCEEDED; all VendorOrderApprovalTests pass
# Commit: Phase 216b — vendor BOM order and electronics approval policy

# ── PHASE 217a — KiCad Workflow Orchestration Tests ────────────────────────
Read phases/phase-217a-kicad-workflow-orchestration-tests.md and execute.
# Verify: BUILD FAILED with missing workflow orchestration symbols
# Commit: Phase 217a — KiCadWorkflowOrchestrationTests (failing)

# ── PHASE 217b — KiCad Workflow Orchestration ──────────────────────────────
Read phases/phase-217b-kicad-workflow-orchestration.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadWorkflowOrchestrationTests pass
# Commit: Phase 217b — KiCad workflow orchestration

# ── PHASE 218a — Merlin v2.0 Version Release Tests ─────────────────────────
Read phases/phase-218a-merlin-v2-version-release-tests.md and execute.
# Verify: BUILD FAILED until version/release artifacts are bumped
# Commit: Phase 218a — MerlinV2VersionTests (failing)

# ── PHASE 218b — Merlin v2.0 Version Release ───────────────────────────────
Read phases/phase-218b-merlin-v2-version-release.md and execute.
# Verify: BUILD SUCCEEDED; all MerlinV2VersionTests pass
# Commit: Phase 218b — Merlin v2.0 version release
# Tag: v2.0.0
```

---

## Budget-Aware Execution (v2.1.0) - RELEASED v2.1.0

Run phases 232–240 in strict sequence. Each `a` is failing tests; each `b` is the implementation
that satisfies them. Do not skip a commit. Do not batch commits across phases. Phase 240b tags
and publishes the v2.1.0 release.

```bash
# ── PHASE 232a — Budget Telemetry Tests ────────────────────────────────────
Read phases/phase-232a-budget-telemetry-tests.md and execute.
# Verify: BUILD FAILED until telemetry surfaces land
# Commit: Phase 232a — BudgetTelemetryTests (failing)

# ── PHASE 232b — Budget Telemetry ──────────────────────────────────────────
Read phases/phase-232b-budget-telemetry.md and execute.
# Verify: BUILD SUCCEEDED; all phase 232a tests pass
# Commit: Phase 232b — Budget telemetry

# ── PHASE 233a — ProviderBudget + Pre-Flight Tests ─────────────────────────
Read phases/phase-233a-provider-budget-preflight-tests.md and execute.
# Verify: BUILD FAILED until ProviderBudget/TokenEstimator/pre-flight land
# Commit: Phase 233a — ProviderBudgetAndPreflightTests (failing)

# ── PHASE 233b — ProviderBudget + Pre-Flight Gate ──────────────────────────
Read phases/phase-233b-provider-budget-preflight.md and execute.
# Verify: BUILD SUCCEEDED; all phase 233a tests pass
# Commit: Phase 233b — ProviderBudget and pre-flight gate

# ── PHASE 234a — Working-Set Caps Tests ────────────────────────────────────
Read phases/phase-234a-working-set-caps-tests.md and execute.
# Verify: BUILD FAILED until per-component caps land
# Commit: Phase 234a — WorkingSetCapsTests (failing)

# ── PHASE 234b — Working-Set Caps ──────────────────────────────────────────
Read phases/phase-234b-working-set-caps.md and execute.
# Verify: BUILD SUCCEEDED; all phase 234a tests pass
# Commit: Phase 234b — Working-set caps

# ── PHASE 235a — Adaptive RAG Tests ────────────────────────────────────────
Read phases/phase-235a-adaptive-rag-tests.md and execute.
# Verify: BUILD FAILED until RAGSelector lands
# Commit: Phase 235a — AdaptiveRAGTests (failing)

# ── PHASE 235b — Adaptive RAG ──────────────────────────────────────────────
Read phases/phase-235b-adaptive-rag.md and execute.
# Verify: BUILD SUCCEEDED; all phase 235a tests pass
# Commit: Phase 235b — Adaptive RAG

# ── PHASE 236a — Enriched PlanStep + refineStep Tests ──────────────────────
Read phases/phase-236a-planstep-enrichment-refine-tests.md and execute.
# Verify: BUILD FAILED until enriched PlanStep and refineStep land
# Commit: Phase 236a — EnrichedPlanStepAndRefineTests (failing)

# ── PHASE 236b — Enriched PlanStep + refineStep ────────────────────────────
Read phases/phase-236b-planstep-enrichment-refine.md and execute.
# Verify: BUILD SUCCEEDED; all phase 236a tests pass
# Commit: Phase 236b — Enriched PlanStep and refineStep

# ── PHASE 237a — Unified Executor Gate Tests ───────────────────────────────
Read phases/phase-237a-executor-gate-tests.md and execute.
# Verify: BUILD FAILED until EscalationHandler lands and recursive recovery is deleted
# Commit: Phase 237a — UnifiedExecutorGateTests (failing)

# ── PHASE 237b — Unified Executor Gate + Recovery Deletion ─────────────────
Read phases/phase-237b-executor-gate.md and execute.
# Verify: BUILD SUCCEEDED; all phase 237a tests pass; no recursive runLoop self-call remains
# Commit: Phase 237b — Unified executor gate, delete recursive recovery

# ── PHASE 238a — Critic Gating Tests ───────────────────────────────────────
Read phases/phase-238a-critic-gating-tests.md and execute.
# Verify: BUILD FAILED until critic policy resolver and CriterionChecker land
# Commit: Phase 238a — CriticGatingTests (failing)

# ── PHASE 238b — Critic Gating ─────────────────────────────────────────────
Read phases/phase-238b-critic-gating.md and execute.
# Verify: BUILD SUCCEEDED; all phase 238a tests pass
# Commit: Phase 238b — Critic gating

# ── PHASE 239a — Decompose-on-Overflow Tests ───────────────────────────────
Read phases/phase-239a-decompose-on-overflow-tests.md and execute.
# Verify: BUILD FAILED until decompose-first + cross-provider routing land
# Commit: Phase 239a — DecomposeOnOverflowTests (failing)

# ── PHASE 239b — Decompose-on-Overflow ─────────────────────────────────────
Read phases/phase-239b-decompose-on-overflow.md and execute.
# Verify: BUILD SUCCEEDED; all phase 239a tests pass
# Commit: Phase 239b — Decompose-on-overflow

# ── PHASE 240a — v2.1.0 Release Tests ──────────────────────────────────────
Read phases/phase-240a-v2-1-release-tests.md and execute.
# Verify: BUILD FAILED until project.yml bumped and RELEASE-v2.1.0.md added
# Commit: Phase 240a — V2_1ReleaseTests (failing)

# ── PHASE 240b — v2.1.0 Release ────────────────────────────────────────────
Read phases/phase-240b-v2-1-release.md and execute.
# Verify: BUILD SUCCEEDED; "About Merlin" shows 2.1.0 (16)
# Commit: Phase 240b — Bump version to 2.1.0 (Budget-Aware Execution)
# Tag: v2.1.0
# Release: gh release create v2.1.0 --latest
```

---

## Project Discipline

```bash
# ── PHASE 277 — Telemetry Test-Seam Cleanup ─────────────────────────────────
cat phases/phase-277-telemetry-test-cleanup.md
# Verify: BUILD SUCCEEDED; zero warnings; full suite green headless
# Commit: Phase 277 — Remove dead telemetry test seam, dedup reader, fix dismiss test
```

```bash
# -- PHASE 278a — v2.2.2 Release Tests (failing) ----------------------------
cat phases/phase-278a-v2-2-2-release-tests.md
# Verify: BUILD SUCCEEDED; AppVersion222Tests + ReleaseNotes222Tests fail at runtime
# Commit: Phase 278a — V2_2_2ReleaseTests (failing)

# -- PHASE 278b — v2.2.2 Release -------------------------------------------
cat phases/phase-278b-v2-2-2-release.md
# Ships the CI-readiness remediation and regression fixes as v2.2.2.
# Verify: BUILD SUCCEEDED; full suite green headless; version banners read 2.2.2/build 19
# Commit: Phase 278b — Bump version to 2.2.2 (build 19)
```

---

## Context-Overflow Hardening (toward v2.2.4)

> **Model:** run these on **gpt-5.5**, not gpt-5.4-mini. 285b and 286b are
> cross-cutting changes under `SWIFT_STRICT_CONCURRENCY=complete` (a new actor with an
> injected protocol + `nonisolated static` persistence helpers; 286b reroutes 14
> `provider.complete` sites across 11 files and adds actor-hopped learn-and-retry).
> The mini tier is documented for "lighter coding tasks"; this batch is not light.
> Run a→b strictly in order; do not start a `b` phase until its `a` commit exists.

```bash
# ── PHASE 283a — Local Model Picker Entries Tests (failing) ─────────────────
cat phases/phase-283a-local-model-picker-tests.md
# Verify: BUILD SUCCEEDED; testLocalProviderWithModelsYieldsOnlyVirtualEntries FAILS at runtime
# Commit: Phase 283a — LocalModelPickerEntriesTests (failing)

# ── PHASE 283b — Local Model Picker ─────────────────────────────────────────
cat phases/phase-283b-local-model-picker.md
# Verify: BUILD SUCCEEDED; all phase 283a tests pass; no prior phase regresses
# Commit: Phase 283b — Local model picker in chat HUD + slot picker; model-list refresh

# ── PHASE 284a — Tool Output Cap Tests (failing) ────────────────────────────
cat phases/phase-284a-tool-output-cap-tests.md
# Verify: BUILD FAILED — errors naming the missing ToolOutput type / clamp / maxChars
# Commit: Phase 284a — ToolOutputClampTests (failing)

# ── PHASE 284b — Tool Output Cap ────────────────────────────────────────────
cat phases/phase-284b-tool-output-cap.md
# Verify: BUILD SUCCEEDED; all phase 284a tests pass; no prior phase regresses
# Commit: Phase 284b — Cap run_shell and read_file output before it enters context

# ── PHASE 285a — Context Budget Resolver Tests (failing) ────────────────────
cat phases/phase-285a-context-budget-resolver-tests.md
# Verify: BUILD FAILED — missing ContextBudgetResolver / ContextBudgetStore / EphemeralBudgetStore
# Commit: Phase 285a — ContextBudgetResolverTests (failing)

# ── PHASE 285b — Context Budget Resolver ────────────────────────────────────
cat phases/phase-285b-context-budget-resolver.md
# Verify: BUILD SUCCEEDED; all phase 285a tests pass; no prior phase regresses
# Commit: Phase 285b — ContextBudgetResolver: discover and persist the model's real context window

# ── PHASE 286a — Universal Pre-flight Guard Tests (failing) ─────────────────
cat phases/phase-286a-universal-preflight-tests.md
# Verify: BUILD FAILED — errors naming the missing PreflightGuard type / fit
# Commit: Phase 286a — PreflightGuardTests (failing)

# ── PHASE 286b — Universal Pre-flight Guard ─────────────────────────────────
cat phases/phase-286b-universal-preflight.md
# Verify: BUILD SUCCEEDED; all phase 286a tests pass; grep finds no un-guarded provider.complete
# Commit: Phase 286b — Route every provider send through PreflightGuard
```

---

## Tool Detection + Vision Launchpad (toward v2.2.4)

> **Model:** gpt-5.5, reasoning effort `high`. 287b adds a new actor + a SwiftUI
> sheet + first-use wiring across several files under strict concurrency; 288 is
> skill/doc work. Run a→b strictly in order.

```bash
# ── PHASE 287a — Tool Requirement Checker Tests (failing) ───────────────────
cat phases/phase-287a-tool-requirement-checker-tests.md
# Verify: BUILD FAILED — missing ToolRequirement / ToolRequirements / ToolRequirementChecker
# Commit: Phase 287a — ToolRequirementCheckerTests (failing)

# ── PHASE 287b — Tool Requirement Checker ───────────────────────────────────
cat phases/phase-287b-tool-requirement-checker.md
# Verify: BUILD SUCCEEDED; all phase 287a tests pass; no prior phase regresses
# Commit: Phase 287b — Tool requirement checker: detect on first use, offer brew install

# ── PHASE 288a — Vision Launchpad Tests (failing) ───────────────────────────
cat phases/phase-288a-vision-launchpad-tests.md
# Verify: BUILD SUCCEEDED; ProjectVisionLaunchpadTests fail at runtime (skill not yet updated)
# Commit: Phase 288a — ProjectVisionLaunchpadTests (failing)

# ── PHASE 288b — Vision Launchpad ───────────────────────────────────────────
cat phases/phase-288b-vision-launchpad.md
# Verify: BUILD SUCCEEDED; all phase 288a tests pass; vision.md has ## Active + ## Deferred
# Commit: Phase 288b — vision.md launchpad: seed at init, vision→architecture→phase→code pipeline
```

```bash
# ── PHASE 289 — v2.2.4 Release (ships phases 283–288) ───────────────────────
# Run only after 283–288 are all committed.
cat phases/phase-289-v2-2-4-release.md
# Verify: BUILD SUCCEEDED; full suite green; grep finds no stale 2.2.3/build 20
# Commit: Phase 289 — Bump version to 2.2.4 (build 21); local tag v2.2.4
# NOTE: git push + gh release create are a MANUAL step — do not push in the batch.
```

---

## Liveness Discipline (phases 307–312)

> Extends Project Discipline to catch *liveness drift* — code that exists and compiles
> but is never reached, gated, or finished (off-gate targets, stub/deferred code,
> unwired components, stale docs). Four scanners + a pre-commit gate + the verification
> gate fix. Run a→b strictly in order; each `b` phase wires its scanner into
> `DisciplineEngine` with a defaulted init parameter, so existing call sites are
> unaffected. Prerequisite: phases 294–306 + 302c complete.

```bash
# ── PHASE 307a — TargetGateScanner Tests (failing) ──────────────────────────
cat phases/phase-307a-target-gate-scanner-tests.md
# Verify: BUILD FAILED — missing TargetGateScanner / UngatedTargetFinding
# Commit: Phase 307a — TargetGateScanner tests (failing)

# ── PHASE 307b — TargetGateScanner ──────────────────────────────────────────
cat phases/phase-307b-target-gate-scanner.md
# Verify: BUILD SUCCEEDED, zero warnings; TargetGateScannerTests + FindingModelTests pass
# Commit: Phase 307b — TargetGateScanner: flag targets the build gate never compiles

# ── PHASE 308a — StubMarkerScanner Tests (failing) ──────────────────────────
cat phases/phase-308a-stub-marker-scanner-tests.md
# Verify: BUILD FAILED — missing StubMarkerScanner / StubMarkerFinding
# Commit: Phase 308a — StubMarkerScanner tests (failing)

# ── PHASE 308b — StubMarkerScanner ──────────────────────────────────────────
cat phases/phase-308b-stub-marker-scanner.md
# Verify: BUILD SUCCEEDED, zero warnings; StubMarkerScannerTests + FindingModelTests pass
# Commit: Phase 308b — StubMarkerScanner: surface unfinished code as discipline findings

# ── PHASE 309a — ReachabilityScanner Tests (failing) ────────────────────────
cat phases/phase-309a-reachability-scanner-tests.md
# Verify: BUILD FAILED — missing ReachabilityScanner / UnwiredComponentFinding
# Commit: Phase 309a — ReachabilityScanner tests (failing)

# ── PHASE 309b — ReachabilityScanner ────────────────────────────────────────
cat phases/phase-309b-reachability-scanner.md
# Verify: BUILD SUCCEEDED, zero warnings; ReachabilityScannerTests + FindingModelTests pass
# Commit: Phase 309b — ReachabilityScanner: flag unwired views and uninjected env objects

# ── PHASE 310a — DocReferenceGraph Fenced-Block Tests (failing) ─────────────
cat phases/phase-310a-doc-reference-fenced-block-tests.md
# Verify: BUILD SUCCEEDED; DocReferenceGraphFencedBlockTests FAILS at runtime (verify with `test`)
# Commit: Phase 310a — DocReferenceGraph fenced-block tests (failing)

# ── PHASE 310b — DocReferenceGraph Fenced-Block Strengthening ───────────────
cat phases/phase-310b-doc-reference-fenced-block.md
# Verify: BUILD SUCCEEDED, zero warnings; DocReferenceGraphFencedBlockTests passes
# Commit: Phase 310b — DocReferenceGraph verifies fenced-block enum cases

# ── PHASE 311a — LivenessGate Tests (failing) ───────────────────────────────
cat phases/phase-311a-liveness-gate-tests.md
# Verify: BUILD FAILED — missing LivenessGate / LivenessGateResult
# Commit: Phase 311a — LivenessGate tests (failing)

# ── PHASE 311b — LivenessGate + pre-commit hook ─────────────────────────────
cat phases/phase-311b-liveness-gate.md
# Verify: BUILD SUCCEEDED, zero warnings; LivenessGateTests + DisciplineCLITests pass; merlin-discipline builds
# Commit: Phase 311b — LivenessGate: pre-commit hook blocks ungated targets

# ── PHASE 312 — Verification Gate Update ────────────────────────────────────
cat phases/phase-312-verification-gate-update.md
# Verify: CLAUDE.md names MerlinTests-Live; .merlin/project.toml lists both gating schemes; MerlinTests-Live build-for-testing SUCCEEDED
# Commit: Phase 312 — Fold MerlinTests-Live into the verification gate
```

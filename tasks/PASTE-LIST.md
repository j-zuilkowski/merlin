# Codex Paste List — Merlin

Model: gpt-5.4-mini
Invocation: paste the content of each task file directly into the Codex prompt.
No terminal trips, no HANDOFF.md references — every file is self-contained.
Each file includes its own context header, full task, verify step, and git commit.

---

```bash
# ── PHASE 00 — Preflight (run once in terminal before starting Codex) ───
cd ~/Documents/localProject/merlin
bash tasks/task-00-preflight.sh
# Must exit 0. Warnings are non-fatal.

# ── HOW TO RUN EACH PHASE ──────────────────────────────���─────────────────
# In Codex, paste the content of each task file:
#   cat tasks/task-XX-name.md
# Codex reads the instructions, writes the files, runs the verify step,
# and commits. Then move to the next phase.

# ── PHASE 01 — Scaffold (xcodegen) ──────────────────────��────────────────
cat tasks/task-01-scaffold.md
# Verify: xcodegen generate + xcodebuild -scheme MerlinTests build-for-testing → BUILD SUCCEEDED
# Commit: git commit -m "Phase 01 — xcodegen scaffold"

# ── PHASE 02a — Shared Types Tests ───────────────────────────────────────
cat tasks/task-02a-shared-types-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 02a

# ── PHASE 02b — Shared Types Implementation ──────────────────────────────
cat tasks/task-02b-shared-types.md
# Verify: SharedTypesTests → 5 pass
# Commit: Phase 02b

# ── PHASE 03a — Provider Tests ───────────────────────────────────────────
cat tasks/task-03a-provider-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 03a

# ── PHASE 03b — DeepSeekProvider + SSEParser ─────────────────────────────
cat tasks/task-03b-deepseek-provider.md
# Verify: ProviderTests → 5 pass
# Commit: Phase 03b

# ── PHASE 04 — LMStudioProvider ──────────────────────────────────────────
cat tasks/task-04-lmstudio-provider.md
# Verify: BUILD SUCCEEDED; live test skips without RUN_LIVE_TESTS
# Commit: Phase 04

# ── PHASE 05 — KeychainManager ───────────────────────────────────────────
cat tasks/task-05-keychain.md
# Verify: KeychainTests → 3 pass
# Commit: Phase 05

# ── PHASE 06 — Tool Definitions ──────────────────────────────────────────
cat tasks/task-06-tool-definitions.md
# Verify: BUILD SUCCEEDED; ToolDefinitions.all is non-empty
# Commit: Phase 06

# ── PHASE 07a — FileSystem + Shell Tests ─────────────────────────────────
cat tasks/task-07a-filesystem-shell-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 07a

# ── PHASE 07b — FileSystem + Shell Implementation ────────────────────────
cat tasks/task-07b-filesystem-shell.md
# Verify: FileSystemToolTests → 5 pass; ShellToolTests → 4 pass
# Commit: Phase 07b

# ── PHASE 08a — Xcode Tools Tests ────────────────────────────────────────
cat tasks/task-08a-xcode-tools-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 08a

# ── PHASE 08b — Xcode Tools Implementation ───────────────────────────────
cat tasks/task-08b-xcode-tools.md
# Verify: XcodeToolTests → pass (fixture test may skip)
# Commit: Phase 08b

# ── PHASE 09a — AX + ScreenCapture Tests ─────────────────────────────────
cat tasks/task-09a-ax-screencapture-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 09a

# ── PHASE 09b — AXInspectorTool + ScreenCaptureTool ──────────────────────
cat tasks/task-09b-ax-screencapture.md
# Verify: AXInspectorTests → pass (needs Accessibility); ScreenCaptureTests → pass or skip
# Commit: Phase 09b

# ── PHASE 10 — CGEventTool + VisionQueryTool ──────────────────────────────
cat tasks/task-10-cgevent-vision.md
# Verify: CGEventToolTests → 2 pass
# Commit: Phase 10

# ── PHASE 11 — AppControlTools + ToolDiscovery ────────────────────────────
cat tasks/task-11-appcontrol-discovery.md
# Verify: AppControlTests → pass; ToolDiscoveryTests → pass
# Commit: Phase 11

# ── PHASE 12a — Auth Tests ────────────────────────────────────────────────
cat tasks/task-12a-auth-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 12a

# ── PHASE 12b — PatternMatcher + AuthMemory ───────────────────────────────
cat tasks/task-12b-auth-impl.md
# Verify: PatternMatcherTests → 5 pass; AuthMemoryTests → 3 pass
# Commit: Phase 12b

# ── PHASE 13a — AuthGate Tests ────────────────────────────────────────────
cat tasks/task-13a-authgate-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 13a

# ── PHASE 13b — AuthGate Implementation ───────────────────────────────────
cat tasks/task-13b-authgate-impl.md
# Verify: AuthGateTests → 4 pass
# Commit: Phase 13b

# ── PHASE 14a — ContextManager Tests ──────────────────────────────────────
cat tasks/task-14a-contextmanager-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 14a

# ── PHASE 14b — ContextManager Implementation ─────────────────────────────
cat tasks/task-14b-contextmanager-impl.md
# Verify: ContextManagerTests → 5 pass
# Commit: Phase 14b

# ── PHASE 15 — ToolRouter ─────────────────────────────────────────────────
cat tasks/task-15-toolrouter.md
# Verify: ToolRouterTests → 2 pass
# Commit: Phase 15

# ── PHASE 16 — ThinkingModeDetector ───────────────────────────────────────
cat tasks/task-16-thinking-detector.md
# Verify: ThinkingModeDetectorTests → 6 pass
# Commit: Phase 16

# ── PHASE 17a — AgenticEngine Tests ───────────────────────────────────────
cat tasks/task-17a-agenticengine-tests.md
# Verify: build errors for missing types (expected)
# Commit: Phase 17a

# ── PHASE 17b — AgenticEngine Implementation ──────────────────────────────
cat tasks/task-17b-agenticengine-impl.md
# Verify: AgenticEngineTests → 4 pass; zero warnings
# Commit: Phase 17b

# ── PHASE 18 — Sessions ───────────────────────────────────────────────────
cat tasks/task-18-sessions.md
# Verify: SessionSerializationTests → 4 pass
# Commit: Phase 18

# ── PHASE 19 — AppState + Entry Point ─────────────────────────────────────
cat tasks/task-19-appstate-entrypoint.md
# Verify: BUILD SUCCEEDED
# Commit: Phase 19

# ── PHASE 19b — Tool Handler Registration ─────────────────────────────────
cat tasks/task-19b-tool-registration.md
# Verify: BUILD SUCCEEDED; all built-in handlers registered
# Commit: Phase 19b

# ── PHASE 20 — ContentView + ChatView + ProviderHUD ───────────────────────
cat tasks/task-20-chatview.md
# Verify: BUILD SUCCEEDED
# Commit: Phase 20

# ── PHASE 21 — ToolLogView + ScreenPreviewView ────────────────────────────
cat tasks/task-21-secondary-views.md
# Verify: BUILD SUCCEEDED; VisualLayoutTests → testNoWidgetsClipped + testAccessibilityAudit pass
# Commit: Phase 21

# ── PHASE 22 — AuthPopupView + FirstLaunchSetup ───────────────────────────
cat tasks/task-22-authpopup.md
# Verify: BUILD SUCCEEDED
# Commit: Phase 22

# ── PHASE 23 — TestTargetApp ──────────────────────────────────────────────
cat tasks/task-23-test-fixture-app.md
# Verify: BUILD SUCCEEDED; GUIAutomationE2ETests skip without RUN_LIVE_TESTS
# Commit: Phase 23

# ── PHASE 24 — Live Tests + Final E2E ─────────────────────────────────────
cat tasks/task-24-live-e2e.md
# Verify (requires RUN_LIVE_TESTS=1 + DEEPSEEK_API_KEY):
#   DeepSeekProviderLiveTests → 3 pass
#   AgenticLoopE2ETests → 1 pass (reads real file via real API)
#   GUIAutomationE2ETests → pass (with Accessibility + LM Studio running)
# Commit: Phase 24

# ── PHASE 25a — RAG Integration Tests ────────────────────────────────────────
cat tasks/task-25a-rag-tests.md
# Verify: BUILD FAILED with errors for XcalibreClient, RAGChunk, RAGBook, RAGTools,
#         CapturingProvider (expected)
# Commit: Phase 25a

# ── PHASE 25b — RAG Integration Implementation ────────────────────────────────
cat tasks/task-25b-rag-impl.md
# Verify: TEST BUILD SUCCEEDED; XcalibreClientTests → 10 pass; RAGToolsTests → 11 pass;
#         RAGEngineTests → 3 pass
# Commit: Phase 25b

# ── PHASE 26a — Multi-Provider Tests ─────────────────────────────────────────
cat tasks/task-26a-provider-tests.md
# Verify: BUILD FAILED with errors for ProviderRegistry, OpenAICompatibleProvider,
#         AnthropicSSEParser, AnthropicMessageEncoder, AnthropicProvider,
#         AgenticEngine.shouldUseThinking(for:) (expected)
# Commit: Phase 26a

# ── PHASE 26b — Multi-Provider Implementation ─────────────────────────────────
cat tasks/task-26b-provider-impl.md
# Verify: TEST BUILD SUCCEEDED; ProviderRegistryTests → 14 pass;
#         OpenAICompatibleProviderTests → 5 pass; AnthropicSSEParserTests → 7 pass;
#         AnthropicMessageEncoderTests → 5 pass; AnthropicProviderRequestTests → 4 pass;
#         AgenticEngineProviderTests → 4 pass
# Commit: Phase 26b

# ── PHASE 27a — Model Picker Tests ───────────────────────────────────────────
cat tasks/task-27a-model-picker-tests.md
# Verify: BUILD FAILED with errors for ProviderRegistry.knownModels (expected)
# Commit: Phase 27a

# ── PHASE 27b — Model Picker Implementation ───────────────────────────────────
cat tasks/task-27b-model-picker.md
# Verify: BUILD SUCCEEDED; ProviderModelPickerTests → 8 pass
# Commit: Phase 27b

# ── PHASE 28a — Menu Tests ────────────────────────────────────────────────────
cat tasks/task-28a-menu-tests.md
# Verify: BUILD FAILED with errors for AgenticEngine.cancel(), AppState.newSession(),
#         AppState.stopEngine(), Notification.Name.merlinNewSession (expected)
# Commit: Phase 28a

# ── PHASE 28b — Menu Implementation ──────────────────────────────────────────
cat tasks/task-28b-menu.md
# Verify: BUILD SUCCEEDED; AgenticEngineCancelTests → 3 pass;
#         AppStateSessionTests → 4 pass
# Commit: Phase 28b

# ════════════════════════════════════════════════════════════════════════════
# VERSION 2
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 29 — ProjectRef + ProjectPickerView + WindowGroup ──────────────────
cat tasks/task-29-project-picker.md
# Verify: BUILD SUCCEEDED; project picker shown at launch; workspace window opens per project
# Commit: Phase 29

# ── PHASE 30a — SessionManager Tests ─────────────────────────────────────────
cat tasks/task-30a-session-manager-tests.md
# Verify: BUILD FAILED with errors for SessionManager, LiveSession (expected)
# Commit: Phase 30a

# ── PHASE 30b — SessionManager Implementation ─────────────────────────────────
cat tasks/task-30b-session-manager.md
# Verify: BUILD SUCCEEDED; SessionManagerTests → 8 pass
# Commit: Phase 30b

# ── PHASE 31a — Permission Mode Tests ────────────────────────────────────────
cat tasks/task-31a-permission-mode-tests.md
# Verify: BUILD FAILED with errors for PermissionMode (expected)
# Commit: Phase 31a

# ── PHASE 31b — Permission Mode Implementation ───────────────────────────────
cat tasks/task-31b-permission-mode.md
# Verify: BUILD SUCCEEDED; PermissionModeTests → 6 pass
# Commit: Phase 31b

# ── PHASE 32a — StagingBuffer Tests ──────────────────────────────────────────
cat tasks/task-32a-staging-buffer-tests.md
# Verify: BUILD FAILED with errors for StagingBuffer, StagedChange, ChangeKind (expected)
# Commit: Phase 32a

# ── PHASE 32b — StagingBuffer Implementation ─────────────────────────────────
cat tasks/task-32b-staging-buffer.md
# Verify: BUILD SUCCEEDED; StagingBufferTests → 10 pass
# Commit: Phase 32b

# ── PHASE 33a — DiffEngine Tests ─────────────────────────────────────────────
cat tasks/task-33a-diff-engine-tests.md
# Verify: BUILD FAILED with errors for DiffEngine, DiffHunk, DiffLine (expected)
# Commit: Phase 33a

# ── PHASE 33b — DiffEngine + DiffPane ────────────────────────────────────────
cat tasks/task-33b-diff-pane.md
# Verify: BUILD SUCCEEDED; DiffEngineTests → 9 pass
# Commit: Phase 33b

# ── PHASE 34 — ChatView v2 (stop button + scroll lock) ───────────────────────
cat tasks/task-34-chatview-v2.md
# Verify: BUILD SUCCEEDED; stop button appears while streaming; scroll lock banner works
# Commit: Phase 34

# ── PHASE 35a — Inline Diff Comment Tests ────────────────────────────────────
cat tasks/task-35a-diff-comment-tests.md
# Verify: BUILD FAILED with errors for DiffComment, StagingBuffer.addComment (expected)
# Commit: Phase 35a

# ── PHASE 35b — Inline Diff Commenting ───────────────────────────────────────
cat tasks/task-35b-diff-comment.md
# Verify: BUILD SUCCEEDED; DiffCommentTests → 6 pass
# Commit: Phase 35b

# ── PHASE 36a — ConstitutionLoader Tests ─────────────────────────────────────────
cat tasks/task-36a-claude-md-tests.md
# Verify: BUILD FAILED with errors for ConstitutionLoader (expected)
# Commit: Phase 36a

# ── PHASE 36b — ConstitutionLoader Implementation ────────────────────────────────
cat tasks/task-36b-claude-md.md
# Verify: BUILD SUCCEEDED; ConstitutionLoaderTests → 8 pass
# Commit: Phase 36b

# ── PHASE 37a — Context Injection Tests ──────────────────────────────────────
cat tasks/task-37a-context-injection-tests.md
# Verify: BUILD FAILED with errors for ContextInjector, AttachmentError (expected)
# Commit: Phase 37a

# ── PHASE 37b — Context Injection Implementation ─────────────────────────────
cat tasks/task-37b-context-injection.md
# Verify: BUILD SUCCEEDED; ContextInjectionTests → 8 pass
# Commit: Phase 37b

# ── PHASE 38a — SkillsRegistry Tests ─────────────────────────────────────────
cat tasks/task-38a-skills-registry-tests.md
# Verify: BUILD FAILED with errors for SkillsRegistry, Skill, SkillFrontmatter (expected)
# Commit: Phase 38a

# ── PHASE 38b — SkillsRegistry Implementation ────────────────────────────────
cat tasks/task-38b-skills-registry.md
# Verify: BUILD SUCCEEDED; SkillsRegistryTests → 10 pass
# Commit: Phase 38b

# ── PHASE 39a — Skill Invocation Tests ───────────────────────────────────────
cat tasks/task-39a-skill-invocation-tests.md
# Verify: BUILD FAILED with errors for AgenticEngine.invokeSkill (expected)
# Commit: Phase 39a

# ── PHASE 39b — Skill Invocation + Built-in Skills ───────────────────────────
cat tasks/task-39b-skill-invocation.md
# Verify: BUILD SUCCEEDED; SkillInvocationTests → 4 pass
# Commit: Phase 39b

# ── PHASE 40a — MCPBridge Tests ──────────────────────────────────────────────
cat tasks/task-40a-mcp-bridge-tests.md
# Verify: BUILD FAILED with errors for MCPConfig, MCPServerConfig, MCPBridge (expected)
# Commit: Phase 40a

# ── PHASE 40b — MCPBridge Implementation ─────────────────────────────────────
cat tasks/task-40b-mcp-bridge.md
# Verify: BUILD SUCCEEDED; MCPBridgeTests → 9 pass
# Commit: Phase 40b

# ── PHASE 41a — SchedulerEngine Tests ────────────────────────────────────────
cat tasks/task-41a-scheduler-tests.md
# Verify: BUILD FAILED with errors for SchedulerEngine, ScheduledTask, ScheduleCadence (expected)
# Commit: Phase 41a

# ── PHASE 41b — SchedulerEngine Implementation ───────────────────────────────
cat tasks/task-41b-scheduler.md
# Verify: BUILD SUCCEEDED; SchedulerEngineTests → 6 pass
# Commit: Phase 41b

# ── PHASE 42a — PRMonitor Tests ──────────────────────────────────────────────
cat tasks/task-42a-pr-monitor-tests.md
# Verify: BUILD FAILED with errors for PRMonitor, PRStatus, ChecksState (expected)
# Commit: Phase 42a

# ── PHASE 42b — PRMonitor Implementation ─────────────────────────────────────
cat tasks/task-42b-pr-monitor.md
# Verify: BUILD SUCCEEDED; PRMonitorTests → 9 pass
# Commit: Phase 42b

# ── PHASE 43a — Connectors Tests ─────────────────────────────────────────────
cat tasks/task-43a-connectors-tests.md
# Verify: BUILD FAILED with errors for ConnectorCredentials, GitHubConnector (expected)
# Commit: Phase 43a

# ── PHASE 43b — Connectors Implementation ────────────────────────────────────
cat tasks/task-43b-connectors.md
# Verify: BUILD SUCCEEDED; ConnectorCredentialsTests → 4 pass; ConnectorProtocolTests → 5 pass
# Commit: Phase 43b

# ── DONE (v2) ─────────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 3
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 44a — TOMLDecoder Tests ────────────────────────────────────────────
cat tasks/task-44a-toml-decoder-tests.md
# Verify: BUILD FAILED with errors for TOMLDecoder, TOMLValue, TOMLLexer (expected)
# Commit: Phase 44a

# ── PHASE 44b — TOMLDecoder Implementation ───────────────────────────────────
cat tasks/task-44b-toml-decoder.md
# Verify: BUILD SUCCEEDED; TOMLDecoderTests → ~25 pass
# Commit: Phase 44b

# ── PHASE 45a — ToolRegistry Tests ───────────────────────────────────────────
cat tasks/task-45a-tool-registry-tests.md
# Verify: BUILD FAILED with errors for ToolRegistry (expected)
# Commit: Phase 45a

# ── PHASE 45b — ToolRegistry Implementation ──────────────────────────────────
cat tasks/task-45b-tool-registry.md
# Verify: BUILD SUCCEEDED; ToolRegistryTests → pass; migrated off ToolDefinitions.all count
# Commit: Phase 45b

# ── PHASE 46a — AppSettings Tests ────────────────────────────────────────────
cat tasks/task-46a-appsettings-tests.md
# Verify: BUILD FAILED with errors for AppSettings, SettingsProposal (expected)
# Commit: Phase 46a

# ── PHASE 46b — AppSettings + config.toml + Settings Window + Appearance ─────
cat tasks/task-46b-appsettings.md
# Verify: BUILD SUCCEEDED; AppSettingsTests → pass; Settings window opens via Cmd+,
# Commit: Phase 46b

# ── PHASE 47a — Memories Tests ───────────────────────────────────────────────
cat tasks/task-47a-memories-tests.md
# Verify: BUILD FAILED with errors for MemoryEngine, MemoryStore (expected)
# Commit: Phase 47a

# ── PHASE 47b — AI-Generated Memories ────────────────────────────────────────
cat tasks/task-47b-memories.md
# Verify: BUILD SUCCEEDED; MemoryEngineTests → pass
# Commit: Phase 47b

# ── PHASE 48a — Hooks Tests ──────────────────────────────────────────────────
cat tasks/task-48a-hooks-tests.md
# Verify: BUILD FAILED with errors for HookEngine, HookDefinition, HookDecision (expected)
# Commit: Phase 48a

# ── PHASE 48b — Hooks Implementation ─────────────────────────────────────────
cat tasks/task-48b-hooks.md
# Verify: BUILD SUCCEEDED; HookEngineTests → pass
# Commit: Phase 48b

# ── PHASE 49a — Thread Automations Tests ─────────────────────────────────────
cat tasks/task-49a-thread-automations-tests.md
# Verify: BUILD FAILED with errors for ThreadAutomation, SchedulerEngine.resume (expected)
# Commit: Phase 49a

# ── PHASE 49b — Thread Automations ───────────────────────────────────────────
cat tasks/task-49b-thread-automations.md
# Verify: BUILD SUCCEEDED; ThreadAutomationTests → pass
# Commit: Phase 49b

# ── PHASE 50a — Web Search Tests ─────────────────────────────────────────────
cat tasks/task-50a-web-search-tests.md
# Verify: BUILD FAILED with errors for WebSearchTool, BraveSearchClient (expected)
# Commit: Phase 50a

# ── PHASE 50b — Web Search Tool ──────────────────────────────────────────────
cat tasks/task-50b-web-search.md
# Verify: BUILD SUCCEEDED; WebSearchTests → pass
# Commit: Phase 50b

# ── PHASE 51 — Reasoning Effort + Personalization + Context Usage Indicator ──
cat tasks/task-51-agent-settings.md
# Verify: BUILD SUCCEEDED; reasoning effort picker renders; standing instructions inject
# Commit: Phase 51

# ── PHASE 52 — Toolbar Actions + Notifications ───────────────────────────────
cat tasks/task-52-toolbar-notifications.md
# Verify: BUILD SUCCEEDED; toolbar actions render; notifications fire on completion
# Commit: Phase 52

# ── PHASE 53 — Floating Pop-out Window + Voice Dictation ─────────────────────
cat tasks/task-53-popout-voice.md
# Verify: BUILD SUCCEEDED; thread detaches to floating window; Ctrl+M opens voice input
# Commit: Phase 53

# ── DONE (v3) ─────────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 4
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 54a — AgentDefinition + AgentRegistry Tests ─────────────────────────
cat tasks/task-54a-agent-definition-tests.md
# Verify: BUILD FAILED (AgentDefinition, AgentRole, AgentRegistry not defined)
# Commit: Phase 54a — AgentRegistryTests (failing)

# ── PHASE 54b — AgentDefinition + AgentRegistry Implementation ────────────────
cat tasks/task-54b-agent-definition.md
# Verify: BUILD SUCCEEDED; all AgentRegistryTests pass
# Commit: Phase 54b — AgentDefinition + AgentRegistry

# ── PHASE 55a — SubagentEngine V4a Tests ──────────────────────────────────────
cat tasks/task-55a-subagent-engine-tests.md
# Verify: BUILD FAILED (SubagentEngine, SubagentEvent not defined)
# Commit: Phase 55a — SubagentEngineTests (failing)

# ── PHASE 55b — SubagentEngine V4a Implementation ─────────────────────────────
cat tasks/task-55b-subagent-engine.md
# Verify: BUILD SUCCEEDED; all SubagentEngineTests pass
# Commit: Phase 55b — SubagentEngine V4a

# ── PHASE 56 — SubagentStream UI ──────────────────────────────────────────────
cat tasks/task-56-subagent-stream-ui.md
# Verify: BUILD SUCCEEDED; all SubagentBlockViewModelTests pass
# Commit: Phase 56 — SubagentStreamUI

# ── PHASE 57a — WorktreeManager Tests ─────────────────────────────────────────
cat tasks/task-57a-worktree-manager-tests.md
# Verify: BUILD FAILED (WorktreeManager, WorktreeError not defined)
# Commit: Phase 57a — WorktreeManagerTests (failing)

# ── PHASE 57b — WorktreeManager Implementation ────────────────────────────────
cat tasks/task-57b-worktree-manager.md
# Verify: BUILD SUCCEEDED; all WorktreeManagerTests pass
# Commit: Phase 57b — WorktreeManager

# ── PHASE 58a — WorkerSubagentEngine Tests ────────────────────────────────────
cat tasks/task-58a-subagent-worker-tests.md
# Verify: BUILD FAILED (WorkerSubagentEngine not defined)
# Commit: Phase 58a — WorkerSubagentEngineTests (failing)

# ── PHASE 58b — WorkerSubagentEngine Implementation ───────────────────────────
cat tasks/task-58b-subagent-worker.md
# Verify: BUILD SUCCEEDED; all WorkerSubagentEngineTests pass
# Commit: Phase 58b — WorkerSubagentEngine V4b

# ── PHASE 59 — SubagentSidebar UI ─────────────────────────────────────────────
cat tasks/task-59-subagent-sidebar-ui.md
# Verify: BUILD SUCCEEDED; all SubagentSidebarViewModelTests pass
# Commit: Phase 59 — SubagentSidebar UI

# ════════════════════════════════════════════════════════════════════════════
# VERSION 4 (continued) — Skills, Vision, Memory, Settings, Workspace, Wiring
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 60a — Skill Compaction Tests ───────────────────────────────────────
cat tasks/task-60a-skill-compaction-tests.md
# Verify: BUILD FAILED with errors for SkillCompactionEngine (expected)
# Commit: Phase 60a — SkillCompactionTests (failing)

# ── PHASE 60b — Skill Compaction Implementation ───────────────────────────────
cat tasks/task-60b-skill-compaction.md
# Verify: BUILD SUCCEEDED; SkillCompactionTests → pass
# Commit: Phase 60b — Skill Compaction

# ── PHASE 61a — Vision Attachment Tests ──────────────────────────────────────
cat tasks/task-61a-vision-attachment-tests.md
# Verify: BUILD FAILED with errors for ContextInjector vision methods (expected)
# Commit: Phase 61a — ContextInjectorVisionTests (failing)

# ── PHASE 61b — Vision Attachment Implementation ──────────────────────────────
cat tasks/task-61b-vision-attachment.md
# Verify: BUILD SUCCEEDED; ContextInjectorVisionTests → pass
# Commit: Phase 61b — Vision Attachment

# ── PHASE 62a — Memory Generation Tests ──────────────────────────────────────
cat tasks/task-62a-memory-generation-tests.md
# Verify: BUILD FAILED with errors for MemoryEngine generation methods (expected)
# Commit: Phase 62a — MemoryGenerationTests (failing)

# ── PHASE 62b — Memory Generation Implementation ─────────────────────────────
cat tasks/task-62b-memory-generation.md
# Verify: BUILD SUCCEEDED; MemoryGenerationTests → pass
# Commit: Phase 62b — Memory Generation

# ── PHASE 63a — Memory Injection Tests ───────────────────────────────────────
cat tasks/task-63a-memory-injection-tests.md
# Verify: BUILD FAILED with errors for MemoryEngine injection methods (expected)
# Commit: Phase 63a — MemoryInjectionTests (failing)

# ── PHASE 63b — Memory Injection Implementation ───────────────────────────────
cat tasks/task-63b-memory-injection.md
# Verify: BUILD SUCCEEDED; MemoryInjectionTests → pass
# Commit: Phase 63b — Memory Injection

# ── PHASE 64 — SettingsSection Enum ──────────────────────────────────────────
cat tasks/task-64-settings-section-enum.md
# Verify: BUILD SUCCEEDED; settings navigation includes all sections
# Commit: Phase 64 — SettingsSection Enum

# ── PHASE 65 — Agent Settings Section ────────────────────────────────────────
cat tasks/task-65-agent-settings.md
# Verify: BUILD SUCCEEDED; Agent settings section renders in Settings window
# Commit: Phase 65 — Agent Settings Section

# ── PHASE 66 — Memories Settings Section ─────────────────────────────────────
cat tasks/task-66-memories-settings.md
# Verify: BUILD SUCCEEDED; Memories settings section renders
# Commit: Phase 66 — Memories Settings Section

# ── PHASE 67 — MCP Settings Section ──────────────────────────────────────────
cat tasks/task-67-mcp-settings.md
# Verify: BUILD SUCCEEDED; MCP settings section renders
# Commit: Phase 67 — MCP Settings Section

# ── PHASE 68 — Skills Settings Section ───────────────────────────────────────
cat tasks/task-68-skills-settings.md
# Verify: BUILD SUCCEEDED; Skills settings section renders
# Commit: Phase 68 — Skills Settings Section

# ── PHASE 69 — Web Search Settings Section ───────────────────────────────────
cat tasks/task-69-search-settings.md
# Verify: BUILD SUCCEEDED; Web Search settings section renders
# Commit: Phase 69 — Web Search Settings Section

# ── PHASE 70 — Permissions Settings Section ──────────────────────────────────
cat tasks/task-70-permissions-settings.md
# Verify: BUILD SUCCEEDED; Permissions settings section renders
# Commit: Phase 70 — Permissions Settings Section

# ── PHASE 71 — Advanced + Connectors Settings ────────────────────────────────
cat tasks/task-71-advanced-connectors-settings.md
# Verify: BUILD SUCCEEDED; Advanced and Connectors settings sections render
# Commit: Phase 71 — Advanced + Connectors Settings

# ── PHASE 72a — WorkspaceLayoutManager Tests ─────────────────────────────────
cat tasks/task-72a-workspace-layout-tests.md
# Verify: BUILD FAILED with errors for WorkspaceLayoutManager (expected)
# Commit: Phase 72a — WorkspaceLayoutManagerTests (failing)

# ── PHASE 72b — WorkspaceLayoutManager Implementation ────────────────────────
cat tasks/task-72b-workspace-layout.md
# Verify: BUILD SUCCEEDED; WorkspaceLayoutManagerTests → pass
# Commit: Phase 72b — WorkspaceLayoutManager

# ── PHASE 73 — FilePane ───────────────────────────────────────────────────────
cat tasks/task-73-file-pane.md
# Verify: BUILD SUCCEEDED; FilePane renders inline file viewer
# Commit: Phase 73 — FilePane

# ── PHASE 74 — TerminalPane ───────────────────────────────────────────────────
cat tasks/task-74-terminal-pane.md
# Verify: BUILD SUCCEEDED; TerminalPane renders inline PTY terminal
# Commit: Phase 74 — TerminalPane

# ── PHASE 75 — PreviewPane ────────────────────────────────────────────────────
cat tasks/task-75-preview-pane.md
# Verify: BUILD SUCCEEDED; PreviewPane renders HTML/Markdown via WKWebView
# Commit: Phase 75 — PreviewPane

# ── PHASE 76 — SideChat ──────────────────────────────────────────────────────
cat tasks/task-76-side-chat.md
# Verify: BUILD SUCCEEDED; SideChat renders independent secondary chat panel
# Commit: Phase 76 — SideChat

# ── PHASE 77 — WorkspaceView Wiring ──────────────────────────────────────────
cat tasks/task-77-workspace-wiring.md
# Verify: BUILD SUCCEEDED; all panes wire into WorkspaceView with layout persistence
# Commit: Phase 77 — WorkspaceView Wiring

# ── PHASE 78 — Fix MerlinApp Settings Scene ──────────────────────────────────
cat tasks/task-78-fix-settings-scene.md
# Verify: BUILD SUCCEEDED; Settings window opens correctly from menu
# Commit: Phase 78 — Fix Settings Scene

# ── PHASE 79a — Subagent Chat Integration Tests ───────────────────────────────
cat tasks/task-79a-subagent-chat-tests.md
# Verify: BUILD FAILED with errors for subagent chat integration (expected)
# Commit: Phase 79a — SubagentChatIntegrationTests (failing)

# ── PHASE 79b — Subagent Chat Integration ────────────────────────────────────
cat tasks/task-79b-subagent-chat.md
# Verify: BUILD SUCCEEDED; SubagentChatIntegrationTests → pass
# Commit: Phase 79b — Subagent Chat Integration

# ── PHASE 80a — DisabledSkillNames Enforcement Tests ─────────────────────────
cat tasks/task-80a-disabled-skills-tests.md
# Verify: BUILD FAILED with errors for disabled skill enforcement (expected)
# Commit: Phase 80a — DisabledSkillNamesTests (failing)

# ── PHASE 80b — DisabledSkillNames Enforcement ───────────────────────────────
cat tasks/task-80b-disabled-skills.md
# Verify: BUILD SUCCEEDED; DisabledSkillNamesTests → pass
# Commit: Phase 80b — DisabledSkillNames Enforcement

# ── PHASE 81 — Scheduler Settings + Wiring ───────────────────────────────────
cat tasks/task-81-scheduler-settings.md
# Verify: BUILD SUCCEEDED; Scheduler settings section renders; SchedulerEngine wired
# Commit: Phase 81 — Scheduler Settings + Wiring

# ── PHASE 82 — ContextUsageTracker: Wire Into ProviderHUD ────────────────────
cat tasks/task-82-context-usage-indicator.md
# Verify: BUILD SUCCEEDED; context usage indicator appears in ProviderHUD
# Commit: Phase 82 — ContextUsageTracker

# ── PHASE 83 — Voice Dictation Button ────────────────────────────────────────
cat tasks/task-83-voice-dictation-button.md
# Verify: BUILD SUCCEEDED; microphone button appears in ChatView input area
# Commit: Phase 83 — Voice Dictation Button

# ── PHASE 84 — FloatingWindowManager ─────────────────────────────────────────
cat tasks/task-84-floating-window.md
# Verify: BUILD SUCCEEDED; floating window opens from menu item and keyboard shortcut
# Commit: Phase 84 — FloatingWindowManager

# ── PHASE 85 — ThreadAutomationEngine Wiring ─────────────────────────────────
cat tasks/task-85-thread-automations.md
# Verify: BUILD SUCCEEDED; ThreadAutomationEngine wired into LiveSession
# Commit: Phase 85 — ThreadAutomationEngine Wiring

# ── PHASE 86 — ToolbarActionStore Wiring ─────────────────────────────────────
cat tasks/task-86-toolbar-actions.md
# Verify: BUILD SUCCEEDED; toolbar actions render and fire from ChatView toolbar
# Commit: Phase 86 — ToolbarActionStore Wiring

# ── PHASE 87 — PRMonitor Wiring ───────────────────────────────────────────────
cat tasks/task-87-pr-monitor.md
# Verify: BUILD SUCCEEDED; PRMonitor wired into AppState
# Commit: Phase 87 — PRMonitor Wiring

# ── PHASE 88a — AppSettings Additions Tests ───────────────────────────────────
cat tasks/task-88a-appsettings-additions-tests.md
# Verify: BUILD FAILED with errors for keepAwake, permissionMode, notifications, messageDensity (expected)
# Commit: Phase 88a — AppSettingsAdditionsTests (failing)

# ── PHASE 88b — AppSettings Additions Implementation ─────────────────────────
cat tasks/task-88b-appsettings-additions.md
# Verify: BUILD SUCCEEDED; AppSettingsAdditionsTests → pass
# Commit: Phase 88b — AppSettings Additions

# ── PHASE 89 — General + Appearance Settings ─────────────────────────────────
cat tasks/task-89-settings-general-appearance.md
# Verify: BUILD SUCCEEDED; General and Appearance settings sections complete
# Commit: Phase 89 — General + Appearance Settings

# ── PHASE 90 — Advanced Settings ─────────────────────────────────────────────
cat tasks/task-90-advanced-settings.md
# Verify: BUILD SUCCEEDED; Advanced settings section complete
# Commit: Phase 90 — Advanced Settings

# ── PHASE 91 — Register Built-in Tools at Launch ─────────────────────────────
cat tasks/task-91-tool-registry-launch.md
# Verify: BUILD SUCCEEDED; all built-in tools registered via ToolRegistry at launch
# Commit: Phase 91 — Tool Registry Launch

# ── PHASE 92 — Apply messageDensity to ChatView ───────────────────────────────
cat tasks/task-92-message-density-chat.md
# Verify: BUILD SUCCEEDED; message density setting applied to ChatView rows
# Commit: Phase 92 — Message Density ChatView

# ── PHASE 93 — Keep Awake (IOPMAssertion) ────────────────────────────────────
cat tasks/task-93-keep-awake.md
# Verify: BUILD SUCCEEDED; IOPMAssertion held while keepAwake is enabled
# Commit: Phase 93 — Keep Awake

# ── PHASE 94 — Notifications Enabled Guard ───────────────────────────────────
cat tasks/task-94-notifications-enabled-guard.md
# Verify: BUILD SUCCEEDED; NotificationEngine gated on notificationsEnabled setting
# Commit: Phase 94 — Notifications Enabled Guard

# ── PHASE 95 — Default Permission Mode ───────────────────────────────────────
cat tasks/task-95-default-permission-mode.md
# Verify: BUILD SUCCEEDED; defaultPermissionMode applied to new sessions
# Commit: Phase 95 — Default Permission Mode

# ── PHASE 96 — AgentRegistry Launch Registration ─────────────────────────────
cat tasks/task-96-agent-registry-launch.md
# Verify: BUILD SUCCEEDED; AgentRegistry.registerBuiltins() called at launch
# Commit: Phase 96 — AgentRegistry Launch

# ── PHASE 97 — HookEngine Main Loop Wiring ───────────────────────────────────
cat tasks/task-97-hook-engine-main-loop.md
# Verify: BUILD SUCCEEDED; HookEngine wired into AgenticEngine main loop
# Commit: Phase 97 — HookEngine Main Loop Wiring

# ── PHASE 98 — Apply AppTheme + Font Settings to UI ──────────────────────────
cat tasks/task-98-appearance-application.md
# Verify: BUILD SUCCEEDED; AppTheme and font settings applied throughout UI
# Commit: Phase 98 — Appearance Application

# ── DONE (v4 complete) ────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 5 — Supervisor-Worker Multi-LLM + Domain Plugin System
# ════════════════════════════════════════════════════════════════════════════

# ── PHASE 99a — DomainRegistry + DomainPlugin Tests ───────────────────────────
cat tasks/task-99a-domain-registry-tests.md
# Verify: BUILD FAILED — DomainRegistry, DomainPlugin, DomainTaskType, DomainManifest, MCPDomainAdapter not defined (expected)
# Commit: Phase 99a — DomainRegistryTests + DomainManifestTests (failing)

# ── PHASE 99b — DomainRegistry + DomainPlugin + MCPDomainAdapter + SoftwareDomain ──
cat tasks/task-99b-domain-registry.md
# Verify: BUILD SUCCEEDED; DomainRegistryTests → 5 pass; DomainManifestTests → 2 pass
# Commit: Phase 99b — DomainRegistry + DomainPlugin + MCPDomainAdapter + SoftwareDomain

# ── PHASE 100a — AgenticEngine Role Slot Routing Tests ────────────────────────
cat tasks/task-100a-role-slot-routing-tests.md
# Verify: BUILD FAILED — AgentSlot, AgenticEngine slot init not defined (expected)
# Commit: Phase 100a — AgenticEngineSlotTests (failing)

# ── PHASE 100b — AgenticEngine Role Slot Routing ──────────────────────────────
cat tasks/task-100b-role-slot-routing.md
# Verify: BUILD SUCCEEDED; AgenticEngineSlotTests → 7 pass; zero warnings
# Commit: Phase 100b — AgenticEngine role slot routing (execute/reason/orchestrate/vision)

# ── PHASE 101a — ModelPerformanceTracker Tests ────────────────────────────────
cat tasks/task-101a-performance-tracker-tests.md
# Verify: BUILD FAILED — OutcomeSignals, ModelPerformanceTracker not defined (expected)
# Commit: Phase 101a — ModelPerformanceTrackerTests (failing)

# ── PHASE 101b — ModelPerformanceTracker ──────────────────────────────────────
cat tasks/task-101b-performance-tracker.md
# Verify: BUILD SUCCEEDED; ModelPerformanceTrackerTests → 6 pass; zero warnings
# Commit: Phase 101b — ModelPerformanceTracker

# ── PHASE 102a — CriticEngine Tests ───────────────────────────────────────────
cat tasks/task-102a-critic-engine-tests.md
# Verify: BUILD FAILED — CriticResult, CriticEngine, ShellRunning not defined (expected)
# Commit: Phase 102a — CriticEngineTests (failing)

# ── PHASE 102b — CriticEngine (Stage 1 + Stage 2) ────────────────────────────
cat tasks/task-102b-critic-engine.md
# Verify: BUILD SUCCEEDED; CriticEngineTests → 5 pass; zero warnings
# Commit: Phase 102b — CriticEngine (Stage 1 domain verification + Stage 2 reason slot)

# ── PHASE 103a — PlannerEngine Tests ──────────────────────────────────────────
cat tasks/task-103a-planner-tests.md
# Verify: BUILD FAILED — ComplexityTier, ClassifierResult, PlannerEngine, PlanStep not defined (expected)
# Commit: Phase 103a — PlannerEngineTests (failing)

# ── PHASE 103b — PlannerEngine ────────────────────────────────────────────────
cat tasks/task-103b-planner-engine.md
# Verify: BUILD SUCCEEDED; PlannerEngineTests → 7 pass; zero warnings
# Commit: Phase 103b — PlannerEngine

# ── PHASE 104a — System Prompt Addendum Tests ─────────────────────────────────
cat tasks/task-104a-system-prompt-addendum-tests.md
# Verify: BUILD FAILED — ProviderConfig.systemPromptAddendum, String.addendumHash, buildSystemPromptForTesting not defined (expected)
# Commit: Phase 104a — SystemPromptAddendumTests (failing)

# ── PHASE 104b — System Prompt Addendum ───────────────────────────────────────
cat tasks/task-104b-system-prompt-addendum.md
# Verify: BUILD SUCCEEDED; SystemPromptAddendumTests → 7 pass; all prior tests pass
# Commit: Phase 104b — system_prompt_addendum injection

# ── PHASE 105a — V5 AgenticEngine Run Loop Tests ──────────────────────────────
cat tasks/task-105a-v5-runloop-tests.md
# Verify: BUILD FAILED — protocols and engine test hooks not defined (expected)
# Commit: Phase 105a — AgenticEngineV5Tests (failing)

# ── PHASE 105b — V5 AgenticEngine Run Loop ────────────────────────────────────
cat tasks/task-105b-v5-runloop.md
# Verify: BUILD SUCCEEDED; AgenticEngineV5Tests → 6 pass; all prior tests pass
# Commit: Phase 105b — V5 AgenticEngine run loop (planner + critic + tracker + memory write)

# ── PHASE 106a — V5 Settings UI Tests ────────────────────────────────────────
cat tasks/task-106a-v5-settings-ui-tests.md
# Verify: BUILD FAILED — RoleSlotSettingsView, PerformanceDashboardView, AppSettings new properties not defined (expected)
# Commit: Phase 106a — V5SettingsUITests (failing)

# ── PHASE 106b — V5 Settings UI ──────────────────────────────────────────────
cat tasks/task-106b-v5-settings-ui.md
# Verify: BUILD SUCCEEDED; V5SettingsUITests → all pass; Settings UI renders
# Commit: Phase 106b — V5 Settings UI (role slot assignment + domain selector + performance dashboard)

# ── PHASE 107a — V5 Skill Frontmatter Tests ───────────────────────────────────
cat tasks/task-107a-skill-frontmatter-v5-tests.md
# Verify: BUILD FAILED — SkillFrontmatter.role, SkillFrontmatter.complexity not defined (expected)
# Commit: Phase 107a — SkillFrontmatterV5Tests (failing)

# ── PHASE 107b — V5 Skill Frontmatter ─────────────────────────────────────────
cat tasks/task-107b-skill-frontmatter-v5.md
# Verify: BUILD SUCCEEDED; SkillFrontmatterV5Tests → 6 pass; zero warnings
# Commit: Phase 107b — Skill frontmatter role: and complexity: declarations

# ── DONE (v5 core) ────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# VERSION 5 — RAG Memory Extension
# ════════════════════════════════════════════════════════════════════════════
# Prereq: xcalibre Phase 18 shipped (POST /api/v1/memory, GET /api/v1/search/chunks?source=all)

# ── PHASE 108a — RAG Source Attribution Tests ─────────────────────────────────
cat tasks/task-108a-rag-source-attribution-tests.md
# Verify: BUILD FAILED — AgentEvent.ragSources not defined; RAGSourcesView not defined (expected)
# Commit: Phase 108a — RAGSourceAttributionTests (failing)

# ── PHASE 108b — RAG Source Attribution ───────────────────────────────────────
cat tasks/task-108b-rag-source-attribution.md
# Verify: BUILD SUCCEEDED; RAGSourceAttributionTests → 4 pass; all prior tests pass
# Commit: Phase 108b — RAG source attribution (.ragSources event + Sources footer in chat)

# ── PHASE 109a — Project Path AppSettings Tests ───────────────────────────────
cat tasks/task-109a-project-path-tests.md
# Verify: BUILD FAILED — AppSettings.projectPath not defined; serializedTOML/applyTOML mismatch (expected)
# Commit: Phase 109a — ProjectPathSettingsTests (failing)

# ── PHASE 109b — Project Path AppSettings Wiring ──────────────────────────────
cat tasks/task-109b-project-path.md
# Verify: BUILD SUCCEEDED; ProjectPathSettingsTests → all pass; all prior tests pass
# Commit: Phase 109b — AppSettings.projectPath wired into engine and Settings UI

# ── PHASE 110a — Memory Browser Tests ─────────────────────────────────────────
cat tasks/task-110a-memory-browser-tests.md
# Verify: BUILD FAILED — XcalibreClient.searchMemory not defined; MemoryBrowserView not defined (expected)
# Commit: Phase 110a — MemoryBrowserTests (failing)

# ── PHASE 110b — Memory Browser ───────────────────────────────────────────────
cat tasks/task-110b-memory-browser.md
# Verify: BUILD SUCCEEDED; MemoryBrowserTests → 5 pass; all prior tests pass
# Commit: Phase 110b — Memory browser (searchMemory convenience + MemoryBrowserView)

# ── PHASE 111a — rag_search Tool Source/ProjectPath Tests ─────────────────────
cat tasks/task-111a-rag-search-tool-tests.md
# Verify: BUILD FAILED — RAGTools.search signature mismatch; Args.source not defined (expected)
# Commit: Phase 111a — RAGSearchToolTests (failing)

# ── PHASE 111b — rag_search Tool Source/ProjectPath ───────────────────────────
cat tasks/task-111b-rag-search-tool.md
# Verify: BUILD SUCCEEDED; RAGSearchToolTests → 6 pass; all prior tests pass
# Commit: Phase 111b — rag_search tool: source + project_path parameters

# ── PHASE 112a — RAG Settings Tests ──────────────────────────────────────────
cat tasks/task-112a-rag-settings-tests.md
# Verify: BUILD FAILED — AppSettings.ragRerank, AppSettings.ragChunkLimit not defined (expected)
# Commit: Phase 112a — RAGSettingsTests (failing)

# ── PHASE 112b — RAG Settings ─────────────────────────────────────────────────
cat tasks/task-112b-rag-settings.md
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
cat tasks/task-113a-outcome-record-persistence-tests.md
# Verify: BUILD FAILED — ModelPerformanceTracker.records(for:taskType:) and
#         ModelPerformanceTracker.exportTrainingData(minScore:) not defined (expected)
# Commit: Phase 113a — OutcomeRecordPersistenceTests (failing)

# ── PHASE 113b — OutcomeRecord Persistence ────────────────────────────────────
cat tasks/task-113b-outcome-record-persistence.md
# Verify: BUILD SUCCEEDED; OutcomeRecordPersistenceTests → 6 pass; all prior tests pass
# Commit: Phase 113b — OutcomeRecord persistence (V6 training data survives restarts)

# ── PHASE 114a — StagingBuffer OutcomeSignals Tests ───────────────────────────
cat tasks/task-114a-staging-buffer-signals-tests.md
# Verify: BUILD FAILED — StagingBuffer.acceptedCount, rejectedCount,
#         editedOnAcceptCount, resetSessionCounts() not defined (expected)
# Commit: Phase 114a — StagingBufferSignalsTests (failing)

# ── PHASE 114b — StagingBuffer OutcomeSignals Wiring ──────────────────────────
cat tasks/task-114b-staging-buffer-signals.md
# Verify: BUILD SUCCEEDED; StagingBufferSignalsTests → 9 pass; all prior tests pass
# Commit: Phase 114b — StagingBuffer accept/reject wired into OutcomeSignals

# ── PHASE 115a — Critic-Gated Memory Tests ────────────────────────────────────
cat tasks/task-115a-critic-gated-memory-tests.md
# Verify: BUILD FAILED — AgenticEngine.lastCriticVerdict not defined (expected)
# Commit: Phase 115a — CriticGatedMemoryTests (failing)

# ── PHASE 115b — Critic-Gated Memory Write ────────────────────────────────────
cat tasks/task-115b-critic-gated-memory.md
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
cat tasks/task-116a-lora-appsettings-tests.md
# Verify: BUILD FAILED — AppSettings.loraEnabled (and 6 other properties) not defined (expected)
# Commit: Phase 116a — LoRASettingsTests (failing)

# ── PHASE 116b — LoRA AppSettings ────────────────────────────────────────────
cat tasks/task-116b-lora-appsettings.md
# Verify: BUILD SUCCEEDED; LoRASettingsTests → 10 pass; all prior tests pass
# Commit: Phase 116b — LoRA AppSettings (loraEnabled + 6 sub-settings, [lora] TOML section)

# ── PHASE 117a — OutcomeRecord Training Fields Tests ─────────────────────────
cat tasks/task-117a-outcome-record-training-fields-tests.md
# Verify: BUILD FAILED — OutcomeRecord.prompt, OutcomeRecord.response not defined (expected)
# Commit: Phase 117a — OutcomeRecordTrainingFieldsTests (failing)

# ── PHASE 117b — OutcomeRecord Training Fields ────────────────────────────────
cat tasks/task-117b-outcome-record-training-fields.md
# Verify: BUILD SUCCEEDED; OutcomeRecordTrainingFieldsTests → 6 pass; all prior tests pass
# Commit: Phase 117b — OutcomeRecord prompt/response fields; record() captures conversation text

# ── PHASE 118a — LoRATrainer Tests ───────────────────────────────────────────
cat tasks/task-118a-lora-trainer-tests.md
# Verify: BUILD FAILED — LoRATrainer, LoRATrainingResult, ShellRunnerProtocol not defined (expected)
# Commit: Phase 118a — LoRATrainerTests (failing)

# ── PHASE 118b — LoRATrainer ──────────────────────────────────────────────────
cat tasks/task-118b-lora-trainer.md
# Verify: BUILD SUCCEEDED; LoRATrainerTests → 5 pass; all prior tests pass
# Commit: Phase 118b — LoRATrainer (JSONL export + mlx_lm.lora shell invocation)

# ── PHASE 119a — LoRACoordinator Tests ───────────────────────────────────────
cat tasks/task-119a-lora-coordinator-tests.md
# Verify: BUILD FAILED — LoRACoordinator not defined (expected)
# Commit: Phase 119a — LoRACoordinatorTests (failing)

# ── PHASE 119b — LoRACoordinator ─────────────────────────────────────────────
cat tasks/task-119b-lora-coordinator.md
# Verify: BUILD SUCCEEDED; LoRACoordinatorTests → 4 pass; all prior tests pass
# Commit: Phase 119b — LoRACoordinator (threshold-gated auto-train trigger, concurrent-safe)

# ── PHASE 120a — LoRA Provider Routing Tests ─────────────────────────────────
cat tasks/task-120a-lora-provider-routing-tests.md
# Verify: BUILD FAILED — AgenticEngine.loraProvider not defined (expected)
# Commit: Phase 120a — LoRAProviderRoutingTests (failing)

# ── PHASE 120b — LoRA Provider Routing ───────────────────────────────────────
cat tasks/task-120b-lora-provider-routing.md
# Verify: BUILD SUCCEEDED; LoRAProviderRoutingTests → 4 pass; all prior tests pass
# Commit: Phase 120b — LoRA provider routing (execute slot → mlx_lm.server when adapter loaded)

# ── PHASE 121a — LoRA Settings UI Tests ──────────────────────────────────────
cat tasks/task-121a-lora-settings-ui-tests.md
# Verify: BUILD FAILED — LoRASettingsSection not defined (expected)
# Commit: Phase 121a — LoRASettingsUITests (failing)

# ── PHASE 121b — LoRA Settings UI ────────────────────────────────────────────
cat tasks/task-121b-lora-settings-ui.md
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
cat tasks/task-123a-sampling-params-tests.md
# Verify: BUILD FAILED — CompletionRequest.topK etc. not defined (expected)
# Commit: Phase 123a — CompletionRequestSamplingParamsTests (failing)

# ── PHASE 123b — Sampling Params Implementation ───────────────────────────────
cat tasks/task-123b-sampling-params.md
# Verify: BUILD SUCCEEDED; CompletionRequestSamplingParamsTests → 13 pass; all prior tests pass
# Commit: Phase 123b — expand CompletionRequest with 8 sampling params; AppSettings inference defaults

# ── PHASE 124a — ModelParameterAdvisor Tests ─────────────────────────────────
cat tasks/task-124a-parameter-advisor-tests.md
# Verify: BUILD FAILED — ModelParameterAdvisor, ParameterAdvisory not defined (expected)
# Commit: Phase 124a — ModelParameterAdvisorTests (failing)

# ── PHASE 124b — ModelParameterAdvisor Implementation ────────────────────────
cat tasks/task-124b-parameter-advisor.md
# Verify: BUILD SUCCEEDED; ModelParameterAdvisorTests → 12 pass; all prior tests pass
# Commit: Phase 124b — ModelParameterAdvisor (truncation, variance, repetition, context overflow)

# ── V6 LOOSE END — Memory → xcalibre RAG indexing ────────────────────────────
# ── PHASE 122a — Memory Xcalibre Index Tests ─────────────────────────────────
cat tasks/task-122a-memory-xcalibre-index-tests.md
# Verify: BUILD FAILED — MemoryEngine has no setXcalibreClient method (expected)
# Commit: Phase 122a — MemoryXcalibreIndexTests (failing)

# ── PHASE 122b — Memory Xcalibre Index ───────────────────────────────────────
cat tasks/task-122b-memory-xcalibre-index.md
# Verify: BUILD SUCCEEDED; MemoryXcalibreIndexTests → 6 pass; all prior tests pass
# Commit: Phase 122b — approved memories indexed in xcalibre-server as factual RAG chunks

# ── V7 Local Model Management ─────────────────────────────────────────────────
# Unified LocalModelManagerProtocol across all 6 local providers (LM Studio, Ollama,
# Jan, LocalAI, Mistral.rs, vLLM-Metal). Runtime reload where supported; restart instructions
# where not. AppState registry + ApplyAdvisory routing. ModelControlView UI.

# ── PHASE 125a — LocalModelManagerProtocol Tests ─────────────────────────────
cat tasks/task-125a-local-model-manager-protocol-tests.md
# Verify: BUILD FAILED — LocalModelManagerProtocol, LoadParam, LocalModelConfig etc. not defined (expected)
# Commit: Phase 125a — LocalModelManagerProtocolTests (failing)

# ── PHASE 125b — LocalModelManagerProtocol + LMStudio + Ollama ───────────────
cat tasks/task-125b-local-model-manager-protocol.md
# Verify: BUILD SUCCEEDED; LocalModelManagerProtocolTests → 22 pass; all prior tests pass
# Commit: Phase 125b — LocalModelManagerProtocol + LMStudioModelManager + OllamaModelManager

# ── PHASE 126a — Extended Provider Manager Tests ─────────────────────────────
cat tasks/task-126a-local-model-manager-extended-tests.md
# Verify: BUILD FAILED — JanModelManager, LocalAIModelManager, MistralRSModelManager, VLLMModelManager not defined (expected)
# Commit: Phase 126a — LocalModelManagerExtendedTests (failing)

# ── PHASE 126b — Jan, LocalAI, MistralRS, vLLM-Metal Managers ─────────────────────
cat tasks/task-126b-local-model-manager-extended.md
# Verify: BUILD SUCCEEDED; LocalModelManagerExtendedTests → 20 pass; all prior tests pass
# Commit: Phase 126b — Jan/LocalAI/MistralRS/vLLM-Metal model managers

# ── PHASE 127a — Model Manager Wiring Tests ──────────────────────────────────
cat tasks/task-127a-model-manager-wiring-tests.md
# Verify: BUILD FAILED — AppState.localModelManagers, applyAdvisory, AgenticEngine.isReloadingModel not defined (expected)
# Commit: Phase 127a — ModelManagerWiringTests (failing)

# ── PHASE 127b — Model Manager Wiring ────────────────────────────────────────
cat tasks/task-127b-model-manager-wiring.md
# Verify: BUILD SUCCEEDED; ModelManagerWiringTests → 9 pass; all prior tests pass
# Commit: Phase 127b — model manager wiring: AppState registry, applyAdvisory, engine reload pause

# ── PHASE 128a — Model Control UI Tests ──────────────────────────────────────
cat tasks/task-128a-model-control-ui-tests.md
# Verify: BUILD FAILED — ModelControlView, RestartInstructionsSheet, ModelControlSectionView not defined (expected)
# Commit: Phase 128a — ModelControlViewTests (failing)

# ── PHASE 128b — Model Control UI ────────────────────────────────────────────
cat tasks/task-128b-model-control-ui.md
# Verify: BUILD SUCCEEDED; ModelControlViewTests → 6 pass; all prior tests pass
# Commit: Phase 128b — ModelControlView: per-provider load param editor + restart instructions sheet

# ── PHASE 132 — V7 Documentation & Code Comment Update ───────────────────────
cat tasks/task-132-v7-docs.md
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
cat tasks/task-129a-calibration-runner-tests.md
# Verify: BUILD FAILED — CalibrationCategory, CalibrationPrompt, CalibrationResponse,
#         CalibrationReport, CalibrationSuite, CalibrationRunner not defined (expected)
# Commit: Phase 129a — CalibrationRunnerTests (failing)

# ── PHASE 129b — CalibrationRunner Implementation ────────────────────────────
cat tasks/task-129b-calibration-runner.md
# Verify: BUILD SUCCEEDED; CalibrationRunnerTests → 14 pass; all prior tests pass
# Commit: Phase 129b — CalibrationTypes + CalibrationSuite (18-prompt battery) + CalibrationRunner

# ── PHASE 130a — CalibrationAdvisor Tests ────────────────────────────────────
cat tasks/task-130a-calibration-advisor-tests.md
# Verify: BUILD FAILED — CalibrationAdvisor, CategoryScores not defined (expected)
# Commit: Phase 130a — CalibrationAdvisorTests (failing)

# ── PHASE 130b — CalibrationAdvisor Implementation ───────────────────────────
cat tasks/task-130b-calibration-advisor.md
# Verify: BUILD SUCCEEDED; CalibrationAdvisorTests → 14 pass; all prior tests pass
# Commit: Phase 130b — CalibrationAdvisor: maps score gaps to ParameterAdvisory

# ── PHASE 131a — Calibration Skill & UI Tests ────────────────────────────────
cat tasks/task-131a-calibration-skill-tests.md
# Verify: BUILD FAILED — CalibrationCoordinator, CalibrationSheet, CalibrationProgressInfo,
#         CalibrationProviderPickerView, CalibrationProgressView, CalibrationReportView,
#         AppState.calibrationCoordinator not defined (expected)
# Commit: Phase 131a — CalibrationSkillTests (failing)

# ── PHASE 131b — Calibration Skill & UI Implementation ───────────────────────
cat tasks/task-131b-calibration-skill.md
# Verify: BUILD SUCCEEDED; CalibrationSkillTests → 9 pass; all prior tests pass
# Commit: Phase 131b — /calibrate skill: provider picker, runner wiring, report view with apply-all

# ── PHASE 133 — V8 Documentation & Code Comment Update ───────────────────────
cat tasks/task-133-v8-docs.md
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
Read tasks/task-134a-memory-backend-plugin-tests.md and execute.
# Verify: BUILD FAILED — MemoryChunk, MemorySearchResult, MemoryBackendPlugin,
#         MemoryBackendRegistry, NullMemoryPlugin not defined (expected)
# Commit: Phase 134a — MemoryBackendPlugin tests (failing)

# ── PHASE 134b — MemoryBackendPlugin Protocol Implementation ─────────────────
Read tasks/task-134b-memory-backend-plugin.md and execute.
# Verify: BUILD SUCCEEDED; all 134a tests pass; zero warnings
# Commit: Phase 134b — MemoryBackendPlugin: protocol, registry, NullMemoryPlugin

# ── PHASE 135a — LocalVectorPlugin Tests ─────────────────────────────────────
Read tasks/task-135a-local-vector-plugin-tests.md and execute.
# Verify: BUILD FAILED — EmbeddingProviderProtocol, LocalVectorPlugin not defined (expected)
# Commit: Phase 135a — LocalVectorPlugin tests (failing)

# ── PHASE 135b — LocalVectorPlugin Implementation ────────────────────────────
Read tasks/task-135b-local-vector-plugin.md and execute.
# Verify: BUILD SUCCEEDED; all 135a tests pass; zero warnings
# Commit: Phase 135b — LocalVectorPlugin: SQLite + NLContextualEmbedding cosine search

# ── PHASE 136a — MemoryEngine Backend Wiring Tests ───────────────────────────
Read tasks/task-136a-memory-engine-backend-wiring-tests.md and execute.
# Verify: BUILD FAILED — MemoryEngine.setMemoryBackend not defined (expected)
# Commit: Phase 136a — MemoryEngine backend wiring tests (failing)

# ── PHASE 136b — MemoryEngine Backend Wiring ─────────────────────────────────
Read tasks/task-136b-memory-engine-backend-wiring.md and execute.
# Verify: BUILD SUCCEEDED; all 136a tests pass; zero warnings
# Commit: Phase 136b — MemoryEngine: replace xcalibre write with MemoryBackendPlugin

# ── PHASE 137a — AgenticEngine Memory Plugin Tests ───────────────────────────
Read tasks/task-137a-agenticengine-memory-plugin-tests.md and execute.
# Verify: BUILD FAILED — AgenticEngine.setMemoryBackend not defined (expected)
# Commit: Phase 137a — AgenticEngine memory plugin tests (failing)

# ── PHASE 137b — AgenticEngine Memory Plugin Wiring ──────────────────────────
Read tasks/task-137b-agenticengine-memory-plugin.md and execute.
# Verify: BUILD SUCCEEDED; all 137a tests pass; zero warnings
# Commit: Phase 137b — AgenticEngine: local memory plugin for writes + merged RAG search

# ── PHASE 138a — Memory Backend AppSettings Wiring Tests ─────────────────────
Read tasks/task-138a-memory-backend-appsettings-tests.md and execute.
# Verify: BUILD FAILED — AppSettings.memoryBackendID, AppState.memoryRegistry not defined (expected)
# Commit: Phase 138a — memory backend AppSettings wiring tests (failing)

# ── PHASE 138b — Memory Backend AppSettings Wiring ───────────────────────────
Read tasks/task-138b-memory-backend-appsettings.md and execute.
# Verify: BUILD SUCCEEDED; all 138a tests pass; zero warnings
# Commit: Phase 138b — AppSettings.memoryBackendID + AppState memory registry wiring

# ── PHASE 139 — V9 Documentation & Code Comment Update ───────────────────────
Read tasks/task-139-v9-docs.md and execute.
# Verify: BUILD SUCCEEDED; zero warnings; all prior tests pass
# Commit: Phase 139 — V9 docs + code comments: local memory store plugin system

# ── PHASE 140a — Circuit Breaker Tests ───────────────────────────────────────
Read tasks/task-140a-circuit-breaker-tests.md and execute.
# Verify: BUILD FAILED — AgenticEngine.consecutiveCriticFailures,
#         AppSettings.agentCircuitBreakerThreshold not defined (expected)
# Commit: Phase 140a — circuit breaker tests (failing)

# ── PHASE 140b — Circuit Breaker Implementation ───────────────────────────────
Read tasks/task-140b-circuit-breaker.md and execute.
# Verify: BUILD SUCCEEDED; all 140a tests pass; zero warnings
# Commit: Phase 140b — reasoning-layer circuit breaker: warn after N consecutive critic failures

# ── PHASE 141a — Grounding Confidence Tests ──────────────────────────────────
Read tasks/task-141a-grounding-confidence-tests.md and execute.
# Verify: BUILD FAILED — GroundingReport, AgentEvent.groundingReport,
#         AppSettings.ragFreshnessThresholdDays, AppSettings.ragMinGroundingScore not defined (expected)
# Commit: Phase 141a — grounding confidence signal tests (failing)

# ── PHASE 141b — Grounding Confidence Implementation ─────────────────────────
Read tasks/task-141b-grounding-confidence.md and execute.
# Verify: BUILD SUCCEEDED; all 141a tests pass; zero warnings
# Commit: Phase 141b — GroundingReport: per-turn grounding confidence signal

# ── PHASE 142a — Semantic Fault Injection Tests ──────────────────────────────
Read tasks/task-142a-semantic-fault-injection-tests.md and execute.
# Verify: BUILD FAILED — StalenessInjectingMemoryBackend, TruncatingMockProvider,
#         EmptyToolResultRouter, DroppingContextManager not defined (expected)
# Commit: Phase 142a — semantic fault injection tests (failing)

# ── PHASE 142b — Semantic Fault Injection Implementation ─────────────────────
Read tasks/task-142b-semantic-fault-injection.md and execute.
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
Read tasks/task-143a-dynamic-model-fetch-tests.md and execute.
# Verify: BUILD FAILED — dynamic model fetch symbols not defined (expected)
# Commit: Phase 143a — dynamic model fetch tests (failing)

# ── PHASE 143b — Dynamic Model Fetch ─────────────────────────────────────────
Read tasks/task-143b-dynamic-model-fetch.md and execute.
# Verify: BUILD SUCCEEDED; all 143a tests pass; zero warnings
# Commit: Phase 143b — Dynamic model fetch

# ── PHASE 144a — Virtual Provider ID Tests ───────────────────────────────────
Read tasks/task-144a-virtual-provider-id-tests.md and execute.
# Verify: BUILD FAILED — VirtualProviderID symbols not defined (expected)
# Commit: Phase 144a — virtual provider ID tests (failing)

# ── PHASE 144b — Virtual Provider IDs ────────────────────────────────────────
Read tasks/task-144b-virtual-provider-id.md and execute.
# Verify: BUILD SUCCEEDED; all 144a tests pass; zero warnings
# Commit: Phase 144b — Virtual provider IDs, delete LMStudioProvider

# ── PHASE 145a — Provider Routing Cleanup Tests ──────────────────────────────
Read tasks/task-145a-provider-routing-cleanup-tests.md and execute.
# Verify: BUILD FAILED — routing cleanup symbols not defined (expected)
# Commit: Phase 145a — provider routing cleanup tests (failing)

# ── PHASE 145b — Provider Routing Cleanup ────────────────────────────────────
Read tasks/task-145b-provider-routing-cleanup.md and execute.
# Verify: BUILD SUCCEEDED; all 145a tests pass; zero warnings
# Commit: Phase 145b — Remove proProvider/flashProvider/visionProvider, simplify routing

# ── PHASE 146a — Provider Settings UI Tests ──────────────────────────────────
Read tasks/task-146a-provider-settings-ui-tests.md and execute.
# Verify: BUILD FAILED — ProviderSettingsView symbols not defined (expected)
# Commit: Phase 146a — provider settings UI tests (failing)

# ── PHASE 146b — Provider Settings UI ────────────────────────────────────────
Read tasks/task-146b-provider-settings-ui.md and execute.
# Verify: BUILD SUCCEEDED; all 146a tests pass; zero warnings
# Commit: Phase 146b — Provider settings UI with dynamic model picker

# ── PHASE 147a — Adaptive Loop Ceiling Tests ─────────────────────────────────
Read tasks/task-147a-adaptive-loop-ceiling-tests.md and execute.
# Verify: BUILD FAILED — adaptive ceiling symbols not defined (expected)
# Commit: Phase 147a — adaptive loop ceiling tests (failing)

# ── PHASE 147b — Adaptive Loop Ceiling ───────────────────────────────────────
Read tasks/task-147b-adaptive-loop-ceiling.md and execute.
# Verify: BUILD SUCCEEDED; all 147a tests pass; zero warnings
# Commit: Phase 147b — Adaptive loop ceiling based on project size

# ── PHASE 148a — Document Verification Tests ─────────────────────────────────
Read tasks/task-148a-document-verification-tests.md and execute.
# Verify: BUILD FAILED — document verification symbols not defined (expected)
# Commit: Phase 148a — document verification tests (failing)

# ── PHASE 148b — Document Verification ───────────────────────────────────────
Read tasks/task-148b-document-verification.md and execute.
# Verify: BUILD SUCCEEDED; all 148a tests pass; zero warnings
# Commit: Phase 148b — Two-tier document verification (truncation fix, firing condition, structured prompt, verdict parsing)

# ── PHASE 149a — LM Studio Context Auto-Resize Tests ─────────────────────────
Read tasks/task-149a-lmstudio-context-autoresize-tests.md and execute.
# Verify: BUILD FAILED — ensureContextLength not defined (expected)
# Commit: Phase 149a — LM Studio context auto-resize tests (failing)

# ── PHASE 149b — LM Studio Context Auto-Resize ───────────────────────────────
Read tasks/task-149b-lmstudio-context-autoresize.md and execute.
# Verify: BUILD SUCCEEDED; all 149a tests pass; zero warnings
# Commit: Phase 149b — LM Studio context auto-resize

# ── PHASE 150a — Loop Continuation Tests ─────────────────────────────────────
Read tasks/task-150a-loop-continuation-tests.md and execute.
# Verify: BUILD SUCCEEDED; tests compile but LoopContinuationTests fail at runtime (expected)
# Commit: Phase 150a — LoopContinuationTests (failing)

# ── PHASE 150b — Loop Continuation and Near-Ceiling Warning ──────────────────
Read tasks/task-150b-loop-continuation.md and execute.
# Verify: BUILD SUCCEEDED; all 6 LoopContinuationTests pass; zero warnings
# Commit: Phase 150b — loop continuation and near-ceiling warning

# ── PHASE 166a — WKWebView Chat Renderer Tests ───────────────────────────────
Read tasks/task-166a-wkwebview-chat-tests.md and execute.
# Verify: BUILD FAILED — ConversationHTMLRenderer type missing (expected)
# Commit: Phase 166a — ConversationHTMLRendererTests (failing)

# ── PHASE 166b — WKWebView Chat Renderer Implementation ──────────────────────
Read tasks/task-166b-wkwebview-chat.md and execute.
# Verify: BUILD SUCCEEDED; all ConversationHTMLRendererTests pass
# Manual: drag-select text across multiple messages works
# Commit: Phase 166b — WKWebView conversation renderer (cross-message selection)

# ── V1.5 — Session History & Archive ─────────────────────────────────────────

# ── PHASE 181a — Session Archive Tests ───────────────────────────────────────
Read tasks/task-181a-session-archive-tests.md and execute.
# Verify: BUILD FAILED — Session.archived, SessionStore.scopedDirectoryName,
#         archive/unarchive, activeSessions, archivedSessions,
#         migrateLegacyIfNeeded not found (expected)
# Commit: Phase 181a — SessionArchiveTests (failing)

# ── PHASE 181b — Session Archive Implementation ───────────────────────────────
Read tasks/task-181b-session-archive.md and execute.
# Verify: BUILD SUCCEEDED; all SessionArchiveTests pass
# Commit: Phase 181b — Session.archived + SessionStore project-scoped path + archive/unarchive

# ── PHASE 182a — Session Restore Tests ───────────────────────────────────────
Read tasks/task-182a-session-restore-tests.md and execute.
# Verify: BUILD FAILED — ContextManager.load, SessionManager.restore,
#         SessionManager.sessionStore not found (expected)
# Commit: Phase 182a — SessionRestoreTests (failing)

# ── PHASE 182b — Session Restore Implementation ───────────────────────────────
Read tasks/task-182b-session-restore.md and execute.
# Verify: BUILD SUCCEEDED; all SessionRestoreTests pass
# Commit: Phase 182b — ContextManager.load + LiveSession initial messages + SessionManager.restore

# ── PHASE 183a — Session Sidebar Helper Tests ─────────────────────────────────
Read tasks/task-183a-session-sidebar-tests.md and execute.
# Verify: BUILD FAILED — RelativeTimestampFormatter not found (expected)
# Commit: Phase 183a — SessionSidebarHelpersTests (failing)

# ── PHASE 183b — Session Sidebar Implementation ───────────────────────────────
Read tasks/task-183b-session-sidebar.md and execute.
# Verify: BUILD SUCCEEDED; all SessionSidebarHelpersTests pass
# Manual: Prior Sessions section visible, archive/recall context menus work,
#         timestamps display correctly, Resume opens live session with history
# Commit: Phase 183b — SessionSidebar Prior Sessions + archive/recall + timestamps

# ── PHASE 184 — Version Bump to v1.5.0 ───────────────────────────────────────
Read tasks/task-184-version-bump-v1-5.md and execute.
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
Read tasks/task-185a-workspace-coordinator-tests.md and execute.
# Verify: BUILD FAILED — WorkspaceCoordinator not found (expected)
# Commit: Phase 185a — WorkspaceCoordinatorTests (failing)

# ── PHASE 185b — WorkspaceCoordinator Implementation ─────────────────────────
Read tasks/task-185b-workspace-coordinator.md and execute.
# Verify: BUILD SUCCEEDED; all WorkspaceCoordinatorTests pass
# Commit: Phase 185b — WorkspaceCoordinator: multi-project state, persistence, activeProjectManager

# ── PHASE 186b — Multi-Project UI ────────────────────────────────────────────
Read tasks/task-186b-multiproject-ui.md and execute.
# Verify: BUILD SUCCEEDED, zero warnings
# Manual: single workspace window; picker sheet on first launch; project sections
#   in sidebar; project header popover (New Session / Close Project); terminal
#   and side chat follow active project; relaunch restores all open projects;
#   Cmd+N opens picker sheet
# Commit: Phase 186b — Single-window multi-project: coordinator-driven UI, picker sheet, persistence

# ── PHASE 187a — Session Title Tests ─────────────────────────────────────────
Read tasks/task-187a-session-title-tests.md and execute.
# Verify: BUILD FAILED — AgenticEngine.onTitleUpdate / applyTitleUpdateIfNeeded not found (expected)
# Commit: Phase 187a — SessionTitleTests (failing)

# ── PHASE 187b — Session Title Auto-Labeling ──────────────────────────────────
Read tasks/task-187b-session-title.md and execute.
# Verify: BUILD SUCCEEDED; all SessionTitleTests pass
# Manual: send first message in new session → sidebar label updates to message text
# Commit: Phase 187b — Session title auto-labeling from first user message

# ── PHASE 188 — Version Bump to v1.6.0 ───────────────────────────────────────
Read tasks/task-188-version-bump-v1-6.md and execute.
# Verify: BUILD SUCCEEDED; CFBundleShortVersionString == 1.6.0
# Commit: Bump version to 1.6.0 (build 5)
# Tag: v1.6.0

# ── PHASE 189 — Crash Fix: ChatView + Version Bump to v1.6.1 ─────────────────
Read tasks/task-189-crash-fix-chatview-v1-6-1.md and execute.
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
# - refreshDistilledConstitution(using:): one-shot provider call to compress constitution.md;
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
#   tasks/RUN-209-218-BATCHES.md
# and execute one A/B pair per turn, compacting or starting a fresh turn between pairs.

# ── PHASE 208a — KiCad Core Contracts Tests ────────────────────────────────
Read tasks/task-208a-merlin-v2-kicad-core-contracts-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad v2.0 core-contract symbols
# Commit: Phase 208a — KiCadV2CoreContractsTests (failing)

# ── PHASE 208b — KiCad Core Contracts ──────────────────────────────────────
Read tasks/task-208b-merlin-v2-kicad-core-contracts.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadV2CoreContractsTests pass
# Commit: Phase 208b — Merlin v2.0 KiCad core contracts

# ── PHASE 209a — KiCad MCP Tooling Boundary Tests ──────────────────────────
Read tasks/task-209a-kicad-mcp-tooling-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad MCP tooling symbols
# Commit: Phase 209a — KiCadMCPToolingTests (failing)

# ── PHASE 209b — KiCad MCP Tooling Boundary ────────────────────────────────
Read tasks/task-209b-kicad-mcp-tooling.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadMCPToolingTests pass
# Commit: Phase 209b — KiCad MCP tooling boundary

# ── PHASE 210a — KiCad Artifact Schemas Tests ──────────────────────────────
Read tasks/task-210a-kicad-artifact-schemas-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad artifact schema/store symbols
# Commit: Phase 210a — KiCadArtifactSchemasTests (failing)

# ── PHASE 210b — KiCad Artifact Schemas ────────────────────────────────────
Read tasks/task-210b-kicad-artifact-schemas.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadArtifactSchemasTests pass
# Commit: Phase 210b — KiCad artifact schemas and store

# ── PHASE 211a — KiCad Schematic Parser Tests ──────────────────────────────
Read tasks/task-211a-kicad-schematic-parser-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad schematic parser symbols
# Commit: Phase 211a — KiCadSchematicParserTests (failing)

# ── PHASE 211b — KiCad Schematic Parser ────────────────────────────────────
Read tasks/task-211b-kicad-schematic-parser.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadSchematicParserTests pass
# Commit: Phase 211b — KiCad schematic parser and writer

# ── PHASE 212a — Schematic Extraction Policy Tests ─────────────────────────
Read tasks/task-212a-schematic-extraction-policy-tests.md and execute.
# Verify: BUILD FAILED with missing schematic extraction policy symbols
# Commit: Phase 212a — SchematicExtractionPolicyTests (failing)

# ── PHASE 212b — Schematic Extraction Policy ───────────────────────────────
Read tasks/task-212b-schematic-extraction-policy.md and execute.
# Verify: BUILD SUCCEEDED; all SchematicExtractionPolicyTests pass
# Commit: Phase 212b — schematic extraction policy and clarification planning

# ── PHASE 213a — Components/Footprints/BOM Tests ───────────────────────────
Read tasks/task-213a-components-footprints-bom-tests.md and execute.
# Verify: BUILD FAILED with missing component/footprint/BOM policy symbols
# Commit: Phase 213a — ComponentsFootprintsBOMTests (failing)

# ── PHASE 213b — Components/Footprints/BOM ─────────────────────────────────
Read tasks/task-213b-components-footprints-bom.md and execute.
# Verify: BUILD SUCCEEDED; all ComponentsFootprintsBOMTests pass
# Commit: Phase 213b — components footprints libraries and BOM policy

# ── PHASE 214a — Board/Routing Policy Tests ────────────────────────────────
Read tasks/task-214a-board-routing-policy-tests.md and execute.
# Verify: BUILD FAILED with missing board/routing policy symbols
# Commit: Phase 214a — BoardRoutingPolicyTests (failing)

# ── PHASE 214b — Board/Routing Policy ──────────────────────────────────────
Read tasks/task-214b-board-routing-policy.md and execute.
# Verify: BUILD SUCCEEDED; all BoardRoutingPolicyTests pass
# Commit: Phase 214b — board profiles net classes placement and routing policy

# ── PHASE 215a — Verification/Fab Policy Tests ─────────────────────────────
Read tasks/task-215a-verification-fab-policy-tests.md and execute.
# Verify: BUILD FAILED with missing verification/fab policy symbols
# Commit: Phase 215a — VerificationFabPolicyTests (failing)

# ── PHASE 215b — Verification/Fab Policy ───────────────────────────────────
Read tasks/task-215b-verification-fab-policy.md and execute.
# Verify: BUILD SUCCEEDED; all VerificationFabPolicyTests pass
# Commit: Phase 215b — verification gates fabrication and visual QA policy

# ── PHASE 216a — Vendor Order/Approval Tests ───────────────────────────────
Read tasks/task-216a-vendor-order-approval-tests.md and execute.
# Verify: BUILD FAILED with missing vendor/order/approval symbols
# Commit: Phase 216a — VendorOrderApprovalTests (failing)

# ── PHASE 216b — Vendor Order/Approval ─────────────────────────────────────
Read tasks/task-216b-vendor-order-approval.md and execute.
# Verify: BUILD SUCCEEDED; all VendorOrderApprovalTests pass
# Commit: Phase 216b — vendor BOM order and electronics approval policy

# ── PHASE 217a — KiCad Workflow Orchestration Tests ────────────────────────
Read tasks/task-217a-kicad-workflow-orchestration-tests.md and execute.
# Verify: BUILD FAILED with missing workflow orchestration symbols
# Commit: Phase 217a — KiCadWorkflowOrchestrationTests (failing)

# ── PHASE 217b — KiCad Workflow Orchestration ──────────────────────────────
Read tasks/task-217b-kicad-workflow-orchestration.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadWorkflowOrchestrationTests pass
# Commit: Phase 217b — KiCad workflow orchestration

# ── PHASE 218a — Merlin v2.0 Version Release Tests ─────────────────────────
Read tasks/task-218a-merlin-v2-version-release-tests.md and execute.
# Verify: BUILD FAILED until version/release artifacts are bumped
# Commit: Phase 218a — MerlinV2VersionTests (failing)

# ── PHASE 218b — Merlin v2.0 Version Release ───────────────────────────────
Read tasks/task-218b-merlin-v2-version-release.md and execute.
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
Read tasks/task-232a-budget-telemetry-tests.md and execute.
# Verify: BUILD FAILED until telemetry surfaces land
# Commit: Phase 232a — BudgetTelemetryTests (failing)

# ── PHASE 232b — Budget Telemetry ──────────────────────────────────────────
Read tasks/task-232b-budget-telemetry.md and execute.
# Verify: BUILD SUCCEEDED; all phase 232a tests pass
# Commit: Phase 232b — Budget telemetry

# ── PHASE 233a — ProviderBudget + Pre-Flight Tests ─────────────────────────
Read tasks/task-233a-provider-budget-preflight-tests.md and execute.
# Verify: BUILD FAILED until ProviderBudget/TokenEstimator/pre-flight land
# Commit: Phase 233a — ProviderBudgetAndPreflightTests (failing)

# ── PHASE 233b — ProviderBudget + Pre-Flight Gate ──────────────────────────
Read tasks/task-233b-provider-budget-preflight.md and execute.
# Verify: BUILD SUCCEEDED; all phase 233a tests pass
# Commit: Phase 233b — ProviderBudget and pre-flight gate

# ── PHASE 234a — Working-Set Caps Tests ────────────────────────────────────
Read tasks/task-234a-working-set-caps-tests.md and execute.
# Verify: BUILD FAILED until per-component caps land
# Commit: Phase 234a — WorkingSetCapsTests (failing)

# ── PHASE 234b — Working-Set Caps ──────────────────────────────────────────
Read tasks/task-234b-working-set-caps.md and execute.
# Verify: BUILD SUCCEEDED; all phase 234a tests pass
# Commit: Phase 234b — Working-set caps

# ── PHASE 235a — Adaptive RAG Tests ────────────────────────────────────────
Read tasks/task-235a-adaptive-rag-tests.md and execute.
# Verify: BUILD FAILED until RAGSelector lands
# Commit: Phase 235a — AdaptiveRAGTests (failing)

# ── PHASE 235b — Adaptive RAG ──────────────────────────────────────────────
Read tasks/task-235b-adaptive-rag.md and execute.
# Verify: BUILD SUCCEEDED; all phase 235a tests pass
# Commit: Phase 235b — Adaptive RAG

# ── PHASE 236a — Enriched PlanStep + refineStep Tests ──────────────────────
Read tasks/task-236a-planstep-enrichment-refine-tests.md and execute.
# Verify: BUILD FAILED until enriched PlanStep and refineStep land
# Commit: Phase 236a — EnrichedPlanStepAndRefineTests (failing)

# ── PHASE 236b — Enriched PlanStep + refineStep ────────────────────────────
Read tasks/task-236b-planstep-enrichment-refine.md and execute.
# Verify: BUILD SUCCEEDED; all phase 236a tests pass
# Commit: Phase 236b — Enriched PlanStep and refineStep

# ── PHASE 237a — Unified Executor Gate Tests ───────────────────────────────
Read tasks/task-237a-executor-gate-tests.md and execute.
# Verify: BUILD FAILED until EscalationHandler lands and recursive recovery is deleted
# Commit: Phase 237a — UnifiedExecutorGateTests (failing)

# ── PHASE 237b — Unified Executor Gate + Recovery Deletion ─────────────────
Read tasks/task-237b-executor-gate.md and execute.
# Verify: BUILD SUCCEEDED; all phase 237a tests pass; no recursive runLoop self-call remains
# Commit: Phase 237b — Unified executor gate, delete recursive recovery

# ── PHASE 238a — Critic Gating Tests ───────────────────────────────────────
Read tasks/task-238a-critic-gating-tests.md and execute.
# Verify: BUILD FAILED until critic policy resolver and CriterionChecker land
# Commit: Phase 238a — CriticGatingTests (failing)

# ── PHASE 238b — Critic Gating ─────────────────────────────────────────────
Read tasks/task-238b-critic-gating.md and execute.
# Verify: BUILD SUCCEEDED; all phase 238a tests pass
# Commit: Phase 238b — Critic gating

# ── PHASE 239a — Decompose-on-Overflow Tests ───────────────────────────────
Read tasks/task-239a-decompose-on-overflow-tests.md and execute.
# Verify: BUILD FAILED until decompose-first + cross-provider routing land
# Commit: Phase 239a — DecomposeOnOverflowTests (failing)

# ── PHASE 239b — Decompose-on-Overflow ─────────────────────────────────────
Read tasks/task-239b-decompose-on-overflow.md and execute.
# Verify: BUILD SUCCEEDED; all phase 239a tests pass
# Commit: Phase 239b — Decompose-on-overflow

# ── PHASE 240a — v2.1.0 Release Tests ──────────────────────────────────────
Read tasks/task-240a-v2-1-release-tests.md and execute.
# Verify: BUILD FAILED until project.yml bumped and RELEASE-v2.1.0.md added
# Commit: Phase 240a — V2_1ReleaseTests (failing)

# ── PHASE 240b — v2.1.0 Release ────────────────────────────────────────────
Read tasks/task-240b-v2-1-release.md and execute.
# Verify: BUILD SUCCEEDED; "About Merlin" shows 2.1.0 (16)
# Commit: Phase 240b — Bump version to 2.1.0 (Budget-Aware Execution)
# Tag: v2.1.0
# Release: gh release create v2.1.0 --latest
```

---

## Project Discipline

```bash
# ── PHASE 277 — Telemetry Test-Seam Cleanup ─────────────────────────────────
cat tasks/task-277-telemetry-test-cleanup.md
# Verify: BUILD SUCCEEDED; zero warnings; full suite green headless
# Commit: Phase 277 — Remove dead telemetry test seam, dedup reader, fix dismiss test
```

```bash
# -- PHASE 278a — v2.2.2 Release Tests (failing) ----------------------------
cat tasks/task-278a-v2-2-2-release-tests.md
# Verify: BUILD SUCCEEDED; AppVersion222Tests + ReleaseNotes222Tests fail at runtime
# Commit: Phase 278a — V2_2_2ReleaseTests (failing)

# -- PHASE 278b — v2.2.2 Release -------------------------------------------
cat tasks/task-278b-v2-2-2-release.md
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
cat tasks/task-283a-local-model-picker-tests.md
# Verify: BUILD SUCCEEDED; testLocalProviderWithModelsYieldsOnlyVirtualEntries FAILS at runtime
# Commit: Phase 283a — LocalModelPickerEntriesTests (failing)

# ── PHASE 283b — Local Model Picker ─────────────────────────────────────────
cat tasks/task-283b-local-model-picker.md
# Verify: BUILD SUCCEEDED; all phase 283a tests pass; no prior phase regresses
# Commit: Phase 283b — Local model picker in chat HUD + slot picker; model-list refresh

# ── PHASE 284a — Tool Output Cap Tests (failing) ────────────────────────────
cat tasks/task-284a-tool-output-cap-tests.md
# Verify: BUILD FAILED — errors naming the missing ToolOutput type / clamp / maxChars
# Commit: Phase 284a — ToolOutputClampTests (failing)

# ── PHASE 284b — Tool Output Cap ────────────────────────────────────────────
cat tasks/task-284b-tool-output-cap.md
# Verify: BUILD SUCCEEDED; all phase 284a tests pass; no prior phase regresses
# Commit: Phase 284b — Cap run_shell and read_file output before it enters context

# ── PHASE 285a — Context Budget Resolver Tests (failing) ────────────────────
cat tasks/task-285a-context-budget-resolver-tests.md
# Verify: BUILD FAILED — missing ContextBudgetResolver / ContextBudgetStore / EphemeralBudgetStore
# Commit: Phase 285a — ContextBudgetResolverTests (failing)

# ── PHASE 285b — Context Budget Resolver ────────────────────────────────────
cat tasks/task-285b-context-budget-resolver.md
# Verify: BUILD SUCCEEDED; all phase 285a tests pass; no prior phase regresses
# Commit: Phase 285b — ContextBudgetResolver: discover and persist the model's real context window

# ── PHASE 286a — Universal Pre-flight Guard Tests (failing) ─────────────────
cat tasks/task-286a-universal-preflight-tests.md
# Verify: BUILD FAILED — errors naming the missing PreflightGuard type / fit
# Commit: Phase 286a — PreflightGuardTests (failing)

# ── PHASE 286b — Universal Pre-flight Guard ─────────────────────────────────
cat tasks/task-286b-universal-preflight.md
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
cat tasks/task-287a-tool-requirement-checker-tests.md
# Verify: BUILD FAILED — missing ToolRequirement / ToolRequirements / ToolRequirementChecker
# Commit: Phase 287a — ToolRequirementCheckerTests (failing)

# ── PHASE 287b — Tool Requirement Checker ───────────────────────────────────
cat tasks/task-287b-tool-requirement-checker.md
# Verify: BUILD SUCCEEDED; all phase 287a tests pass; no prior phase regresses
# Commit: Phase 287b — Tool requirement checker: detect on first use, offer brew install

# ── PHASE 288a — Vision Launchpad Tests (failing) ───────────────────────────
cat tasks/task-288a-vision-launchpad-tests.md
# Verify: BUILD SUCCEEDED; ProjectVisionLaunchpadTests fail at runtime (skill not yet updated)
# Commit: Phase 288a — ProjectVisionLaunchpadTests (failing)

# ── PHASE 288b — Vision Launchpad ───────────────────────────────────────────
cat tasks/task-288b-vision-launchpad.md
# Verify: BUILD SUCCEEDED; all phase 288a tests pass; vision.md has ## Active + ## Deferred
# Commit: Phase 288b — vision.md launchpad: seed at init, vision→architecture→phase→code pipeline
```

```bash
# ── PHASE 289 — v2.2.4 Release (ships phases 283–288) ───────────────────────
# Run only after 283–288 are all committed.
cat tasks/task-289-v2-2-4-release.md
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
cat tasks/task-307a-target-gate-scanner-tests.md
# Verify: BUILD FAILED — missing TargetGateScanner / UngatedTargetFinding
# Commit: Phase 307a — TargetGateScanner tests (failing)

# ── PHASE 307b — TargetGateScanner ──────────────────────────────────────────
cat tasks/task-307b-target-gate-scanner.md
# Verify: BUILD SUCCEEDED, zero warnings; TargetGateScannerTests + FindingModelTests pass
# Commit: Phase 307b — TargetGateScanner: flag targets the build gate never compiles

# ── PHASE 308a — StubMarkerScanner Tests (failing) ──────────────────────────
cat tasks/task-308a-stub-marker-scanner-tests.md
# Verify: BUILD FAILED — missing StubMarkerScanner / StubMarkerFinding
# Commit: Phase 308a — StubMarkerScanner tests (failing)

# ── PHASE 308b — StubMarkerScanner ──────────────────────────────────────────
cat tasks/task-308b-stub-marker-scanner.md
# Verify: BUILD SUCCEEDED, zero warnings; StubMarkerScannerTests + FindingModelTests pass
# Commit: Phase 308b — StubMarkerScanner: surface unfinished code as discipline findings

# ── PHASE 309a — ReachabilityScanner Tests (failing) ────────────────────────
cat tasks/task-309a-reachability-scanner-tests.md
# Verify: BUILD FAILED — missing ReachabilityScanner / UnwiredComponentFinding
# Commit: Phase 309a — ReachabilityScanner tests (failing)

# ── PHASE 309b — ReachabilityScanner ────────────────────────────────────────
cat tasks/task-309b-reachability-scanner.md
# Verify: BUILD SUCCEEDED, zero warnings; ReachabilityScannerTests + FindingModelTests pass
# Commit: Phase 309b — ReachabilityScanner: flag unwired views and uninjected env objects

# ── PHASE 310a — DocReferenceGraph Fenced-Block Tests (failing) ─────────────
cat tasks/task-310a-doc-reference-fenced-block-tests.md
# Verify: BUILD SUCCEEDED; DocReferenceGraphFencedBlockTests FAILS at runtime (verify with `test`)
# Commit: Phase 310a — DocReferenceGraph fenced-block tests (failing)

# ── PHASE 310b — DocReferenceGraph Fenced-Block Strengthening ───────────────
cat tasks/task-310b-doc-reference-fenced-block.md
# Verify: BUILD SUCCEEDED, zero warnings; DocReferenceGraphFencedBlockTests passes
# Commit: Phase 310b — DocReferenceGraph verifies fenced-block enum cases

# ── PHASE 311a — LivenessGate Tests (failing) ───────────────────────────────
cat tasks/task-311a-liveness-gate-tests.md
# Verify: BUILD FAILED — missing LivenessGate / LivenessGateResult
# Commit: Phase 311a — LivenessGate tests (failing)

# ── PHASE 311b — LivenessGate + pre-commit hook ─────────────────────────────
cat tasks/task-311b-liveness-gate.md
# Verify: BUILD SUCCEEDED, zero warnings; LivenessGateTests + DisciplineCLITests pass; merlin-discipline builds
# Commit: Phase 311b — LivenessGate: pre-commit hook blocks ungated targets

# ── PHASE 312 — Verification Gate Update ────────────────────────────────────
cat tasks/task-312-verification-gate-update.md
# Verify: constitution.md names MerlinTests-Live; .merlin/project.toml lists both gating schemes; MerlinTests-Live build-for-testing SUCCEEDED
# Commit: Phase 312 — Fold MerlinTests-Live into the verification gate
```

---

## Discipline Gate Auto-Install (phase 313)

> Makes the discipline pre-commit gate arm itself at app launch for any project that
> opts into the `pre_commit` discipline layer — removes reliance on the opt-in Settings
> toggle. The toggle stays as a manual install/uninstall override.

```bash
# ── PHASE 313a — Discipline Gate Auto-Install Tests (failing) ───────────────
cat tasks/task-313a-discipline-gate-autoinstall-tests.md
# Verify: BUILD FAILED — missing DisciplineGateInstaller
# Commit: Phase 313a — Discipline gate auto-install tests (failing)

# ── PHASE 313b — Discipline Gate Auto-Install ───────────────────────────────
cat tasks/task-313b-discipline-gate-autoinstall.md
# Verify: BUILD SUCCEEDED, zero warnings; DisciplineGateInstallerTests passes
# Commit: Phase 313b — Auto-arm the discipline pre-commit gate at app launch
```

---

## Discipline Operability (phases 314–315)

> W2 of the proving-readiness plan. 314 fixes a `TargetGateScanner` false positive
> (a dependency-only target was flagged ungated — it blocked a real commit). 315 adds a
> `merlin-discipline scan` subcommand so an operator can run the full discipline scan
> and see every finding. Run a→b strictly in order.

```bash
# ── PHASE 314a — TargetGateScanner Dependency-Following Tests (failing) ──────
cat tasks/task-314a-target-gate-dependency-tests.md
# Verify (test — runtime-failure phase): BUILD SUCCEEDED; testDependencyOnlyTargetIsTreatedAsGated FAILS
# Commit: Phase 314a — TargetGateScanner dependency-following tests (failing)

# ── PHASE 314b — TargetGateScanner Dependency-Following ─────────────────────
cat tasks/task-314b-target-gate-dependency.md
# Verify: BUILD SUCCEEDED, zero warnings; all TargetGateScannerTests pass
# Commit: Phase 314b — TargetGateScanner follows transitive project.yml dependencies

# ── PHASE 315a — merlin-discipline scan Command Tests (failing) ─────────────
cat tasks/task-315a-discipline-scan-command-tests.md
# Verify: BUILD FAILED — missing DisciplineCLI.formatScanReport
# Commit: Phase 315a — merlin-discipline scan command tests (failing)

# ── PHASE 315b — merlin-discipline scan Command ─────────────────────────────
cat tasks/task-315b-discipline-scan-command.md
# Verify: BUILD SUCCEEDED, zero warnings; DisciplineScanReportTests + DisciplineCLITests pass; merlin-discipline builds
# Commit: Phase 315b — merlin-discipline scan: print all discipline findings
```

---

## Scanner Tuning (phases 316–318)

> W2 follow-up. The first real `merlin-discipline scan` of the Merlin repo was ~99%
> false positives. These three task pairs tune the scanners against real-repo noise.
> All three `a` phases are RUNTIME-failure phases — build SUCCEEDS, the new test FAILS;
> verify with `test`, not build-for-testing. Run a→b strictly in order.

```bash
# ── PHASE 316a — DocReferenceGraph Scope Tests (failing) ────────────────────
cat tasks/task-316a-doc-reference-scope-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; testPhasesDocsAndTestSymbolsAreNotFlagged FAILS
# Commit: Phase 316a — DocReferenceGraph scope tests (failing)

# ── PHASE 316b — DocReferenceGraph Scope Fix ────────────────────────────────
cat tasks/task-316b-doc-reference-scope.md
# Verify: BUILD SUCCEEDED, zero warnings; DocReferenceGraphScopeTests + DocReferenceGraphFencedBlockTests pass
# Commit: Phase 316b — DocReferenceGraph skips tasks/ and knows test symbols

# ── PHASE 317a — ReachabilityScanner Injection-Detection Tests (failing) ────
cat tasks/task-317a-reachability-injection-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; ReachabilityScannerInjectionTests FAIL
# Commit: Phase 317a — ReachabilityScanner injection-detection tests (failing)

# ── PHASE 317b — ReachabilityScanner Injection-Detection Fix ────────────────
cat tasks/task-317b-reachability-injection.md
# Verify: BUILD SUCCEEDED, zero warnings; ReachabilityScanner tests pass
# Commit: Phase 317b — ReachabilityScanner reads annotation injection, skips comments

# ── PHASE 318a — StubMarkerScanner Tuning Tests (failing) ───────────────────
cat tasks/task-318a-stub-marker-tuning-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; StubMarkerScannerTuningTests FAIL
# Commit: Phase 318a — StubMarkerScanner tuning tests (failing)

# ── PHASE 318b — StubMarkerScanner Tuning ───────────────────────────────────
cat tasks/task-318b-stub-marker-tuning.md
# Verify: BUILD SUCCEEDED, zero warnings; StubMarkerScanner tests pass
# Commit: Phase 318b — StubMarkerScanner skips .cancel buttons and multi-line strings
```

---

## Scanner Tuning — Precision (phase 319)

> Final scanner-tuning pass. Skips build-output directories (`build/`, `DerivedData/`,
> `.build/`) in all scanner file enumeration, and drops DocReferenceGraph's
> low-precision loose backticked-identifier check (keeping the high-precision
> fenced-block enum-case check). 319a is a RUNTIME-failure phase — verify with `test`.
> 319b also rewrites the task-316a test and adds banners to four prior task docs.

```bash
# ── PHASE 319a — DocReferenceGraph Precision Tests (failing) ────────────────
cat tasks/task-319a-doc-reference-precision-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; DocReferenceGraphPrecisionTests FAIL
# Commit: Phase 319a — DocReferenceGraph precision tests (failing)

# ── PHASE 319b — DocReferenceGraph Precision Fix ────────────────────────────
cat tasks/task-319b-doc-reference-precision.md
# Verify: BUILD SUCCEEDED, zero warnings; DocReferenceGraph Precision/Scope/FencedBlock tests pass
# Commit: Phase 319b — DocReferenceGraph precision: skip build/, drop the loose check
```

## Phases 320–324 — W4 trace-audit findings

> Authored from the W4 trace-the-calls audit (`merlin-eval/TRACE-AUDIT.md`). 320 wires
> the two dead `WorkerDiffView` toolbar buttons (empty `{ }` actions) to the staging
> buffer. 321 fixes a `DocReferenceGraph` false positive — `extractEnumCaseNames` parsed
> words out of `//` comments on `case` lines. 322 removes three dead `TelemetryEmitter`
> setters (zero callers). 323 fixes the `TaskScanner` doc-tier blind spot (it read only
> `task-NNb` docs; the "New surface" block lives in the `a` docs) and makes phaseDrift
> always a nudge. 324 fixes `TaskScanner` symbol matching — qualified names, enum cases,
> non-symbol filtering — so the phaseDrift metric is real, not noise. 320a is a
> COMPILE-failure phase (verify with `build-for-testing`); 321a, 323a and 324a are
> RUNTIME-failure phases (verify with `test`); 322 is an implementation-only cleanup.

```bash
# ── PHASE 320a — WorkerDiffView Reject/Accept Action Tests (failing) ────────
cat tasks/task-320a-worker-diff-actions-tests.md
# Verify (build-for-testing — compile-failure): BUILD FAILED; missing rejectAllChanges/acceptAndMergeChanges
# Commit: Phase 320a — WorkerDiffViewActionTests (failing)

# ── PHASE 320b — Wire WorkerDiffView Reject-All / Accept-and-Merge ──────────
cat tasks/task-320b-worker-diff-actions.md
# Verify: BUILD SUCCEEDED, zero warnings; WorkerDiffViewActionTests pass
# Commit: Phase 320b — Wire WorkerDiffView reject-all / accept-and-merge

# ── PHASE 321a — DocReferenceGraph Comment-Stripping Tests (failing) ────────
cat tasks/task-321a-doc-reference-comment-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; DocReferenceGraphCommentTests FAIL
# Commit: Phase 321a — DocReferenceGraphCommentTests (failing)

# ── PHASE 321b — DocReferenceGraph extractEnumCaseNames Strips // Comments ──
cat tasks/task-321b-doc-reference-comment.md
# Verify: BUILD SUCCEEDED, zero warnings; DocReferenceGraph comment/fenced/precision/dangling tests pass
# Commit: Phase 321b — DocReferenceGraph extractEnumCaseNames strips // comments

# ── PHASE 322 — Remove Dead TelemetryEmitter Setters ───────────────────────
cat tasks/task-322-remove-dead-telemetry-setters.md
# Verify: BUILD SUCCEEDED both schemes, zero warnings; TelemetryEmitterTests pass
# Commit: Phase 322 — Remove dead TelemetryEmitter setters

# ── PHASE 323a — TaskScanner Doc-Coverage & Drift-Severity Tests (failing) ─
cat tasks/task-323a-phasescanner-doc-coverage-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; all 3 new tests FAIL
# Commit: Phase 323a — TaskScanner doc-coverage & drift-severity tests (failing)

# ── PHASE 323b — TaskScanner Reads All Phase Docs; Drift Is Always a Nudge ─
cat tasks/task-323b-phasescanner-doc-coverage.md
# Verify: full MerlinTests suite passes; MerlinTests-Live compiles; zero warnings
# Commit: Phase 323b — TaskScanner reads all task docs; drift is always a nudge

# ── PHASE 324a — TaskScanner Symbol-Matching Accuracy Tests (failing) ──────
cat tasks/task-324a-phasescanner-matching-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; all 5 new tests FAIL
# Commit: Phase 324a — TaskScanner symbol-matching tests (failing)

# ── PHASE 324b — TaskScanner Symbol-Matching Accuracy ──────────────────────
cat tasks/task-324b-phasescanner-matching.md
# Verify: full MerlinTests suite passes; MerlinTests-Live compiles; zero warnings
# Commit: Phase 324b — TaskScanner symbol-matching accuracy
```

## Phase 325 — W5 surface-census gap fill

> The W5 surface census (`merlin-eval/SURFACE-CENSUS.md` §1.2) found 12 interactive
> controls with no `AccessibilityID` — XCUITest cannot reach them, so they are untested
> surface. 325 adds the 12 constants and applies `.accessibilityIdentifier(...)`. 325a
> is a COMPILE-failure phase (verify with `build-for-testing`).

```bash
# ── PHASE 325a — AccessibilityID Gap-Fill Tests (failing) ───────────────────
cat tasks/task-325a-accessibility-id-gap-tests.md
# Verify (build-for-testing — compile-failure): BUILD FAILED; 12 missing AccessibilityID members
# Commit: Phase 325a — AccessibilityID gap-fill tests (failing)

# ── PHASE 325b — AccessibilityID Gap-Fill Implementation ────────────────────
cat tasks/task-325b-accessibility-id-gap.md
# Verify: BUILD SUCCEEDED both schemes, zero warnings; AccessibilityIDCoverageTests pass
# Commit: Phase 325b — AccessibilityID gap-fill: the 12 controls phase 306 missed
```

## Phases 326–330 — W5 proving-suite harness

> The `MerlinE2ETests` / `MerlinTests` harness that drives the S1–S18 eval scenarios.
> Each is an implementation phase (the test file is the deliverable); verify with
> `build-for-testing` (it compiles the harness — the proving suite is run separately).
> Fixtures must be built first per `merlin-eval/fixtures/S{1,2,4,5,6}-*.md`.

```bash
# ── PHASE 326 — Eval Capability Harness (S1–S6) ─────────────────────────────
cat tasks/task-326-eval-capability-harness.md
# Verify: BUILD SUCCEEDED both schemes, zero warnings
# Commit: Phase 326 — Eval capability harness (S1–S6)

# ── PHASE 327 — Eval Agent-Tool Census (S18) ────────────────────────────────
cat tasks/task-327-eval-agent-tool-census.md
# Verify: BUILD SUCCEEDED, zero warnings; AgentToolCensusTests pass
# Commit: Phase 327 — Eval agent-tool census (S18)

# ── PHASE 328 — Eval Surface Harness (S7–S11) ───────────────────────────────
cat tasks/task-328-eval-surface-harness.md
# Verify: BUILD SUCCEEDED (MerlinTests-Live), zero warnings
# Commit: Phase 328 — Eval surface harness (S7–S11)

# ── PHASE 329 — Eval Render Harness (S10) ───────────────────────────────────
cat tasks/task-329-eval-render-harness.md
# Verify: BUILD SUCCEEDED, zero warnings; ConversationRenderTests pass
# Commit: Phase 329 — Eval render harness (S10 chat rendering)

# ── PHASE 330 — Eval Operator Harness (S12–S17) ─────────────────────────────
cat tasks/task-330-eval-operator-harness.md
# Verify: BUILD SUCCEEDED, zero warnings; OperatorConfigTests pass
# Commit: Phase 330 — Eval operator harness (S12–S17)
```

## Phases 331–332 — merlin-eval relocation

> Adds a shared directory blacklist (`DisciplineExclusions`) to every file-walking
> discipline scanner, then moves the eval suite (`merlin-eval/`) into the merlin repo so
> it is version-controlled with the project. 331a/331b are a TDD pair; 332 is the
> filesystem move + harness path fix + commit.

```bash
# ── PHASE 331a — DisciplineExclusions Tests (failing) ───────────────────────
cat tasks/task-331a-discipline-exclusions-tests.md
# Verify (build-for-testing — compile-failure): BUILD FAILED; 4 "cannot find 'DisciplineExclusions'" errors
# Commit: Phase 331a — DisciplineExclusionsTests (failing)

# ── PHASE 331b — DisciplineExclusions Blacklist ─────────────────────────────
cat tasks/task-331b-discipline-exclusions.md
# Verify: BUILD SUCCEEDED both schemes, zero warnings; DisciplineExclusionsTests pass; grep lists 8 scanner files
# Commit: Phase 331b — DisciplineExclusions blacklist

# ── PHASE 332 — Relocate merlin-eval Into The Repo ──────────────────────────
cat tasks/task-332-relocate-merlin-eval.md
# Verify: move done, old sibling path gone; MerlinTests-Live BUILD SUCCEEDED, zero warnings
# Commit: Phase 332 — Relocate merlin-eval into the merlin repo
```

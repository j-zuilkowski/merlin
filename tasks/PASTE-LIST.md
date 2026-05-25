# Codex Paste List — Merlin

Model: gpt-5.4-mini
Invocation: paste the content of each task file directly into the Codex prompt.
No terminal trips, no HANDOFF.md references — every file is self-contained.
Each file includes its own context header, full task, verify step, and git commit.

---

```bash
# ── TASK 00 — Preflight (run once in terminal before starting Codex) ───
cd ~/Documents/localProject/merlin
bash tasks/task-00-preflight.sh
# Must exit 0. Warnings are non-fatal.

# ── HOW TO RUN EACH TASK ──────────────────────────────���─────────────────
# In Codex, paste the content of each task file:
#   cat tasks/task-XX-name.md
# Codex reads the instructions, writes the files, runs the verify step,
# and commits. Then move to the next task.

# ── TASK 01 — Scaffold (xcodegen) ──────────────────────��────────────────
cat tasks/task-01-scaffold.md
# Verify: xcodegen generate + xcodebuild -scheme MerlinTests build-for-testing → BUILD SUCCEEDED
# Commit: git commit -m "Task 01 — xcodegen scaffold"

# ── TASK 02a — Shared Types Tests ───────────────────────────────────────
cat tasks/task-02a-shared-types-tests.md
# Verify: build errors for missing types (expected)
# Commit: Task 02a

# ── TASK 02b — Shared Types Implementation ──────────────────────────────
cat tasks/task-02b-shared-types.md
# Verify: SharedTypesTests → 5 pass
# Commit: Task 02b

# ── TASK 03a — Provider Tests ───────────────────────────────────────────
cat tasks/task-03a-provider-tests.md
# Verify: build errors for missing types (expected)
# Commit: Task 03a

# ── TASK 03b — DeepSeekProvider + SSEParser ─────────────────────────────
cat tasks/task-03b-deepseek-provider.md
# Verify: ProviderTests → 5 pass
# Commit: Task 03b

# ── TASK 04 — LMStudioProvider ──────────────────────────────────────────
cat tasks/task-04-lmstudio-provider.md
# Verify: BUILD SUCCEEDED; live test skips without RUN_LIVE_TESTS
# Commit: Task 04

# ── TASK 05 — KeychainManager ───────────────────────────────────────────
cat tasks/task-05-keychain.md
# Verify: KeychainTests → 3 pass
# Commit: Task 05

# ── TASK 06 — Tool Definitions ──────────────────────────────────────────
cat tasks/task-06-tool-definitions.md
# Verify: BUILD SUCCEEDED; ToolDefinitions.all is non-empty
# Commit: Task 06

# ── TASK 07a — FileSystem + Shell Tests ─────────────────────────────────
cat tasks/task-07a-filesystem-shell-tests.md
# Verify: build errors for missing types (expected)
# Commit: Task 07a

# ── TASK 07b — FileSystem + Shell Implementation ────────────────────────
cat tasks/task-07b-filesystem-shell.md
# Verify: FileSystemToolTests → 5 pass; ShellToolTests → 4 pass
# Commit: Task 07b

# ── TASK 08a — Xcode Tools Tests ────────────────────────────────────────
cat tasks/task-08a-xcode-tools-tests.md
# Verify: build errors for missing types (expected)
# Commit: Task 08a

# ── TASK 08b — Xcode Tools Implementation ───────────────────────────────
cat tasks/task-08b-xcode-tools.md
# Verify: XcodeToolTests → pass (fixture test may skip)
# Commit: Task 08b

# ── TASK 09a — AX + ScreenCapture Tests ─────────────────────────────────
cat tasks/task-09a-ax-screencapture-tests.md
# Verify: build errors for missing types (expected)
# Commit: Task 09a

# ── TASK 09b — AXInspectorTool + ScreenCaptureTool ──────────────────────
cat tasks/task-09b-ax-screencapture.md
# Verify: AXInspectorTests → pass (needs Accessibility); ScreenCaptureTests → pass or skip
# Commit: Task 09b

# ── TASK 10 — CGEventTool + VisionQueryTool ──────────────────────────────
cat tasks/task-10-cgevent-vision.md
# Verify: CGEventToolTests → 2 pass
# Commit: Task 10

# ── TASK 11 — AppControlTools + ToolDiscovery ────────────────────────────
cat tasks/task-11-appcontrol-discovery.md
# Verify: AppControlTests → pass; ToolDiscoveryTests → pass
# Commit: Task 11

# ── TASK 12a — Auth Tests ────────────────────────────────────────────────
cat tasks/task-12a-auth-tests.md
# Verify: build errors for missing types (expected)
# Commit: Task 12a

# ── TASK 12b — PatternMatcher + AuthMemory ───────────────────────────────
cat tasks/task-12b-auth-impl.md
# Verify: PatternMatcherTests → 5 pass; AuthMemoryTests → 3 pass
# Commit: Task 12b

# ── TASK 13a — AuthGate Tests ────────────────────────────────────────────
cat tasks/task-13a-authgate-tests.md
# Verify: build errors for missing types (expected)
# Commit: Task 13a

# ── TASK 13b — AuthGate Implementation ───────────────────────────────────
cat tasks/task-13b-authgate-impl.md
# Verify: AuthGateTests → 4 pass
# Commit: Task 13b

# ── TASK 14a — ContextManager Tests ──────────────────────────────────────
cat tasks/task-14a-contextmanager-tests.md
# Verify: build errors for missing types (expected)
# Commit: Task 14a

# ── TASK 14b — ContextManager Implementation ─────────────────────────────
cat tasks/task-14b-contextmanager-impl.md
# Verify: ContextManagerTests → 5 pass
# Commit: Task 14b

# ── TASK 15 — ToolRouter ─────────────────────────────────────────────────
cat tasks/task-15-toolrouter.md
# Verify: ToolRouterTests → 2 pass
# Commit: Task 15

# ── TASK 16 — ThinkingModeDetector ───────────────────────────────────────
cat tasks/task-16-thinking-detector.md
# Verify: ThinkingModeDetectorTests → 6 pass
# Commit: Task 16

# ── TASK 17a — AgenticEngine Tests ───────────────────────────────────────
cat tasks/task-17a-agenticengine-tests.md
# Verify: build errors for missing types (expected)
# Commit: Task 17a

# ── TASK 17b — AgenticEngine Implementation ──────────────────────────────
cat tasks/task-17b-agenticengine-impl.md
# Verify: AgenticEngineTests → 4 pass; zero warnings
# Commit: Task 17b

# ── TASK 18 — Sessions ───────────────────────────────────────────────────
cat tasks/task-18-sessions.md
# Verify: SessionSerializationTests → 4 pass
# Commit: Task 18

# ── TASK 19 — AppState + Entry Point ─────────────────────────────────────
cat tasks/task-19-appstate-entrypoint.md
# Verify: BUILD SUCCEEDED
# Commit: Task 19

# ── TASK 19b — Tool Handler Registration ─────────────────────────────────
cat tasks/task-19b-tool-registration.md
# Verify: BUILD SUCCEEDED; all built-in handlers registered
# Commit: Task 19b

# ── TASK 20 — ContentView + ChatView + ProviderHUD ───────────────────────
cat tasks/task-20-chatview.md
# Verify: BUILD SUCCEEDED
# Commit: Task 20

# ── TASK 21 — ToolLogView + ScreenPreviewView ────────────────────────────
cat tasks/task-21-secondary-views.md
# Verify: BUILD SUCCEEDED; VisualLayoutTests → testNoWidgetsClipped + testAccessibilityAudit pass
# Commit: Task 21

# ── TASK 22 — AuthPopupView + FirstLaunchSetup ───────────────────────────
cat tasks/task-22-authpopup.md
# Verify: BUILD SUCCEEDED
# Commit: Task 22

# ── TASK 23 — TestTargetApp ──────────────────────────────────────────────
cat tasks/task-23-test-fixture-app.md
# Verify: BUILD SUCCEEDED; GUIAutomationE2ETests skip without RUN_LIVE_TESTS
# Commit: Task 23

# ── TASK 24 — Live Tests + Final E2E ─────────────────────────────────────
cat tasks/task-24-live-e2e.md
# Verify (requires RUN_LIVE_TESTS=1 + DEEPSEEK_API_KEY):
#   DeepSeekProviderLiveTests → 3 pass
#   AgenticLoopE2ETests → 1 pass (reads real file via real API)
#   GUIAutomationE2ETests → pass (with Accessibility + LM Studio running)
# Commit: Task 24

# ── TASK 25a — RAG Integration Tests ────────────────────────────────────────
cat tasks/task-25a-rag-tests.md
# Verify: BUILD FAILED with errors for XcalibreClient, RAGChunk, RAGBook, RAGTools,
#         CapturingProvider (expected)
# Commit: Task 25a

# ── TASK 25b — RAG Integration Implementation ────────────────────────────────
cat tasks/task-25b-rag-impl.md
# Verify: TEST BUILD SUCCEEDED; XcalibreClientTests → 10 pass; RAGToolsTests → 11 pass;
#         RAGEngineTests → 3 pass
# Commit: Task 25b

# ── TASK 26a — Multi-Provider Tests ─────────────────────────────────────────
cat tasks/task-26a-provider-tests.md
# Verify: BUILD FAILED with errors for ProviderRegistry, OpenAICompatibleProvider,
#         AnthropicSSEParser, AnthropicMessageEncoder, AnthropicProvider,
#         AgenticEngine.shouldUseThinking(for:) (expected)
# Commit: Task 26a

# ── TASK 26b — Multi-Provider Implementation ─────────────────────────────────
cat tasks/task-26b-provider-impl.md
# Verify: TEST BUILD SUCCEEDED; ProviderRegistryTests → 14 pass;
#         OpenAICompatibleProviderTests → 5 pass; AnthropicSSEParserTests → 7 pass;
#         AnthropicMessageEncoderTests → 5 pass; AnthropicProviderRequestTests → 4 pass;
#         AgenticEngineProviderTests → 4 pass
# Commit: Task 26b

# ── TASK 27a — Model Picker Tests ───────────────────────────────────────────
cat tasks/task-27a-model-picker-tests.md
# Verify: BUILD FAILED with errors for ProviderRegistry.knownModels (expected)
# Commit: Task 27a

# ── TASK 27b — Model Picker Implementation ───────────────────────────────────
cat tasks/task-27b-model-picker.md
# Verify: BUILD SUCCEEDED; ProviderModelPickerTests → 8 pass
# Commit: Task 27b

# ── TASK 28a — Menu Tests ────────────────────────────────────────────────────
cat tasks/task-28a-menu-tests.md
# Verify: BUILD FAILED with errors for AgenticEngine.cancel(), AppState.newSession(),
#         AppState.stopEngine(), Notification.Name.merlinNewSession (expected)
# Commit: Task 28a

# ── TASK 28b — Menu Implementation ──────────────────────────────────────────
cat tasks/task-28b-menu.md
# Verify: BUILD SUCCEEDED; AgenticEngineCancelTests → 3 pass;
#         AppStateSessionTests → 4 pass
# Commit: Task 28b

# ════════════════════════════════════════════════════════════════════════════
# VERSION 2
# ════════════════════════════════════════════════════════════════════════════

# ── TASK 29 — ProjectRef + ProjectPickerView + WindowGroup ──────────────────
cat tasks/task-29-project-picker.md
# Verify: BUILD SUCCEEDED; project picker shown at launch; workspace window opens per project
# Commit: Task 29

# ── TASK 30a — SessionManager Tests ─────────────────────────────────────────
cat tasks/task-30a-session-manager-tests.md
# Verify: BUILD FAILED with errors for SessionManager, LiveSession (expected)
# Commit: Task 30a

# ── TASK 30b — SessionManager Implementation ─────────────────────────────────
cat tasks/task-30b-session-manager.md
# Verify: BUILD SUCCEEDED; SessionManagerTests → 8 pass
# Commit: Task 30b

# ── TASK 31a — Permission Mode Tests ────────────────────────────────────────
cat tasks/task-31a-permission-mode-tests.md
# Verify: BUILD FAILED with errors for PermissionMode (expected)
# Commit: Task 31a

# ── TASK 31b — Permission Mode Implementation ───────────────────────────────
cat tasks/task-31b-permission-mode.md
# Verify: BUILD SUCCEEDED; PermissionModeTests → 6 pass
# Commit: Task 31b

# ── TASK 32a — StagingBuffer Tests ──────────────────────────────────────────
cat tasks/task-32a-staging-buffer-tests.md
# Verify: BUILD FAILED with errors for StagingBuffer, StagedChange, ChangeKind (expected)
# Commit: Task 32a

# ── TASK 32b — StagingBuffer Implementation ─────────────────────────────────
cat tasks/task-32b-staging-buffer.md
# Verify: BUILD SUCCEEDED; StagingBufferTests → 10 pass
# Commit: Task 32b

# ── TASK 33a — DiffEngine Tests ─────────────────────────────────────────────
cat tasks/task-33a-diff-engine-tests.md
# Verify: BUILD FAILED with errors for DiffEngine, DiffHunk, DiffLine (expected)
# Commit: Task 33a

# ── TASK 33b — DiffEngine + DiffPane ────────────────────────────────────────
cat tasks/task-33b-diff-pane.md
# Verify: BUILD SUCCEEDED; DiffEngineTests → 9 pass
# Commit: Task 33b

# ── TASK 34 — ChatView v2 (stop button + scroll lock) ───────────────────────
cat tasks/task-34-chatview-v2.md
# Verify: BUILD SUCCEEDED; stop button appears while streaming; scroll lock banner works
# Commit: Task 34

# ── TASK 35a — Inline Diff Comment Tests ────────────────────────────────────
cat tasks/task-35a-diff-comment-tests.md
# Verify: BUILD FAILED with errors for DiffComment, StagingBuffer.addComment (expected)
# Commit: Task 35a

# ── TASK 35b — Inline Diff Commenting ───────────────────────────────────────
cat tasks/task-35b-diff-comment.md
# Verify: BUILD SUCCEEDED; DiffCommentTests → 6 pass
# Commit: Task 35b

# ── TASK 36a — ConstitutionLoader Tests ─────────────────────────────────────────
cat tasks/task-36a-constitution-tests.md
# Verify: BUILD FAILED with errors for ConstitutionLoader (expected)
# Commit: Task 36a

# ── TASK 36b — ConstitutionLoader Implementation ────────────────────────────────
cat tasks/task-36b-constitution.md
# Verify: BUILD SUCCEEDED; ConstitutionLoaderTests → 8 pass
# Commit: Task 36b

# ── TASK 37a — Context Injection Tests ──────────────────────────────────────
cat tasks/task-37a-context-injection-tests.md
# Verify: BUILD FAILED with errors for ContextInjector, AttachmentError (expected)
# Commit: Task 37a

# ── TASK 37b — Context Injection Implementation ─────────────────────────────
cat tasks/task-37b-context-injection.md
# Verify: BUILD SUCCEEDED; ContextInjectionTests → 8 pass
# Commit: Task 37b

# ── TASK 38a — SkillsRegistry Tests ─────────────────────────────────────────
cat tasks/task-38a-skills-registry-tests.md
# Verify: BUILD FAILED with errors for SkillsRegistry, Skill, SkillFrontmatter (expected)
# Commit: Task 38a

# ── TASK 38b — SkillsRegistry Implementation ────────────────────────────────
cat tasks/task-38b-skills-registry.md
# Verify: BUILD SUCCEEDED; SkillsRegistryTests → 10 pass
# Commit: Task 38b

# ── TASK 39a — Skill Invocation Tests ───────────────────────────────────────
cat tasks/task-39a-skill-invocation-tests.md
# Verify: BUILD FAILED with errors for AgenticEngine.invokeSkill (expected)
# Commit: Task 39a

# ── TASK 39b — Skill Invocation + Built-in Skills ───────────────────────────
cat tasks/task-39b-skill-invocation.md
# Verify: BUILD SUCCEEDED; SkillInvocationTests → 4 pass
# Commit: Task 39b

# ── TASK 40a — MCPBridge Tests ──────────────────────────────────────────────
cat tasks/task-40a-mcp-bridge-tests.md
# Verify: BUILD FAILED with errors for MCPConfig, MCPServerConfig, MCPBridge (expected)
# Commit: Task 40a

# ── TASK 40b — MCPBridge Implementation ─────────────────────────────────────
cat tasks/task-40b-mcp-bridge.md
# Verify: BUILD SUCCEEDED; MCPBridgeTests → 9 pass
# Commit: Task 40b

# ── TASK 41a — SchedulerEngine Tests ────────────────────────────────────────
cat tasks/task-41a-scheduler-tests.md
# Verify: BUILD FAILED with errors for SchedulerEngine, ScheduledTask, ScheduleCadence (expected)
# Commit: Task 41a

# ── TASK 41b — SchedulerEngine Implementation ───────────────────────────────
cat tasks/task-41b-scheduler.md
# Verify: BUILD SUCCEEDED; SchedulerEngineTests → 6 pass
# Commit: Task 41b

# ── TASK 42a — PRMonitor Tests ──────────────────────────────────────────────
cat tasks/task-42a-pr-monitor-tests.md
# Verify: BUILD FAILED with errors for PRMonitor, PRStatus, ChecksState (expected)
# Commit: Task 42a

# ── TASK 42b — PRMonitor Implementation ─────────────────────────────────────
cat tasks/task-42b-pr-monitor.md
# Verify: BUILD SUCCEEDED; PRMonitorTests → 9 pass
# Commit: Task 42b

# ── TASK 43a — Connectors Tests ─────────────────────────────────────────────
cat tasks/task-43a-connectors-tests.md
# Verify: BUILD FAILED with errors for ConnectorCredentials, GitHubConnector (expected)
# Commit: Task 43a

# ── TASK 43b — Connectors Implementation ────────────────────────────────────
cat tasks/task-43b-connectors.md
# Verify: BUILD SUCCEEDED; ConnectorCredentialsTests → 4 pass; ConnectorProtocolTests → 5 pass
# Commit: Task 43b

# ── DONE (v2) ─────────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 3
# ════════════════════════════════════════════════════════════════════════════

# ── TASK 44a — TOMLDecoder Tests ────────────────────────────────────────────
cat tasks/task-44a-toml-decoder-tests.md
# Verify: BUILD FAILED with errors for TOMLDecoder, TOMLValue, TOMLLexer (expected)
# Commit: Task 44a

# ── TASK 44b — TOMLDecoder Implementation ───────────────────────────────────
cat tasks/task-44b-toml-decoder.md
# Verify: BUILD SUCCEEDED; TOMLDecoderTests → ~25 pass
# Commit: Task 44b

# ── TASK 45a — ToolRegistry Tests ───────────────────────────────────────────
cat tasks/task-45a-tool-registry-tests.md
# Verify: BUILD FAILED with errors for ToolRegistry (expected)
# Commit: Task 45a

# ── TASK 45b — ToolRegistry Implementation ──────────────────────────────────
cat tasks/task-45b-tool-registry.md
# Verify: BUILD SUCCEEDED; ToolRegistryTests → pass; migrated off ToolDefinitions.all count
# Commit: Task 45b

# ── TASK 46a — AppSettings Tests ────────────────────────────────────────────
cat tasks/task-46a-appsettings-tests.md
# Verify: BUILD FAILED with errors for AppSettings, SettingsProposal (expected)
# Commit: Task 46a

# ── TASK 46b — AppSettings + config.toml + Settings Window + Appearance ─────
cat tasks/task-46b-appsettings.md
# Verify: BUILD SUCCEEDED; AppSettingsTests → pass; Settings window opens via Cmd+,
# Commit: Task 46b

# ── TASK 47a — Memories Tests ───────────────────────────────────────────────
cat tasks/task-47a-memories-tests.md
# Verify: BUILD FAILED with errors for MemoryEngine, MemoryStore (expected)
# Commit: Task 47a

# ── TASK 47b — AI-Generated Memories ────────────────────────────────────────
cat tasks/task-47b-memories.md
# Verify: BUILD SUCCEEDED; MemoryEngineTests → pass
# Commit: Task 47b

# ── TASK 48a — Hooks Tests ──────────────────────────────────────────────────
cat tasks/task-48a-hooks-tests.md
# Verify: BUILD FAILED with errors for HookEngine, HookDefinition, HookDecision (expected)
# Commit: Task 48a

# ── TASK 48b — Hooks Implementation ─────────────────────────────────────────
cat tasks/task-48b-hooks.md
# Verify: BUILD SUCCEEDED; HookEngineTests → pass
# Commit: Task 48b

# ── TASK 49a — Thread Automations Tests ─────────────────────────────────────
cat tasks/task-49a-thread-automations-tests.md
# Verify: BUILD FAILED with errors for ThreadAutomation, SchedulerEngine.resume (expected)
# Commit: Task 49a

# ── TASK 49b — Thread Automations ───────────────────────────────────────────
cat tasks/task-49b-thread-automations.md
# Verify: BUILD SUCCEEDED; ThreadAutomationTests → pass
# Commit: Task 49b

# ── TASK 50a — Web Search Tests ─────────────────────────────────────────────
cat tasks/task-50a-web-search-tests.md
# Verify: BUILD FAILED with errors for WebSearchTool, BraveSearchClient (expected)
# Commit: Task 50a

# ── TASK 50b — Web Search Tool ──────────────────────────────────────────────
cat tasks/task-50b-web-search.md
# Verify: BUILD SUCCEEDED; WebSearchTests → pass
# Commit: Task 50b

# ── TASK 51 — Reasoning Effort + Personalization + Context Usage Indicator ──
cat tasks/task-51-agent-settings.md
# Verify: BUILD SUCCEEDED; reasoning effort picker renders; standing instructions inject
# Commit: Task 51

# ── TASK 52 — Toolbar Actions + Notifications ───────────────────────────────
cat tasks/task-52-toolbar-notifications.md
# Verify: BUILD SUCCEEDED; toolbar actions render; notifications fire on completion
# Commit: Task 52

# ── TASK 53 — Floating Pop-out Window + Voice Dictation ─────────────────────
cat tasks/task-53-popout-voice.md
# Verify: BUILD SUCCEEDED; thread detaches to floating window; Ctrl+M opens voice input
# Commit: Task 53

# ── DONE (v3) ─────────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 4
# ════════════════════════════════════════════════════════════════════════════

# ── TASK 54a — AgentDefinition + AgentRegistry Tests ─────────────────────────
cat tasks/task-54a-agent-definition-tests.md
# Verify: BUILD FAILED (AgentDefinition, AgentRole, AgentRegistry not defined)
# Commit: Task 54a — AgentRegistryTests (failing)

# ── TASK 54b — AgentDefinition + AgentRegistry Implementation ────────────────
cat tasks/task-54b-agent-definition.md
# Verify: BUILD SUCCEEDED; all AgentRegistryTests pass
# Commit: Task 54b — AgentDefinition + AgentRegistry

# ── TASK 55a — SubagentEngine V4a Tests ──────────────────────────────────────
cat tasks/task-55a-subagent-engine-tests.md
# Verify: BUILD FAILED (SubagentEngine, SubagentEvent not defined)
# Commit: Task 55a — SubagentEngineTests (failing)

# ── TASK 55b — SubagentEngine V4a Implementation ─────────────────────────────
cat tasks/task-55b-subagent-engine.md
# Verify: BUILD SUCCEEDED; all SubagentEngineTests pass
# Commit: Task 55b — SubagentEngine V4a

# ── TASK 56 — SubagentStream UI ──────────────────────────────────────────────
cat tasks/task-56-subagent-stream-ui.md
# Verify: BUILD SUCCEEDED; all SubagentBlockViewModelTests pass
# Commit: Task 56 — SubagentStreamUI

# ── TASK 57a — WorktreeManager Tests ─────────────────────────────────────────
cat tasks/task-57a-worktree-manager-tests.md
# Verify: BUILD FAILED (WorktreeManager, WorktreeError not defined)
# Commit: Task 57a — WorktreeManagerTests (failing)

# ── TASK 57b — WorktreeManager Implementation ────────────────────────────────
cat tasks/task-57b-worktree-manager.md
# Verify: BUILD SUCCEEDED; all WorktreeManagerTests pass
# Commit: Task 57b — WorktreeManager

# ── TASK 58a — WorkerSubagentEngine Tests ────────────────────────────────────
cat tasks/task-58a-subagent-worker-tests.md
# Verify: BUILD FAILED (WorkerSubagentEngine not defined)
# Commit: Task 58a — WorkerSubagentEngineTests (failing)

# ── TASK 58b — WorkerSubagentEngine Implementation ───────────────────────────
cat tasks/task-58b-subagent-worker.md
# Verify: BUILD SUCCEEDED; all WorkerSubagentEngineTests pass
# Commit: Task 58b — WorkerSubagentEngine V4b

# ── TASK 59 — SubagentSidebar UI ─────────────────────────────────────────────
cat tasks/task-59-subagent-sidebar-ui.md
# Verify: BUILD SUCCEEDED; all SubagentSidebarViewModelTests pass
# Commit: Task 59 — SubagentSidebar UI

# ════════════════════════════════════════════════════════════════════════════
# VERSION 4 (continued) — Skills, Vision, Memory, Settings, Workspace, Wiring
# ════════════════════════════════════════════════════════════════════════════

# ── TASK 60a — Skill Compaction Tests ───────────────────────────────────────
cat tasks/task-60a-skill-compaction-tests.md
# Verify: BUILD FAILED with errors for SkillCompactionEngine (expected)
# Commit: Task 60a — SkillCompactionTests (failing)

# ── TASK 60b — Skill Compaction Implementation ───────────────────────────────
cat tasks/task-60b-skill-compaction.md
# Verify: BUILD SUCCEEDED; SkillCompactionTests → pass
# Commit: Task 60b — Skill Compaction

# ── TASK 61a — Vision Attachment Tests ──────────────────────────────────────
cat tasks/task-61a-vision-attachment-tests.md
# Verify: BUILD FAILED with errors for ContextInjector vision methods (expected)
# Commit: Task 61a — ContextInjectorVisionTests (failing)

# ── TASK 61b — Vision Attachment Implementation ──────────────────────────────
cat tasks/task-61b-vision-attachment.md
# Verify: BUILD SUCCEEDED; ContextInjectorVisionTests → pass
# Commit: Task 61b — Vision Attachment

# ── TASK 62a — Memory Generation Tests ──────────────────────────────────────
cat tasks/task-62a-memory-generation-tests.md
# Verify: BUILD FAILED with errors for MemoryEngine generation methods (expected)
# Commit: Task 62a — MemoryGenerationTests (failing)

# ── TASK 62b — Memory Generation Implementation ─────────────────────────────
cat tasks/task-62b-memory-generation.md
# Verify: BUILD SUCCEEDED; MemoryGenerationTests → pass
# Commit: Task 62b — Memory Generation

# ── TASK 63a — Memory Injection Tests ───────────────────────────────────────
cat tasks/task-63a-memory-injection-tests.md
# Verify: BUILD FAILED with errors for MemoryEngine injection methods (expected)
# Commit: Task 63a — MemoryInjectionTests (failing)

# ── TASK 63b — Memory Injection Implementation ───────────────────────────────
cat tasks/task-63b-memory-injection.md
# Verify: BUILD SUCCEEDED; MemoryInjectionTests → pass
# Commit: Task 63b — Memory Injection

# ── TASK 64 — SettingsSection Enum ──────────────────────────────────────────
cat tasks/task-64-settings-section-enum.md
# Verify: BUILD SUCCEEDED; settings navigation includes all sections
# Commit: Task 64 — SettingsSection Enum

# ── TASK 65 — Agent Settings Section ────────────────────────────────────────
cat tasks/task-65-agent-settings.md
# Verify: BUILD SUCCEEDED; Agent settings section renders in Settings window
# Commit: Task 65 — Agent Settings Section

# ── TASK 66 — Memories Settings Section ─────────────────────────────────────
cat tasks/task-66-memories-settings.md
# Verify: BUILD SUCCEEDED; Memories settings section renders
# Commit: Task 66 — Memories Settings Section

# ── TASK 67 — MCP Settings Section ──────────────────────────────────────────
cat tasks/task-67-mcp-settings.md
# Verify: BUILD SUCCEEDED; MCP settings section renders
# Commit: Task 67 — MCP Settings Section

# ── TASK 68 — Skills Settings Section ───────────────────────────────────────
cat tasks/task-68-skills-settings.md
# Verify: BUILD SUCCEEDED; Skills settings section renders
# Commit: Task 68 — Skills Settings Section

# ── TASK 69 — Web Search Settings Section ───────────────────────────────────
cat tasks/task-69-search-settings.md
# Verify: BUILD SUCCEEDED; Web Search settings section renders
# Commit: Task 69 — Web Search Settings Section

# ── TASK 70 — Permissions Settings Section ──────────────────────────────────
cat tasks/task-70-permissions-settings.md
# Verify: BUILD SUCCEEDED; Permissions settings section renders
# Commit: Task 70 — Permissions Settings Section

# ── TASK 71 — Advanced + Connectors Settings ────────────────────────────────
cat tasks/task-71-advanced-connectors-settings.md
# Verify: BUILD SUCCEEDED; Advanced and Connectors settings sections render
# Commit: Task 71 — Advanced + Connectors Settings

# ── TASK 72a — WorkspaceLayoutManager Tests ─────────────────────────────────
cat tasks/task-72a-workspace-layout-tests.md
# Verify: BUILD FAILED with errors for WorkspaceLayoutManager (expected)
# Commit: Task 72a — WorkspaceLayoutManagerTests (failing)

# ── TASK 72b — WorkspaceLayoutManager Implementation ────────────────────────
cat tasks/task-72b-workspace-layout.md
# Verify: BUILD SUCCEEDED; WorkspaceLayoutManagerTests → pass
# Commit: Task 72b — WorkspaceLayoutManager

# ── TASK 73 — FilePane ───────────────────────────────────────────────────────
cat tasks/task-73-file-pane.md
# Verify: BUILD SUCCEEDED; FilePane renders inline file viewer
# Commit: Task 73 — FilePane

# ── TASK 74 — TerminalPane ───────────────────────────────────────────────────
cat tasks/task-74-terminal-pane.md
# Verify: BUILD SUCCEEDED; TerminalPane renders inline PTY terminal
# Commit: Task 74 — TerminalPane

# ── TASK 75 — PreviewPane ────────────────────────────────────────────────────
cat tasks/task-75-preview-pane.md
# Verify: BUILD SUCCEEDED; PreviewPane renders HTML/Markdown via WKWebView
# Commit: Task 75 — PreviewPane

# ── TASK 76 — SideChat ──────────────────────────────────────────────────────
cat tasks/task-76-side-chat.md
# Verify: BUILD SUCCEEDED; SideChat renders independent secondary chat panel
# Commit: Task 76 — SideChat

# ── TASK 77 — WorkspaceView Wiring ──────────────────────────────────────────
cat tasks/task-77-workspace-wiring.md
# Verify: BUILD SUCCEEDED; all panes wire into WorkspaceView with layout persistence
# Commit: Task 77 — WorkspaceView Wiring

# ── TASK 78 — Fix MerlinApp Settings Scene ──────────────────────────────────
cat tasks/task-78-fix-settings-scene.md
# Verify: BUILD SUCCEEDED; Settings window opens correctly from menu
# Commit: Task 78 — Fix Settings Scene

# ── TASK 79a — Subagent Chat Integration Tests ───────────────────────────────
cat tasks/task-79a-subagent-chat-tests.md
# Verify: BUILD FAILED with errors for subagent chat integration (expected)
# Commit: Task 79a — SubagentChatIntegrationTests (failing)

# ── TASK 79b — Subagent Chat Integration ────────────────────────────────────
cat tasks/task-79b-subagent-chat.md
# Verify: BUILD SUCCEEDED; SubagentChatIntegrationTests → pass
# Commit: Task 79b — Subagent Chat Integration

# ── TASK 80a — DisabledSkillNames Enforcement Tests ─────────────────────────
cat tasks/task-80a-disabled-skills-tests.md
# Verify: BUILD FAILED with errors for disabled skill enforcement (expected)
# Commit: Task 80a — DisabledSkillNamesTests (failing)

# ── TASK 80b — DisabledSkillNames Enforcement ───────────────────────────────
cat tasks/task-80b-disabled-skills.md
# Verify: BUILD SUCCEEDED; DisabledSkillNamesTests → pass
# Commit: Task 80b — DisabledSkillNames Enforcement

# ── TASK 81 — Scheduler Settings + Wiring ───────────────────────────────────
cat tasks/task-81-scheduler-settings.md
# Verify: BUILD SUCCEEDED; Scheduler settings section renders; SchedulerEngine wired
# Commit: Task 81 — Scheduler Settings + Wiring

# ── TASK 82 — ContextUsageTracker: Wire Into ProviderHUD ────────────────────
cat tasks/task-82-context-usage-indicator.md
# Verify: BUILD SUCCEEDED; context usage indicator appears in ProviderHUD
# Commit: Task 82 — ContextUsageTracker

# ── TASK 83 — Voice Dictation Button ────────────────────────────────────────
cat tasks/task-83-voice-dictation-button.md
# Verify: BUILD SUCCEEDED; microphone button appears in ChatView input area
# Commit: Task 83 — Voice Dictation Button

# ── TASK 84 — FloatingWindowManager ─────────────────────────────────────────
cat tasks/task-84-floating-window.md
# Verify: BUILD SUCCEEDED; floating window opens from menu item and keyboard shortcut
# Commit: Task 84 — FloatingWindowManager

# ── TASK 85 — ThreadAutomationEngine Wiring ─────────────────────────────────
cat tasks/task-85-thread-automations.md
# Verify: BUILD SUCCEEDED; ThreadAutomationEngine wired into LiveSession
# Commit: Task 85 — ThreadAutomationEngine Wiring

# ── TASK 86 — ToolbarActionStore Wiring ─────────────────────────────────────
cat tasks/task-86-toolbar-actions.md
# Verify: BUILD SUCCEEDED; toolbar actions render and fire from ChatView toolbar
# Commit: Task 86 — ToolbarActionStore Wiring

# ── TASK 87 — PRMonitor Wiring ───────────────────────────────────────────────
cat tasks/task-87-pr-monitor.md
# Verify: BUILD SUCCEEDED; PRMonitor wired into AppState
# Commit: Task 87 — PRMonitor Wiring

# ── TASK 88a — AppSettings Additions Tests ───────────────────────────────────
cat tasks/task-88a-appsettings-additions-tests.md
# Verify: BUILD FAILED with errors for keepAwake, permissionMode, notifications, messageDensity (expected)
# Commit: Task 88a — AppSettingsAdditionsTests (failing)

# ── TASK 88b — AppSettings Additions Implementation ─────────────────────────
cat tasks/task-88b-appsettings-additions.md
# Verify: BUILD SUCCEEDED; AppSettingsAdditionsTests → pass
# Commit: Task 88b — AppSettings Additions

# ── TASK 89 — General + Appearance Settings ─────────────────────────────────
cat tasks/task-89-settings-general-appearance.md
# Verify: BUILD SUCCEEDED; General and Appearance settings sections complete
# Commit: Task 89 — General + Appearance Settings

# ── TASK 90 — Advanced Settings ─────────────────────────────────────────────
cat tasks/task-90-advanced-settings.md
# Verify: BUILD SUCCEEDED; Advanced settings section complete
# Commit: Task 90 — Advanced Settings

# ── TASK 91 — Register Built-in Tools at Launch ─────────────────────────────
cat tasks/task-91-tool-registry-launch.md
# Verify: BUILD SUCCEEDED; all built-in tools registered via ToolRegistry at launch
# Commit: Task 91 — Tool Registry Launch

# ── TASK 92 — Apply messageDensity to ChatView ───────────────────────────────
cat tasks/task-92-message-density-chat.md
# Verify: BUILD SUCCEEDED; message density setting applied to ChatView rows
# Commit: Task 92 — Message Density ChatView

# ── TASK 93 — Keep Awake (IOPMAssertion) ────────────────────────────────────
cat tasks/task-93-keep-awake.md
# Verify: BUILD SUCCEEDED; IOPMAssertion held while keepAwake is enabled
# Commit: Task 93 — Keep Awake

# ── TASK 94 — Notifications Enabled Guard ───────────────────────────────────
cat tasks/task-94-notifications-enabled-guard.md
# Verify: BUILD SUCCEEDED; NotificationEngine gated on notificationsEnabled setting
# Commit: Task 94 — Notifications Enabled Guard

# ── TASK 95 — Default Permission Mode ───────────────────────────────────────
cat tasks/task-95-default-permission-mode.md
# Verify: BUILD SUCCEEDED; defaultPermissionMode applied to new sessions
# Commit: Task 95 — Default Permission Mode

# ── TASK 96 — AgentRegistry Launch Registration ─────────────────────────────
cat tasks/task-96-agent-registry-launch.md
# Verify: BUILD SUCCEEDED; AgentRegistry.registerBuiltins() called at launch
# Commit: Task 96 — AgentRegistry Launch

# ── TASK 97 — HookEngine Main Loop Wiring ───────────────────────────────────
cat tasks/task-97-hook-engine-main-loop.md
# Verify: BUILD SUCCEEDED; HookEngine wired into AgenticEngine main loop
# Commit: Task 97 — HookEngine Main Loop Wiring

# ── TASK 98 — Apply AppTheme + Font Settings to UI ──────────────────────────
cat tasks/task-98-appearance-application.md
# Verify: BUILD SUCCEEDED; AppTheme and font settings applied throughout UI
# Commit: Task 98 — Appearance Application

# ── DONE (v4 complete) ────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 5 — Supervisor-Worker Multi-LLM + Domain Plugin System
# ════════════════════════════════════════════════════════════════════════════

# ── TASK 99a — DomainRegistry + DomainPlugin Tests ───────────────────────────
cat tasks/task-99a-domain-registry-tests.md
# Verify: BUILD FAILED — DomainRegistry, DomainPlugin, DomainTaskType, DomainManifest, MCPDomainAdapter not defined (expected)
# Commit: Task 99a — DomainRegistryTests + DomainManifestTests (failing)

# ── TASK 99b — DomainRegistry + DomainPlugin + MCPDomainAdapter + SoftwareDomain ──
cat tasks/task-99b-domain-registry.md
# Verify: BUILD SUCCEEDED; DomainRegistryTests → 5 pass; DomainManifestTests → 2 pass
# Commit: Task 99b — DomainRegistry + DomainPlugin + MCPDomainAdapter + SoftwareDomain

# ── TASK 100a — AgenticEngine Role Slot Routing Tests ────────────────────────
cat tasks/task-100a-role-slot-routing-tests.md
# Verify: BUILD FAILED — AgentSlot, AgenticEngine slot init not defined (expected)
# Commit: Task 100a — AgenticEngineSlotTests (failing)

# ── TASK 100b — AgenticEngine Role Slot Routing ──────────────────────────────
cat tasks/task-100b-role-slot-routing.md
# Verify: BUILD SUCCEEDED; AgenticEngineSlotTests → 7 pass; zero warnings
# Commit: Task 100b — AgenticEngine role slot routing (execute/reason/orchestrate/vision)

# ── TASK 101a — ModelPerformanceTracker Tests ────────────────────────────────
cat tasks/task-101a-performance-tracker-tests.md
# Verify: BUILD FAILED — OutcomeSignals, ModelPerformanceTracker not defined (expected)
# Commit: Task 101a — ModelPerformanceTrackerTests (failing)

# ── TASK 101b — ModelPerformanceTracker ──────────────────────────────────────
cat tasks/task-101b-performance-tracker.md
# Verify: BUILD SUCCEEDED; ModelPerformanceTrackerTests → 6 pass; zero warnings
# Commit: Task 101b — ModelPerformanceTracker

# ── TASK 102a — CriticEngine Tests ───────────────────────────────────────────
cat tasks/task-102a-critic-engine-tests.md
# Verify: BUILD FAILED — CriticResult, CriticEngine, ShellRunning not defined (expected)
# Commit: Task 102a — CriticEngineTests (failing)

# ── TASK 102b — CriticEngine (Stage 1 + Stage 2) ────────────────────────────
cat tasks/task-102b-critic-engine.md
# Verify: BUILD SUCCEEDED; CriticEngineTests → 5 pass; zero warnings
# Commit: Task 102b — CriticEngine (Stage 1 domain verification + Stage 2 reason slot)

# ── TASK 103a — PlannerEngine Tests ──────────────────────────────────────────
cat tasks/task-103a-planner-tests.md
# Verify: BUILD FAILED — ComplexityTier, ClassifierResult, PlannerEngine, PlanStep not defined (expected)
# Commit: Task 103a — PlannerEngineTests (failing)

# ── TASK 103b — PlannerEngine ────────────────────────────────────────────────
cat tasks/task-103b-planner-engine.md
# Verify: BUILD SUCCEEDED; PlannerEngineTests → 7 pass; zero warnings
# Commit: Task 103b — PlannerEngine

# ── TASK 104a — System Prompt Addendum Tests ─────────────────────────────────
cat tasks/task-104a-system-prompt-addendum-tests.md
# Verify: BUILD FAILED — ProviderConfig.systemPromptAddendum, String.addendumHash, buildSystemPromptForTesting not defined (expected)
# Commit: Task 104a — SystemPromptAddendumTests (failing)

# ── TASK 104b — System Prompt Addendum ───────────────────────────────────────
cat tasks/task-104b-system-prompt-addendum.md
# Verify: BUILD SUCCEEDED; SystemPromptAddendumTests → 7 pass; all prior tests pass
# Commit: Task 104b — system_prompt_addendum injection

# ── TASK 105a — V5 AgenticEngine Run Loop Tests ──────────────────────────────
cat tasks/task-105a-v5-runloop-tests.md
# Verify: BUILD FAILED — protocols and engine test hooks not defined (expected)
# Commit: Task 105a — AgenticEngineV5Tests (failing)

# ── TASK 105b — V5 AgenticEngine Run Loop ────────────────────────────────────
cat tasks/task-105b-v5-runloop.md
# Verify: BUILD SUCCEEDED; AgenticEngineV5Tests → 6 pass; all prior tests pass
# Commit: Task 105b — V5 AgenticEngine run loop (planner + critic + tracker + memory write)

# ── TASK 106a — V5 Settings UI Tests ────────────────────────────────────────
cat tasks/task-106a-v5-settings-ui-tests.md
# Verify: BUILD FAILED — RoleSlotSettingsView, PerformanceDashboardView, AppSettings new properties not defined (expected)
# Commit: Task 106a — V5SettingsUITests (failing)

# ── TASK 106b — V5 Settings UI ──────────────────────────────────────────────
cat tasks/task-106b-v5-settings-ui.md
# Verify: BUILD SUCCEEDED; V5SettingsUITests → all pass; Settings UI renders
# Commit: Task 106b — V5 Settings UI (role slot assignment + domain selector + performance dashboard)

# ── TASK 107a — V5 Skill Frontmatter Tests ───────────────────────────────────
cat tasks/task-107a-skill-frontmatter-v5-tests.md
# Verify: BUILD FAILED — SkillFrontmatter.role, SkillFrontmatter.complexity not defined (expected)
# Commit: Task 107a — SkillFrontmatterV5Tests (failing)

# ── TASK 107b — V5 Skill Frontmatter ─────────────────────────────────────────
cat tasks/task-107b-skill-frontmatter-v5.md
# Verify: BUILD SUCCEEDED; SkillFrontmatterV5Tests → 6 pass; zero warnings
# Commit: Task 107b — Skill frontmatter role: and complexity: declarations

# ── DONE (v5 core) ────────────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass
#        xcodebuild -scheme Merlin → zero errors, zero warnings

# VERSION 5 — RAG Memory Extension
# ════════════════════════════════════════════════════════════════════════════
# Prereq: xcalibre Task 18 shipped (POST /api/v1/memory, GET /api/v1/search/chunks?source=all)

# ── TASK 108a — RAG Source Attribution Tests ─────────────────────────────────
cat tasks/task-108a-rag-source-attribution-tests.md
# Verify: BUILD FAILED — AgentEvent.ragSources not defined; RAGSourcesView not defined (expected)
# Commit: Task 108a — RAGSourceAttributionTests (failing)

# ── TASK 108b — RAG Source Attribution ───────────────────────────────────────
cat tasks/task-108b-rag-source-attribution.md
# Verify: BUILD SUCCEEDED; RAGSourceAttributionTests → 4 pass; all prior tests pass
# Commit: Task 108b — RAG source attribution (.ragSources event + Sources footer in chat)

# ── TASK 109a — Project Path AppSettings Tests ───────────────────────────────
cat tasks/task-109a-project-path-tests.md
# Verify: BUILD FAILED — AppSettings.projectPath not defined; serializedTOML/applyTOML mismatch (expected)
# Commit: Task 109a — ProjectPathSettingsTests (failing)

# ── TASK 109b — Project Path AppSettings Wiring ──────────────────────────────
cat tasks/task-109b-project-path.md
# Verify: BUILD SUCCEEDED; ProjectPathSettingsTests → all pass; all prior tests pass
# Commit: Task 109b — AppSettings.projectPath wired into engine and Settings UI

# ── TASK 110a — Memory Browser Tests ─────────────────────────────────────────
cat tasks/task-110a-memory-browser-tests.md
# Verify: BUILD FAILED — XcalibreClient.searchMemory not defined; MemoryBrowserView not defined (expected)
# Commit: Task 110a — MemoryBrowserTests (failing)

# ── TASK 110b — Memory Browser ───────────────────────────────────────────────
cat tasks/task-110b-memory-browser.md
# Verify: BUILD SUCCEEDED; MemoryBrowserTests → 5 pass; all prior tests pass
# Commit: Task 110b — Memory browser (searchMemory convenience + MemoryBrowserView)

# ── TASK 111a — rag_search Tool Source/ProjectPath Tests ─────────────────────
cat tasks/task-111a-rag-search-tool-tests.md
# Verify: BUILD FAILED — RAGTools.search signature mismatch; Args.source not defined (expected)
# Commit: Task 111a — RAGSearchToolTests (failing)

# ── TASK 111b — rag_search Tool Source/ProjectPath ───────────────────────────
cat tasks/task-111b-rag-search-tool.md
# Verify: BUILD SUCCEEDED; RAGSearchToolTests → 6 pass; all prior tests pass
# Commit: Task 111b — rag_search tool: source + project_path parameters

# ── TASK 112a — RAG Settings Tests ──────────────────────────────────────────
cat tasks/task-112a-rag-settings-tests.md
# Verify: BUILD FAILED — AppSettings.ragRerank, AppSettings.ragChunkLimit not defined (expected)
# Commit: Task 112a — RAGSettingsTests (failing)

# ── TASK 112b — RAG Settings ─────────────────────────────────────────────────
cat tasks/task-112b-rag-settings.md
# Verify: BUILD SUCCEEDED; RAGSettingsTests → all pass; all prior tests pass
# Commit: Task 112b — ragRerank + ragChunkLimit configurable (default off, safe for RTX 2070)

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

# ── TASK 113a — OutcomeRecord Persistence Tests ──────────────────────────────
cat tasks/task-113a-outcome-record-persistence-tests.md
# Verify: BUILD FAILED — ModelPerformanceTracker.records(for:taskType:) and
#         ModelPerformanceTracker.exportTrainingData(minScore:) not defined (expected)
# Commit: Task 113a — OutcomeRecordPersistenceTests (failing)

# ── TASK 113b — OutcomeRecord Persistence ────────────────────────────────────
cat tasks/task-113b-outcome-record-persistence.md
# Verify: BUILD SUCCEEDED; OutcomeRecordPersistenceTests → 6 pass; all prior tests pass
# Commit: Task 113b — OutcomeRecord persistence (V6 training data survives restarts)

# ── TASK 114a — StagingBuffer OutcomeSignals Tests ───────────────────────────
cat tasks/task-114a-staging-buffer-signals-tests.md
# Verify: BUILD FAILED — StagingBuffer.acceptedCount, rejectedCount,
#         editedOnAcceptCount, resetSessionCounts() not defined (expected)
# Commit: Task 114a — StagingBufferSignalsTests (failing)

# ── TASK 114b — StagingBuffer OutcomeSignals Wiring ──────────────────────────
cat tasks/task-114b-staging-buffer-signals.md
# Verify: BUILD SUCCEEDED; StagingBufferSignalsTests → 9 pass; all prior tests pass
# Commit: Task 114b — StagingBuffer accept/reject wired into OutcomeSignals

# ── TASK 115a — Critic-Gated Memory Tests ────────────────────────────────────
cat tasks/task-115a-critic-gated-memory-tests.md
# Verify: BUILD FAILED — AgenticEngine.lastCriticVerdict not defined (expected)
# Commit: Task 115a — CriticGatedMemoryTests (failing)

# ── TASK 115b — Critic-Gated Memory Write ────────────────────────────────────
cat tasks/task-115b-critic-gated-memory.md
# Verify: BUILD SUCCEEDED; CriticGatedMemoryTests → 7 pass; all prior tests pass
# Commit: Task 115b — critic-gated memory write (suppress xcalibre write on critic .fail)

# ── DONE (v5 loose ends) ──────────────────────────────────────────────────────
# Final: xcodebuild -scheme MerlinTests → all unit + integration pass; zero warnings

# ════════════════════════════════════════════════════════════════════════════
# VERSION 6 — LoRA Self-Training (MLX-LM on M4 Mac)
# ════════════════════════════════════════════════════════════════════════════
# Hardware: M4 Mac 128 GB unified memory (already present)
# Prereq: python -m mlx_lm installed; base model downloaded via mlx_lm
# All features default-off (loraEnabled = false). App builds and ships cleanly
# with everything disabled.

# ── TASK 116a — LoRA AppSettings Tests ──────────────────────────────────────
cat tasks/task-116a-lora-appsettings-tests.md
# Verify: BUILD FAILED — AppSettings.loraEnabled (and 6 other properties) not defined (expected)
# Commit: Task 116a — LoRASettingsTests (failing)

# ── TASK 116b — LoRA AppSettings ────────────────────────────────────────────
cat tasks/task-116b-lora-appsettings.md
# Verify: BUILD SUCCEEDED; LoRASettingsTests → 10 pass; all prior tests pass
# Commit: Task 116b — LoRA AppSettings (loraEnabled + 6 sub-settings, [lora] TOML section)

# ── TASK 117a — OutcomeRecord Training Fields Tests ─────────────────────────
cat tasks/task-117a-outcome-record-training-fields-tests.md
# Verify: BUILD FAILED — OutcomeRecord.prompt, OutcomeRecord.response not defined (expected)
# Commit: Task 117a — OutcomeRecordTrainingFieldsTests (failing)

# ── TASK 117b — OutcomeRecord Training Fields ────────────────────────────────
cat tasks/task-117b-outcome-record-training-fields.md
# Verify: BUILD SUCCEEDED; OutcomeRecordTrainingFieldsTests → 6 pass; all prior tests pass
# Commit: Task 117b — OutcomeRecord prompt/response fields; record() captures conversation text

# ── TASK 118a — LoRATrainer Tests ───────────────────────────────────────────
cat tasks/task-118a-lora-trainer-tests.md
# Verify: BUILD FAILED — LoRATrainer, LoRATrainingResult, ShellRunnerProtocol not defined (expected)
# Commit: Task 118a — LoRATrainerTests (failing)

# ── TASK 118b — LoRATrainer ──────────────────────────────────────────────────
cat tasks/task-118b-lora-trainer.md
# Verify: BUILD SUCCEEDED; LoRATrainerTests → 5 pass; all prior tests pass
# Commit: Task 118b — LoRATrainer (JSONL export + mlx_lm.lora shell invocation)

# ── TASK 119a — LoRACoordinator Tests ───────────────────────────────────────
cat tasks/task-119a-lora-coordinator-tests.md
# Verify: BUILD FAILED — LoRACoordinator not defined (expected)
# Commit: Task 119a — LoRACoordinatorTests (failing)

# ── TASK 119b — LoRACoordinator ─────────────────────────────────────────────
cat tasks/task-119b-lora-coordinator.md
# Verify: BUILD SUCCEEDED; LoRACoordinatorTests → 4 pass; all prior tests pass
# Commit: Task 119b — LoRACoordinator (threshold-gated auto-train trigger, concurrent-safe)

# ── TASK 120a — LoRA Provider Routing Tests ─────────────────────────────────
cat tasks/task-120a-lora-provider-routing-tests.md
# Verify: BUILD FAILED — AgenticEngine.loraProvider not defined (expected)
# Commit: Task 120a — LoRAProviderRoutingTests (failing)

# ── TASK 120b — LoRA Provider Routing ───────────────────────────────────────
cat tasks/task-120b-lora-provider-routing.md
# Verify: BUILD SUCCEEDED; LoRAProviderRoutingTests → 4 pass; all prior tests pass
# Commit: Task 120b — LoRA provider routing (execute slot → mlx_lm.server when adapter loaded)

# ── TASK 121a — LoRA Settings UI Tests ──────────────────────────────────────
cat tasks/task-121a-lora-settings-ui-tests.md
# Verify: BUILD FAILED — LoRASettingsSection not defined (expected)
# Commit: Task 121a — LoRASettingsUITests (failing)

# ── TASK 121b — LoRA Settings UI ────────────────────────────────────────────
cat tasks/task-121b-lora-settings-ui.md
# Verify: BUILD SUCCEEDED; LoRASettingsUITests → 4 pass; all prior tests pass
# Commit: Task 121b — LoRA Settings UI (master toggle + training config + status row)

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

# ── TASK 123a — Sampling Params Tests ───────────────────────────────────────
cat tasks/task-123a-sampling-params-tests.md
# Verify: BUILD FAILED — CompletionRequest.topK etc. not defined (expected)
# Commit: Task 123a — CompletionRequestSamplingParamsTests (failing)

# ── TASK 123b — Sampling Params Implementation ───────────────────────────────
cat tasks/task-123b-sampling-params.md
# Verify: BUILD SUCCEEDED; CompletionRequestSamplingParamsTests → 13 pass; all prior tests pass
# Commit: Task 123b — expand CompletionRequest with 8 sampling params; AppSettings inference defaults

# ── TASK 124a — ModelParameterAdvisor Tests ─────────────────────────────────
cat tasks/task-124a-parameter-advisor-tests.md
# Verify: BUILD FAILED — ModelParameterAdvisor, ParameterAdvisory not defined (expected)
# Commit: Task 124a — ModelParameterAdvisorTests (failing)

# ── TASK 124b — ModelParameterAdvisor Implementation ────────────────────────
cat tasks/task-124b-parameter-advisor.md
# Verify: BUILD SUCCEEDED; ModelParameterAdvisorTests → 12 pass; all prior tests pass
# Commit: Task 124b — ModelParameterAdvisor (truncation, variance, repetition, context overflow)

# ── V6 LOOSE END — Memory → xcalibre RAG indexing ────────────────────────────
# ── TASK 122a — Memory Xcalibre Index Tests ─────────────────────────────────
cat tasks/task-122a-memory-xcalibre-index-tests.md
# Verify: BUILD FAILED — MemoryEngine has no setXcalibreClient method (expected)
# Commit: Task 122a — MemoryXcalibreIndexTests (failing)

# ── TASK 122b — Memory Xcalibre Index ───────────────────────────────────────
cat tasks/task-122b-memory-xcalibre-index.md
# Verify: BUILD SUCCEEDED; MemoryXcalibreIndexTests → 6 pass; all prior tests pass
# Commit: Task 122b — approved memories indexed in xcalibre-server as factual RAG chunks

# ── V7 Local Model Management ─────────────────────────────────────────────────
# Unified LocalModelManagerProtocol across all 6 local providers (LM Studio, Ollama,
# Jan, LocalAI, Mistral.rs, vLLM-Metal). Runtime reload where supported; restart instructions
# where not. AppState registry + ApplyAdvisory routing. ModelControlView UI.

# ── TASK 125a — LocalModelManagerProtocol Tests ─────────────────────────────
cat tasks/task-125a-local-model-manager-protocol-tests.md
# Verify: BUILD FAILED — LocalModelManagerProtocol, LoadParam, LocalModelConfig etc. not defined (expected)
# Commit: Task 125a — LocalModelManagerProtocolTests (failing)

# ── TASK 125b — LocalModelManagerProtocol + LMStudio + Ollama ───────────────
cat tasks/task-125b-local-model-manager-protocol.md
# Verify: BUILD SUCCEEDED; LocalModelManagerProtocolTests → 22 pass; all prior tests pass
# Commit: Task 125b — LocalModelManagerProtocol + LMStudioModelManager + OllamaModelManager

# ── TASK 126a — Extended Provider Manager Tests ─────────────────────────────
cat tasks/task-126a-local-model-manager-extended-tests.md
# Verify: BUILD FAILED — JanModelManager, LocalAIModelManager, MistralRSModelManager, VLLMModelManager not defined (expected)
# Commit: Task 126a — LocalModelManagerExtendedTests (failing)

# ── TASK 126b — Jan, LocalAI, MistralRS, vLLM-Metal Managers ─────────────────────
cat tasks/task-126b-local-model-manager-extended.md
# Verify: BUILD SUCCEEDED; LocalModelManagerExtendedTests → 20 pass; all prior tests pass
# Commit: Task 126b — Jan/LocalAI/MistralRS/vLLM-Metal model managers

# ── TASK 127a — Model Manager Wiring Tests ──────────────────────────────────
cat tasks/task-127a-model-manager-wiring-tests.md
# Verify: BUILD FAILED — AppState.localModelManagers, applyAdvisory, AgenticEngine.isReloadingModel not defined (expected)
# Commit: Task 127a — ModelManagerWiringTests (failing)

# ── TASK 127b — Model Manager Wiring ────────────────────────────────────────
cat tasks/task-127b-model-manager-wiring.md
# Verify: BUILD SUCCEEDED; ModelManagerWiringTests → 9 pass; all prior tests pass
# Commit: Task 127b — model manager wiring: AppState registry, applyAdvisory, engine reload pause

# ── TASK 128a — Model Control UI Tests ──────────────────────────────────────
cat tasks/task-128a-model-control-ui-tests.md
# Verify: BUILD FAILED — ModelControlView, RestartInstructionsSheet, ModelControlSectionView not defined (expected)
# Commit: Task 128a — ModelControlViewTests (failing)

# ── TASK 128b — Model Control UI ────────────────────────────────────────────
cat tasks/task-128b-model-control-ui.md
# Verify: BUILD SUCCEEDED; ModelControlViewTests → 6 pass; all prior tests pass
# Commit: Task 128b — ModelControlView: per-provider load param editor + restart instructions sheet

# ── TASK 132 — V7 Documentation & Code Comment Update ───────────────────────
cat tasks/task-132-v7-docs.md
# Verify: BUILD SUCCEEDED; zero warnings; all prior tests pass
# Commit: Task 132 — V7 docs + code comments: inference params, ModelParameterAdvisor, LocalModelManagerProtocol, ModelControlView

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

# ── TASK 129a — CalibrationRunner Tests ─────────────────────────────────────
cat tasks/task-129a-calibration-runner-tests.md
# Verify: BUILD FAILED — CalibrationCategory, CalibrationPrompt, CalibrationResponse,
#         CalibrationReport, CalibrationSuite, CalibrationRunner not defined (expected)
# Commit: Task 129a — CalibrationRunnerTests (failing)

# ── TASK 129b — CalibrationRunner Implementation ────────────────────────────
cat tasks/task-129b-calibration-runner.md
# Verify: BUILD SUCCEEDED; CalibrationRunnerTests → 14 pass; all prior tests pass
# Commit: Task 129b — CalibrationTypes + CalibrationSuite (18-prompt battery) + CalibrationRunner

# ── TASK 130a — CalibrationAdvisor Tests ────────────────────────────────────
cat tasks/task-130a-calibration-advisor-tests.md
# Verify: BUILD FAILED — CalibrationAdvisor, CategoryScores not defined (expected)
# Commit: Task 130a — CalibrationAdvisorTests (failing)

# ── TASK 130b — CalibrationAdvisor Implementation ───────────────────────────
cat tasks/task-130b-calibration-advisor.md
# Verify: BUILD SUCCEEDED; CalibrationAdvisorTests → 14 pass; all prior tests pass
# Commit: Task 130b — CalibrationAdvisor: maps score gaps to ParameterAdvisory

# ── TASK 131a — Calibration Skill & UI Tests ────────────────────────────────
cat tasks/task-131a-calibration-skill-tests.md
# Verify: BUILD FAILED — CalibrationCoordinator, CalibrationSheet, CalibrationProgressInfo,
#         CalibrationProviderPickerView, CalibrationProgressView, CalibrationReportView,
#         AppState.calibrationCoordinator not defined (expected)
# Commit: Task 131a — CalibrationSkillTests (failing)

# ── TASK 131b — Calibration Skill & UI Implementation ───────────────────────
cat tasks/task-131b-calibration-skill.md
# Verify: BUILD SUCCEEDED; CalibrationSkillTests → 9 pass; all prior tests pass
# Commit: Task 131b — /calibrate skill: provider picker, runner wiring, report view with apply-all

# ── TASK 133 — V8 Documentation & Code Comment Update ───────────────────────
cat tasks/task-133-v8-docs.md
# Verify: BUILD SUCCEEDED; zero warnings; all prior tests pass
# Commit: Task 133 — V8 docs + code comments: CalibrationSuite, CalibrationRunner, CalibrationAdvisor, CalibrationCoordinator, report views

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

# ── TASK 134a — MemoryBackendPlugin Protocol Tests ──────────────────────────
Read tasks/task-134a-memory-backend-plugin-tests.md and execute.
# Verify: BUILD FAILED — MemoryChunk, MemorySearchResult, MemoryBackendPlugin,
#         MemoryBackendRegistry, NullMemoryPlugin not defined (expected)
# Commit: Task 134a — MemoryBackendPlugin tests (failing)

# ── TASK 134b — MemoryBackendPlugin Protocol Implementation ─────────────────
Read tasks/task-134b-memory-backend-plugin.md and execute.
# Verify: BUILD SUCCEEDED; all 134a tests pass; zero warnings
# Commit: Task 134b — MemoryBackendPlugin: protocol, registry, NullMemoryPlugin

# ── TASK 135a — LocalVectorPlugin Tests ─────────────────────────────────────
Read tasks/task-135a-local-vector-plugin-tests.md and execute.
# Verify: BUILD FAILED — EmbeddingProviderProtocol, LocalVectorPlugin not defined (expected)
# Commit: Task 135a — LocalVectorPlugin tests (failing)

# ── TASK 135b — LocalVectorPlugin Implementation ────────────────────────────
Read tasks/task-135b-local-vector-plugin.md and execute.
# Verify: BUILD SUCCEEDED; all 135a tests pass; zero warnings
# Commit: Task 135b — LocalVectorPlugin: SQLite + NLContextualEmbedding cosine search

# ── TASK 136a — MemoryEngine Backend Wiring Tests ───────────────────────────
Read tasks/task-136a-memory-engine-backend-wiring-tests.md and execute.
# Verify: BUILD FAILED — MemoryEngine.setMemoryBackend not defined (expected)
# Commit: Task 136a — MemoryEngine backend wiring tests (failing)

# ── TASK 136b — MemoryEngine Backend Wiring ─────────────────────────────────
Read tasks/task-136b-memory-engine-backend-wiring.md and execute.
# Verify: BUILD SUCCEEDED; all 136a tests pass; zero warnings
# Commit: Task 136b — MemoryEngine: replace xcalibre write with MemoryBackendPlugin

# ── TASK 137a — AgenticEngine Memory Plugin Tests ───────────────────────────
Read tasks/task-137a-agenticengine-memory-plugin-tests.md and execute.
# Verify: BUILD FAILED — AgenticEngine.setMemoryBackend not defined (expected)
# Commit: Task 137a — AgenticEngine memory plugin tests (failing)

# ── TASK 137b — AgenticEngine Memory Plugin Wiring ──────────────────────────
Read tasks/task-137b-agenticengine-memory-plugin.md and execute.
# Verify: BUILD SUCCEEDED; all 137a tests pass; zero warnings
# Commit: Task 137b — AgenticEngine: local memory plugin for writes + merged RAG search

# ── TASK 138a — Memory Backend AppSettings Wiring Tests ─────────────────────
Read tasks/task-138a-memory-backend-appsettings-tests.md and execute.
# Verify: BUILD FAILED — AppSettings.memoryBackendID, AppState.memoryRegistry not defined (expected)
# Commit: Task 138a — memory backend AppSettings wiring tests (failing)

# ── TASK 138b — Memory Backend AppSettings Wiring ───────────────────────────
Read tasks/task-138b-memory-backend-appsettings.md and execute.
# Verify: BUILD SUCCEEDED; all 138a tests pass; zero warnings
# Commit: Task 138b — AppSettings.memoryBackendID + AppState memory registry wiring

# ── TASK 139 — V9 Documentation & Code Comment Update ───────────────────────
Read tasks/task-139-v9-docs.md and execute.
# Verify: BUILD SUCCEEDED; zero warnings; all prior tests pass
# Commit: Task 139 — V9 docs + code comments: local memory store plugin system

# ── TASK 140a — Circuit Breaker Tests ───────────────────────────────────────
Read tasks/task-140a-circuit-breaker-tests.md and execute.
# Verify: BUILD FAILED — AgenticEngine.consecutiveCriticFailures,
#         AppSettings.agentCircuitBreakerThreshold not defined (expected)
# Commit: Task 140a — circuit breaker tests (failing)

# ── TASK 140b — Circuit Breaker Implementation ───────────────────────────────
Read tasks/task-140b-circuit-breaker.md and execute.
# Verify: BUILD SUCCEEDED; all 140a tests pass; zero warnings
# Commit: Task 140b — reasoning-layer circuit breaker: warn after N consecutive critic failures

# ── TASK 141a — Grounding Confidence Tests ──────────────────────────────────
Read tasks/task-141a-grounding-confidence-tests.md and execute.
# Verify: BUILD FAILED — GroundingReport, AgentEvent.groundingReport,
#         AppSettings.ragFreshnessThresholdDays, AppSettings.ragMinGroundingScore not defined (expected)
# Commit: Task 141a — grounding confidence signal tests (failing)

# ── TASK 141b — Grounding Confidence Implementation ─────────────────────────
Read tasks/task-141b-grounding-confidence.md and execute.
# Verify: BUILD SUCCEEDED; all 141a tests pass; zero warnings
# Commit: Task 141b — GroundingReport: per-turn grounding confidence signal

# ── TASK 142a — Semantic Fault Injection Tests ──────────────────────────────
Read tasks/task-142a-semantic-fault-injection-tests.md and execute.
# Verify: BUILD FAILED — StalenessInjectingMemoryBackend, TruncatingMockProvider,
#         EmptyToolResultRouter, DroppingContextManager not defined (expected)
# Commit: Task 142a — semantic fault injection tests (failing)

# ── TASK 142b — Semantic Fault Injection Implementation ─────────────────────
Read tasks/task-142b-semantic-fault-injection.md and execute.
# Verify: BUILD SUCCEEDED; all 142a tests pass; zero warnings
# Commit: Task 142b — semantic fault injection test doubles: stale retrieval, truncation, empty tools, context drop

# ── DONE (v9 Local Memory Store) ──────────────────────────────────────────────
# Memory is fully local: SQLite at ~/.merlin/memory.sqlite, embedded with Apple
# NLContextualEmbedding, retrieved by cosine similarity. xcalibre-server is now
# optional book-content only. Backend is swappable via Settings → Memory.
#
# Behavioral reliability (v9 additions,  tasks 140–142):
# - Circuit breaker (task 140): halt/warn after N consecutive critic failures
# - Grounding confidence signal (task 141): GroundingReport per turn
# - Semantic fault injection (task 142): test doubles for stale retrieval,
#   token pressure, empty tool results, context drop
# All four mitigations from "Context Decay, Orchestration Drift, and the Rise of
# Silent Failures in AI Systems" (VentureBeat, 2025) are implemented and documented.

# ── TASK 143a — Dynamic Model Fetch Tests ───────────────────────────────────
Read tasks/task-143a-dynamic-model-fetch-tests.md and execute.
# Verify: BUILD FAILED — dynamic model fetch symbols not defined (expected)
# Commit: Task 143a — dynamic model fetch tests (failing)

# ── TASK 143b — Dynamic Model Fetch ─────────────────────────────────────────
Read tasks/task-143b-dynamic-model-fetch.md and execute.
# Verify: BUILD SUCCEEDED; all 143a tests pass; zero warnings
# Commit: Task 143b — Dynamic model fetch

# ── TASK 144a — Virtual Provider ID Tests ───────────────────────────────────
Read tasks/task-144a-virtual-provider-id-tests.md and execute.
# Verify: BUILD FAILED — VirtualProviderID symbols not defined (expected)
# Commit: Task 144a — virtual provider ID tests (failing)

# ── TASK 144b — Virtual Provider IDs ────────────────────────────────────────
Read tasks/task-144b-virtual-provider-id.md and execute.
# Verify: BUILD SUCCEEDED; all 144a tests pass; zero warnings
# Commit: Task 144b — Virtual provider IDs, delete LMStudioProvider

# ── TASK 145a — Provider Routing Cleanup Tests ──────────────────────────────
Read tasks/task-145a-provider-routing-cleanup-tests.md and execute.
# Verify: BUILD FAILED — routing cleanup symbols not defined (expected)
# Commit: Task 145a — provider routing cleanup tests (failing)

# ── TASK 145b — Provider Routing Cleanup ────────────────────────────────────
Read tasks/task-145b-provider-routing-cleanup.md and execute.
# Verify: BUILD SUCCEEDED; all 145a tests pass; zero warnings
# Commit: Task 145b — Remove proProvider/flashProvider/visionProvider, simplify routing

# ── TASK 146a — Provider Settings UI Tests ──────────────────────────────────
Read tasks/task-146a-provider-settings-ui-tests.md and execute.
# Verify: BUILD FAILED — ProviderSettingsView symbols not defined (expected)
# Commit: Task 146a — provider settings UI tests (failing)

# ── TASK 146b — Provider Settings UI ────────────────────────────────────────
Read tasks/task-146b-provider-settings-ui.md and execute.
# Verify: BUILD SUCCEEDED; all 146a tests pass; zero warnings
# Commit: Task 146b — Provider settings UI with dynamic model picker

# ── TASK 147a — Adaptive Loop Ceiling Tests ─────────────────────────────────
Read tasks/task-147a-adaptive-loop-ceiling-tests.md and execute.
# Verify: BUILD FAILED — adaptive ceiling symbols not defined (expected)
# Commit: Task 147a — adaptive loop ceiling tests (failing)

# ── TASK 147b — Adaptive Loop Ceiling ───────────────────────────────────────
Read tasks/task-147b-adaptive-loop-ceiling.md and execute.
# Verify: BUILD SUCCEEDED; all 147a tests pass; zero warnings
# Commit: Task 147b — Adaptive loop ceiling based on project size

# ── TASK 148a — Document Verification Tests ─────────────────────────────────
Read tasks/task-148a-document-verification-tests.md and execute.
# Verify: BUILD FAILED — document verification symbols not defined (expected)
# Commit: Task 148a — document verification tests (failing)

# ── TASK 148b — Document Verification ───────────────────────────────────────
Read tasks/task-148b-document-verification.md and execute.
# Verify: BUILD SUCCEEDED; all 148a tests pass; zero warnings
# Commit: Task 148b — Two-tier document verification (truncation fix, firing condition, structured prompt, verdict parsing)

# ── TASK 149a — LM Studio Context Auto-Resize Tests ─────────────────────────
Read tasks/task-149a-lmstudio-context-autoresize-tests.md and execute.
# Verify: BUILD FAILED — ensureContextLength not defined (expected)
# Commit: Task 149a — LM Studio context auto-resize tests (failing)

# ── TASK 149b — LM Studio Context Auto-Resize ───────────────────────────────
Read tasks/task-149b-lmstudio-context-autoresize.md and execute.
# Verify: BUILD SUCCEEDED; all 149a tests pass; zero warnings
# Commit: Task 149b — LM Studio context auto-resize

# ── TASK 150a — Loop Continuation Tests ─────────────────────────────────────
Read tasks/task-150a-loop-continuation-tests.md and execute.
# Verify: BUILD SUCCEEDED; tests compile but LoopContinuationTests fail at runtime (expected)
# Commit: Task 150a — LoopContinuationTests (failing)

# ── TASK 150b — Loop Continuation and Near-Ceiling Warning ──────────────────
Read tasks/task-150b-loop-continuation.md and execute.
# Verify: BUILD SUCCEEDED; all 6 LoopContinuationTests pass; zero warnings
# Commit: Task 150b — loop continuation and near-ceiling warning

# ── TASK 166a — WKWebView Chat Renderer Tests ───────────────────────────────
Read tasks/task-166a-wkwebview-chat-tests.md and execute.
# Verify: BUILD FAILED — ConversationHTMLRenderer type missing (expected)
# Commit: Task 166a — ConversationHTMLRendererTests (failing)

# ── TASK 166b — WKWebView Chat Renderer Implementation ──────────────────────
Read tasks/task-166b-wkwebview-chat.md and execute.
# Verify: BUILD SUCCEEDED; all ConversationHTMLRendererTests pass
# Manual: drag-select text across multiple messages works
# Commit: Task 166b — WKWebView conversation renderer (cross-message selection)

# ── V1.5 — Session History & Archive ─────────────────────────────────────────

# ── TASK 181a — Session Archive Tests ───────────────────────────────────────
Read tasks/task-181a-session-archive-tests.md and execute.
# Verify: BUILD FAILED — Session.archived, SessionStore.scopedDirectoryName,
#         archive/unarchive, activeSessions, archivedSessions,
#         migrateLegacyIfNeeded not found (expected)
# Commit: Task 181a — SessionArchiveTests (failing)

# ── TASK 181b — Session Archive Implementation ───────────────────────────────
Read tasks/task-181b-session-archive.md and execute.
# Verify: BUILD SUCCEEDED; all SessionArchiveTests pass
# Commit: Task 181b — Session.archived + SessionStore project-scoped path + archive/unarchive

# ── TASK 182a — Session Restore Tests ───────────────────────────────────────
Read tasks/task-182a-session-restore-tests.md and execute.
# Verify: BUILD FAILED — ContextManager.load, SessionManager.restore,
#         SessionManager.sessionStore not found (expected)
# Commit: Task 182a — SessionRestoreTests (failing)

# ── TASK 182b — Session Restore Implementation ───────────────────────────────
Read tasks/task-182b-session-restore.md and execute.
# Verify: BUILD SUCCEEDED; all SessionRestoreTests pass
# Commit: Task 182b — ContextManager.load + LiveSession initial messages + SessionManager.restore

# ── TASK 183a — Session Sidebar Helper Tests ─────────────────────────────────
Read tasks/task-183a-session-sidebar-tests.md and execute.
# Verify: BUILD FAILED — RelativeTimestampFormatter not found (expected)
# Commit: Task 183a — SessionSidebarHelpersTests (failing)

# ── TASK 183b — Session Sidebar Implementation ───────────────────────────────
Read tasks/task-183b-session-sidebar.md and execute.
# Verify: BUILD SUCCEEDED; all SessionSidebarHelpersTests pass
# Manual: Prior Sessions section visible, archive/recall context menus work,
#         timestamps display correctly, Resume opens live session with history
# Commit: Task 183b — SessionSidebar Prior Sessions + archive/recall + timestamps

# ── TASK 184 — Version Bump to v1.5.0 ───────────────────────────────────────
Read tasks/task-184-version-bump-v1-5.md and execute.
# Verify: BUILD SUCCEEDED; About Merlin shows 1.5.0
# Commit: Bump version to 1.5.0 (build 4)
# Tag: v1.5.0

# ── DONE (v1.5 Session History & Archive) ─────────────────────────────────────
# Tasks 181–184 add session history and archive/recall to the sidebar:
# - 181: Session.archived field; SessionStore scoped per-project directory;
#   archive/unarchive/activeSessions/archivedSessions; legacy migration
# - 182: ContextManager.load for bulk message injection; LiveSession accepts
#   initialMessages + shared sessionStore; SessionManager.restore cold-restores
#   a persisted session as a new LiveSession with auto-compaction
# - 183: RelativeTimestampFormatter; SessionSidebar Prior Sessions section with
#   timestamps, archived collapse, context menus (Resume/Archive/Recall/Delete)
# - 184: Marketing version 1.5.0, build 4, tag v1.5.0

# ── V1.6 — Multi-Project Workspace + Session Auto-Labeling ───────────────────

# ── TASK 185a — WorkspaceCoordinator Tests ───────────────────────────────────
Read tasks/task-185a-workspace-coordinator-tests.md and execute.
# Verify: BUILD FAILED — WorkspaceCoordinator not found (expected)
# Commit: Task 185a — WorkspaceCoordinatorTests (failing)

# ── TASK 185b — WorkspaceCoordinator Implementation ─────────────────────────
Read tasks/task-185b-workspace-coordinator.md and execute.
# Verify: BUILD SUCCEEDED; all WorkspaceCoordinatorTests pass
# Commit: Task 185b — WorkspaceCoordinator: multi-project state, persistence, activeProjectManager

# ── TASK 186b — Multi-Project UI ────────────────────────────────────────────
Read tasks/task-186b-multiproject-ui.md and execute.
# Verify: BUILD SUCCEEDED, zero warnings
# Manual: single workspace window; picker sheet on first launch; project sections
#   in sidebar; project header popover (New Session / Close Project); terminal
#   and side chat follow active project; relaunch restores all open projects;
#   Cmd+N opens picker sheet
# Commit: Task 186b — Single-window multi-project: coordinator-driven UI, picker sheet, persistence

# ── TASK 187a — Session Title Tests ─────────────────────────────────────────
Read tasks/task-187a-session-title-tests.md and execute.
# Verify: BUILD FAILED — AgenticEngine.onTitleUpdate / applyTitleUpdateIfNeeded not found (expected)
# Commit: Task 187a — SessionTitleTests (failing)

# ── TASK 187b — Session Title Auto-Labeling ──────────────────────────────────
Read tasks/task-187b-session-title.md and execute.
# Verify: BUILD SUCCEEDED; all SessionTitleTests pass
# Manual: send first message in new session → sidebar label updates to message text
# Commit: Task 187b — Session title auto-labeling from first user message

# ── TASK 188 — Version Bump to v1.6.0 ───────────────────────────────────────
Read tasks/task-188-version-bump-v1-6.md and execute.
# Verify: BUILD SUCCEEDED; CFBundleShortVersionString == 1.6.0
# Commit: Bump version to 1.6.0 (build 5)
# Tag: v1.6.0

# ── TASK 189 — Crash Fix: ChatView + Version Bump to v1.6.1 ─────────────────
Read tasks/task-189-crash-fix-chatview-v1-6-1.md and execute.
# Fix: ChatView @EnvironmentObject SessionManager → @FocusedObject; WorkspaceView exposes activeManager
# Verify: BUILD SUCCEEDED; CFBundleShortVersionString == 1.6.1; app launches without trapping
# Commit: Bump version to 1.6.1 (build 6) — patch fix for ChatView crash
# Tag: v1.6.1

# ── DONE (v1.6 Multi-Project Workspace) ───────────────────────────────────────
# Tasks 185–189:
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
# Tasks 143–150 close two categories of silent failure:
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
# Tasks 205–207 add three-layer prompt compression to keep per-turn cost linear:
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
# Task 208 establishes the first implementation contracts for the v2.0
# Electronics/KiCad feature set.
#
# IMPORTANT for Merlin execution:
# Do not run  tasks 209–218 in a single prompt. Use:
#   tasks/RUN-209-218-BATCHES.md
# and execute one A/B pair per turn, compacting or starting a fresh turn between pairs.

# ── TASK 208a — KiCad Core Contracts Tests ────────────────────────────────
Read tasks/task-208a-merlin-v2-kicad-core-contracts-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad v2.0 core-contract symbols
# Commit: Task 208a — KiCadV2CoreContractsTests (failing)

# ── TASK 208b — KiCad Core Contracts ──────────────────────────────────────
Read tasks/task-208b-merlin-v2-kicad-core-contracts.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadV2CoreContractsTests pass
# Commit: Task 208b — Merlin v2.0 KiCad core contracts

# ── TASK 209a — KiCad MCP Tooling Boundary Tests ──────────────────────────
Read tasks/task-209a-kicad-mcp-tooling-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad MCP tooling symbols
# Commit: Task 209a — KiCadMCPToolingTests (failing)

# ── TASK 209b — KiCad MCP Tooling Boundary ────────────────────────────────
Read tasks/task-209b-kicad-mcp-tooling.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadMCPToolingTests pass
# Commit: Task 209b — KiCad MCP tooling boundary

# ── TASK 210a — KiCad Artifact Schemas Tests ──────────────────────────────
Read tasks/task-210a-kicad-artifact-schemas-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad artifact schema/store symbols
# Commit: Task 210a — KiCadArtifactSchemasTests (failing)

# ── TASK 210b — KiCad Artifact Schemas ────────────────────────────────────
Read tasks/task-210b-kicad-artifact-schemas.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadArtifactSchemasTests pass
# Commit: Task 210b — KiCad artifact schemas and store

# ── TASK 211a — KiCad Schematic Parser Tests ──────────────────────────────
Read tasks/task-211a-kicad-schematic-parser-tests.md and execute.
# Verify: BUILD FAILED with missing KiCad schematic parser symbols
# Commit: Task 211a — KiCadSchematicParserTests (failing)

# ── TASK 211b — KiCad Schematic Parser ────────────────────────────────────
Read tasks/task-211b-kicad-schematic-parser.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadSchematicParserTests pass
# Commit: Task 211b — KiCad schematic parser and writer

# ── TASK 212a — Schematic Extraction Policy Tests ─────────────────────────
Read tasks/task-212a-schematic-extraction-policy-tests.md and execute.
# Verify: BUILD FAILED with missing schematic extraction policy symbols
# Commit: Task 212a — SchematicExtractionPolicyTests (failing)

# ── TASK 212b — Schematic Extraction Policy ───────────────────────────────
Read tasks/task-212b-schematic-extraction-policy.md and execute.
# Verify: BUILD SUCCEEDED; all SchematicExtractionPolicyTests pass
# Commit: Task 212b — schematic extraction policy and clarification planning

# ── TASK 213a — Components/Footprints/BOM Tests ───────────────────────────
Read tasks/task-213a-components-footprints-bom-tests.md and execute.
# Verify: BUILD FAILED with missing component/footprint/BOM policy symbols
# Commit: Task 213a — ComponentsFootprintsBOMTests (failing)

# ── TASK 213b — Components/Footprints/BOM ─────────────────────────────────
Read tasks/task-213b-components-footprints-bom.md and execute.
# Verify: BUILD SUCCEEDED; all ComponentsFootprintsBOMTests pass
# Commit: Task 213b — components footprints libraries and BOM policy

# ── TASK 214a — Board/Routing Policy Tests ────────────────────────────────
Read tasks/task-214a-board-routing-policy-tests.md and execute.
# Verify: BUILD FAILED with missing board/routing policy symbols
# Commit: Task 214a — BoardRoutingPolicyTests (failing)

# ── TASK 214b — Board/Routing Policy ──────────────────────────────────────
Read tasks/task-214b-board-routing-policy.md and execute.
# Verify: BUILD SUCCEEDED; all BoardRoutingPolicyTests pass
# Commit: Task 214b — board profiles net classes placement and routing policy

# ── TASK 215a — Verification/Fab Policy Tests ─────────────────────────────
Read tasks/task-215a-verification-fab-policy-tests.md and execute.
# Verify: BUILD FAILED with missing verification/fab policy symbols
# Commit: Task 215a — VerificationFabPolicyTests (failing)

# ── TASK 215b — Verification/Fab Policy ───────────────────────────────────
Read tasks/task-215b-verification-fab-policy.md and execute.
# Verify: BUILD SUCCEEDED; all VerificationFabPolicyTests pass
# Commit: Task 215b — verification gates fabrication and visual QA policy

# ── TASK 216a — Vendor Order/Approval Tests ───────────────────────────────
Read tasks/task-216a-vendor-order-approval-tests.md and execute.
# Verify: BUILD FAILED with missing vendor/order/approval symbols
# Commit: Task 216a — VendorOrderApprovalTests (failing)

# ── TASK 216b — Vendor Order/Approval ─────────────────────────────────────
Read tasks/task-216b-vendor-order-approval.md and execute.
# Verify: BUILD SUCCEEDED; all VendorOrderApprovalTests pass
# Commit: Task 216b — vendor BOM order and electronics approval policy

# ── TASK 217a — KiCad Workflow Orchestration Tests ────────────────────────
Read tasks/task-217a-kicad-workflow-orchestration-tests.md and execute.
# Verify: BUILD FAILED with missing workflow orchestration symbols
# Commit: Task 217a — KiCadWorkflowOrchestrationTests (failing)

# ── TASK 217b — KiCad Workflow Orchestration ──────────────────────────────
Read tasks/task-217b-kicad-workflow-orchestration.md and execute.
# Verify: BUILD SUCCEEDED; all KiCadWorkflowOrchestrationTests pass
# Commit: Task 217b — KiCad workflow orchestration

# ── TASK 218a — Merlin v2.0 Version Release Tests ─────────────────────────
Read tasks/task-218a-merlin-v2-version-release-tests.md and execute.
# Verify: BUILD FAILED until version/release artifacts are bumped
# Commit: Task 218a — MerlinV2VersionTests (failing)

# ── TASK 218b — Merlin v2.0 Version Release ───────────────────────────────
Read tasks/task-218b-merlin-v2-version-release.md and execute.
# Verify: BUILD SUCCEEDED; all MerlinV2VersionTests pass
# Commit: Task 218b — Merlin v2.0 version release
# Tag: v2.0.0
```

---

## Budget-Aware Execution (v2.1.0) - RELEASED v2.1.0

Run  tasks 232–240 in strict sequence. Each `a` is failing tests; each `b` is the implementation
that satisfies them. Do not skip a commit. Do not batch commits across  tasks. Task 240b tags
and publishes the v2.1.0 release.

```bash
# ── TASK 232a — Budget Telemetry Tests ────────────────────────────────────
Read tasks/task-232a-budget-telemetry-tests.md and execute.
# Verify: BUILD FAILED until telemetry surfaces land
# Commit: Task 232a — BudgetTelemetryTests (failing)

# ── TASK 232b — Budget Telemetry ──────────────────────────────────────────
Read tasks/task-232b-budget-telemetry.md and execute.
# Verify: BUILD SUCCEEDED; all task 232a tests pass
# Commit: Task 232b — Budget telemetry

# ── TASK 233a — ProviderBudget + Pre-Flight Tests ─────────────────────────
Read tasks/task-233a-provider-budget-preflight-tests.md and execute.
# Verify: BUILD FAILED until ProviderBudget/TokenEstimator/pre-flight land
# Commit: Task 233a — ProviderBudgetAndPreflightTests (failing)

# ── TASK 233b — ProviderBudget + Pre-Flight Gate ──────────────────────────
Read tasks/task-233b-provider-budget-preflight.md and execute.
# Verify: BUILD SUCCEEDED; all task 233a tests pass
# Commit: Task 233b — ProviderBudget and pre-flight gate

# ── TASK 234a — Working-Set Caps Tests ────────────────────────────────────
Read tasks/task-234a-working-set-caps-tests.md and execute.
# Verify: BUILD FAILED until per-component caps land
# Commit: Task 234a — WorkingSetCapsTests (failing)

# ── TASK 234b — Working-Set Caps ──────────────────────────────────────────
Read tasks/task-234b-working-set-caps.md and execute.
# Verify: BUILD SUCCEEDED; all task 234a tests pass
# Commit: Task 234b — Working-set caps

# ── TASK 235a — Adaptive RAG Tests ────────────────────────────────────────
Read tasks/task-235a-adaptive-rag-tests.md and execute.
# Verify: BUILD FAILED until RAGSelector lands
# Commit: Task 235a — AdaptiveRAGTests (failing)

# ── TASK 235b — Adaptive RAG ──────────────────────────────────────────────
Read tasks/task-235b-adaptive-rag.md and execute.
# Verify: BUILD SUCCEEDED; all task 235a tests pass
# Commit: Task 235b — Adaptive RAG

# ── TASK 236a — Enriched PlanStep + refineStep Tests ──────────────────────
Read tasks/task-236a-planstep-enrichment-refine-tests.md and execute.
# Verify: BUILD FAILED until enriched PlanStep and refineStep land
# Commit: Task 236a — EnrichedPlanStepAndRefineTests (failing)

# ── TASK 236b — Enriched PlanStep + refineStep ────────────────────────────
Read tasks/task-236b-planstep-enrichment-refine.md and execute.
# Verify: BUILD SUCCEEDED; all task 236a tests pass
# Commit: Task 236b — Enriched PlanStep and refineStep

# ── TASK 237a — Unified Executor Gate Tests ───────────────────────────────
Read tasks/task-237a-executor-gate-tests.md and execute.
# Verify: BUILD FAILED until EscalationHandler lands and recursive recovery is deleted
# Commit: Task 237a — UnifiedExecutorGateTests (failing)

# ── TASK 237b — Unified Executor Gate + Recovery Deletion ─────────────────
Read tasks/task-237b-executor-gate.md and execute.
# Verify: BUILD SUCCEEDED; all task 237a tests pass; no recursive runLoop self-call remains
# Commit: Task 237b — Unified executor gate, delete recursive recovery

# ── TASK 238a — Critic Gating Tests ───────────────────────────────────────
Read tasks/task-238a-critic-gating-tests.md and execute.
# Verify: BUILD FAILED until critic policy resolver and CriterionChecker land
# Commit: Task 238a — CriticGatingTests (failing)

# ── TASK 238b — Critic Gating ─────────────────────────────────────────────
Read tasks/task-238b-critic-gating.md and execute.
# Verify: BUILD SUCCEEDED; all task 238a tests pass
# Commit: Task 238b — Critic gating

# ── TASK 239a — Decompose-on-Overflow Tests ───────────────────────────────
Read tasks/task-239a-decompose-on-overflow-tests.md and execute.
# Verify: BUILD FAILED until decompose-first + cross-provider routing land
# Commit: Task 239a — DecomposeOnOverflowTests (failing)

# ── TASK 239b — Decompose-on-Overflow ─────────────────────────────────────
Read tasks/task-239b-decompose-on-overflow.md and execute.
# Verify: BUILD SUCCEEDED; all task 239a tests pass
# Commit: Task 239b — Decompose-on-overflow

# ── TASK 240a — v2.1.0 Release Tests ──────────────────────────────────────
Read tasks/task-240a-v2-1-release-tests.md and execute.
# Verify: BUILD FAILED until project.yml bumped and RELEASE-v2.1.0.md added
# Commit: Task 240a — V2_1ReleaseTests (failing)

# ── TASK 240b — v2.1.0 Release ────────────────────────────────────────────
Read tasks/task-240b-v2-1-release.md and execute.
# Verify: BUILD SUCCEEDED; "About Merlin" shows 2.1.0 (16)
# Commit: Task 240b — Bump version to 2.1.0 (Budget-Aware Execution)
# Tag: v2.1.0
# Release: gh release create v2.1.0 --latest
```

---

## Project Discipline

```bash
# ── TASK 277 — Telemetry Test-Seam Cleanup ─────────────────────────────────
cat tasks/task-277-telemetry-test-cleanup.md
# Verify: BUILD SUCCEEDED; zero warnings; full suite green headless
# Commit: Task 277 — Remove dead telemetry test seam, dedup reader, fix dismiss test
```

```bash
# -- TASK 278a — v2.2.2 Release Tests (failing) ----------------------------
cat tasks/task-278a-v2-2-2-release-tests.md
# Verify: BUILD SUCCEEDED; AppVersion222Tests + ReleaseNotes222Tests fail at runtime
# Commit: Task 278a — V2_2_2ReleaseTests (failing)

# -- TASK 278b — v2.2.2 Release -------------------------------------------
cat tasks/task-278b-v2-2-2-release.md
# Ships the CI-readiness remediation and regression fixes as v2.2.2.
# Verify: BUILD SUCCEEDED; full suite green headless; version banners read 2.2.2/build 19
# Commit: Task 278b — Bump version to 2.2.2 (build 19)
```

---

## Context-Overflow Hardening (toward v2.2.4)

> **Model:** run these on **gpt-5.5**, not gpt-5.4-mini. 285b and 286b are
> cross-cutting changes under `SWIFT_STRICT_CONCURRENCY=complete` (a new actor with an
> injected protocol + `nonisolated static` persistence helpers; 286b reroutes 14
> `provider.complete` sites across 11 files and adds actor-hopped learn-and-retry).
> The mini tier is documented for "lighter coding tasks"; this batch is not light.
> Run a→b strictly in order; do not start a `b` task until its `a` commit exists.

```bash
# ── TASK 283a — Local Model Picker Entries Tests (failing) ─────────────────
cat tasks/task-283a-local-model-picker-tests.md
# Verify: BUILD SUCCEEDED; testLocalProviderWithModelsYieldsOnlyVirtualEntries FAILS at runtime
# Commit: Task 283a — LocalModelPickerEntriesTests (failing)

# ── TASK 283b — Local Model Picker ─────────────────────────────────────────
cat tasks/task-283b-local-model-picker.md
# Verify: BUILD SUCCEEDED; all task 283a tests pass; no prior task regresses
# Commit: Task 283b — Local model picker in chat HUD + slot picker; model-list refresh

# ── TASK 284a — Tool Output Cap Tests (failing) ────────────────────────────
cat tasks/task-284a-tool-output-cap-tests.md
# Verify: BUILD FAILED — errors naming the missing ToolOutput type / clamp / maxChars
# Commit: Task 284a — ToolOutputClampTests (failing)

# ── TASK 284b — Tool Output Cap ────────────────────────────────────────────
cat tasks/task-284b-tool-output-cap.md
# Verify: BUILD SUCCEEDED; all task 284a tests pass; no prior task regresses
# Commit: Task 284b — Cap run_shell and read_file output before it enters context

# ── TASK 285a — Context Budget Resolver Tests (failing) ────────────────────
cat tasks/task-285a-context-budget-resolver-tests.md
# Verify: BUILD FAILED — missing ContextBudgetResolver / ContextBudgetStore / EphemeralBudgetStore
# Commit: Task 285a — ContextBudgetResolverTests (failing)

# ── TASK 285b — Context Budget Resolver ────────────────────────────────────
cat tasks/task-285b-context-budget-resolver.md
# Verify: BUILD SUCCEEDED; all task 285a tests pass; no prior task regresses
# Commit: Task 285b — ContextBudgetResolver: discover and persist the model's real context window

# ── TASK 286a — Universal Pre-flight Guard Tests (failing) ─────────────────
cat tasks/task-286a-universal-preflight-tests.md
# Verify: BUILD FAILED — errors naming the missing PreflightGuard type / fit
# Commit: Task 286a — PreflightGuardTests (failing)

# ── TASK 286b — Universal Pre-flight Guard ─────────────────────────────────
cat tasks/task-286b-universal-preflight.md
# Verify: BUILD SUCCEEDED; all task 286a tests pass; grep finds no un-guarded provider.complete
# Commit: Task 286b — Route every provider send through PreflightGuard
```

---

## Tool Detection + Vision Launchpad (toward v2.2.4)

> **Model:** gpt-5.5, reasoning effort `high`. 287b adds a new actor + a SwiftUI
> sheet + first-use wiring across several files under strict concurrency; 288 is
> skill/doc work. Run a→b strictly in order.

```bash
# ── TASK 287a — Tool Requirement Checker Tests (failing) ───────────────────
cat tasks/task-287a-tool-requirement-checker-tests.md
# Verify: BUILD FAILED — missing ToolRequirement / ToolRequirements / ToolRequirementChecker
# Commit: Task 287a — ToolRequirementCheckerTests (failing)

# ── TASK 287b — Tool Requirement Checker ───────────────────────────────────
cat tasks/task-287b-tool-requirement-checker.md
# Verify: BUILD SUCCEEDED; all task 287a tests pass; no prior task regresses
# Commit: Task 287b — Tool requirement checker: detect on first use, offer brew install

# ── TASK 288a — Vision Launchpad Tests (failing) ───────────────────────────
cat tasks/task-288a-vision-launchpad-tests.md
# Verify: BUILD SUCCEEDED; ProjectVisionLaunchpadTests fail at runtime (skill not yet updated)
# Commit: Task 288a — ProjectVisionLaunchpadTests (failing)

# ── TASK 288b — Vision Launchpad ───────────────────────────────────────────
cat tasks/task-288b-vision-launchpad.md
# Verify: BUILD SUCCEEDED; all task 288a tests pass; vision.md has ## Active + ## Deferred
# Commit: Task 288b — vision.md launchpad: seed at init, vision→architecture→task→code pipeline
```

```bash
# ── TASK 289 — v2.2.4 Release (ships  tasks 283–288) ───────────────────────
# Run only after 283–288 are all committed.
cat tasks/task-289-v2-2-4-release.md
# Verify: BUILD SUCCEEDED; full suite green; grep finds no stale 2.2.3/build 20
# Commit: Task 289 — Bump version to 2.2.4 (build 21); local tag v2.2.4
# NOTE: git push + gh release create are a MANUAL step — do not push in the batch.
```

---

## Liveness Discipline ( tasks 307–312)

> Extends Project Discipline to catch *liveness drift* — code that exists and compiles
> but is never reached, gated, or finished (off-gate targets, stub/deferred code,
> unwired components, stale docs). Four scanners + a pre-commit gate + the verification
> gate fix. Run a→b strictly in order; each `b` task wires its scanner into
> `DisciplineEngine` with a defaulted init parameter, so existing call sites are
> unaffected. Prerequisite:  tasks 294–306 + 302c complete.

```bash
# ── TASK 307a — TargetGateScanner Tests (failing) ──────────────────────────
cat tasks/task-307a-target-gate-scanner-tests.md
# Verify: BUILD FAILED — missing TargetGateScanner / UngatedTargetFinding
# Commit: Task 307a — TargetGateScanner tests (failing)

# ── TASK 307b — TargetGateScanner ──────────────────────────────────────────
cat tasks/task-307b-target-gate-scanner.md
# Verify: BUILD SUCCEEDED, zero warnings; TargetGateScannerTests + FindingModelTests pass
# Commit: Task 307b — TargetGateScanner: flag targets the build gate never compiles

# ── TASK 308a — StubMarkerScanner Tests (failing) ──────────────────────────
cat tasks/task-308a-stub-marker-scanner-tests.md
# Verify: BUILD FAILED — missing StubMarkerScanner / StubMarkerFinding
# Commit: Task 308a — StubMarkerScanner tests (failing)

# ── TASK 308b — StubMarkerScanner ──────────────────────────────────────────
cat tasks/task-308b-stub-marker-scanner.md
# Verify: BUILD SUCCEEDED, zero warnings; StubMarkerScannerTests + FindingModelTests pass
# Commit: Task 308b — StubMarkerScanner: surface unfinished code as discipline findings

# ── TASK 309a — ReachabilityScanner Tests (failing) ────────────────────────
cat tasks/task-309a-reachability-scanner-tests.md
# Verify: BUILD FAILED — missing ReachabilityScanner / UnwiredComponentFinding
# Commit: Task 309a — ReachabilityScanner tests (failing)

# ── TASK 309b — ReachabilityScanner ────────────────────────────────────────
cat tasks/task-309b-reachability-scanner.md
# Verify: BUILD SUCCEEDED, zero warnings; ReachabilityScannerTests + FindingModelTests pass
# Commit: Task 309b — ReachabilityScanner: flag unwired views and uninjected env objects

# ── TASK 310a — DocReferenceGraph Fenced-Block Tests (failing) ─────────────
cat tasks/task-310a-doc-reference-fenced-block-tests.md
# Verify: BUILD SUCCEEDED; DocReferenceGraphFencedBlockTests FAILS at runtime (verify with `test`)
# Commit: Task 310a — DocReferenceGraph fenced-block tests (failing)

# ── TASK 310b — DocReferenceGraph Fenced-Block Strengthening ───────────────
cat tasks/task-310b-doc-reference-fenced-block.md
# Verify: BUILD SUCCEEDED, zero warnings; DocReferenceGraphFencedBlockTests passes
# Commit: Task 310b — DocReferenceGraph verifies fenced-block enum cases

# ── TASK 311a — LivenessGate Tests (failing) ───────────────────────────────
cat tasks/task-311a-liveness-gate-tests.md
# Verify: BUILD FAILED — missing LivenessGate / LivenessGateResult
# Commit: Task 311a — LivenessGate tests (failing)

# ── TASK 311b — LivenessGate + pre-commit hook ─────────────────────────────
cat tasks/task-311b-liveness-gate.md
# Verify: BUILD SUCCEEDED, zero warnings; LivenessGateTests + DisciplineCLITests pass; merlin-discipline builds
# Commit: Task 311b — LivenessGate: pre-commit hook blocks ungated targets

# ── TASK 312 — Verification Gate Update ────────────────────────────────────
cat tasks/task-312-verification-gate-update.md
# Verify: constitution.md names MerlinTests-Live; .merlin/project.toml lists both gating schemes; MerlinTests-Live build-for-testing SUCCEEDED
# Commit: Task 312 — Fold MerlinTests-Live into the verification gate
```

---

## Discipline Gate Auto-Install (task 313)

> Makes the discipline pre-commit gate arm itself at app launch for any project that
> opts into the `pre_commit` discipline layer — removes reliance on the opt-in Settings
> toggle. The toggle stays as a manual install/uninstall override.

```bash
# ── TASK 313a — Discipline Gate Auto-Install Tests (failing) ───────────────
cat tasks/task-313a-discipline-gate-autoinstall-tests.md
# Verify: BUILD FAILED — missing DisciplineGateInstaller
# Commit: Task 313a — Discipline gate auto-install tests (failing)

# ── TASK 313b — Discipline Gate Auto-Install ───────────────────────────────
cat tasks/task-313b-discipline-gate-autoinstall.md
# Verify: BUILD SUCCEEDED, zero warnings; DisciplineGateInstallerTests passes
# Commit: Task 313b — Auto-arm the discipline pre-commit gate at app launch
```

---

## Discipline Operability ( tasks 314–315)

> W2 of the proving-readiness plan. 314 fixes a `TargetGateScanner` false positive
> (a dependency-only target was flagged ungated — it blocked a real commit). 315 adds a
> `merlin-discipline scan` subcommand so an operator can run the full discipline scan
> and see every finding. Run a→b strictly in order.

```bash
# ── TASK 314a — TargetGateScanner Dependency-Following Tests (failing) ──────
cat tasks/task-314a-target-gate-dependency-tests.md
# Verify (test — runtime-failure task): BUILD SUCCEEDED; testDependencyOnlyTargetIsTreatedAsGated FAILS
# Commit: Task 314a — TargetGateScanner dependency-following tests (failing)

# ── TASK 314b — TargetGateScanner Dependency-Following ─────────────────────
cat tasks/task-314b-target-gate-dependency.md
# Verify: BUILD SUCCEEDED, zero warnings; all TargetGateScannerTests pass
# Commit: Task 314b — TargetGateScanner follows transitive project.yml dependencies

# ── TASK 315a — merlin-discipline scan Command Tests (failing) ─────────────
cat tasks/task-315a-discipline-scan-command-tests.md
# Verify: BUILD FAILED — missing DisciplineCLI.formatScanReport
# Commit: Task 315a — merlin-discipline scan command tests (failing)

# ── TASK 315b — merlin-discipline scan Command ─────────────────────────────
cat tasks/task-315b-discipline-scan-command.md
# Verify: BUILD SUCCEEDED, zero warnings; DisciplineScanReportTests + DisciplineCLITests pass; merlin-discipline builds
# Commit: Task 315b — merlin-discipline scan: print all discipline findings
```

---

## Scanner Tuning ( tasks 316–318)

> W2 follow-up. The first real `merlin-discipline scan` of the Merlin repo was ~99%
> false positives. These three task pairs tune the scanners against real-repo noise.
> All three `a`  tasks are RUNTIME-failure  tasks — build SUCCEEDS, the new test FAILS;
> verify with `test`, not build-for-testing. Run a→b strictly in order.

```bash
# ── TASK 316a — DocReferenceGraph Scope Tests (failing) ────────────────────
cat tasks/task-316a-doc-reference-scope-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; testTasksDocsAndTestSymbolsAreNotFlagged FAILS
# Commit: Task 316a — DocReferenceGraph scope tests (failing)

# ── TASK 316b — DocReferenceGraph Scope Fix ────────────────────────────────
cat tasks/task-316b-doc-reference-scope.md
# Verify: BUILD SUCCEEDED, zero warnings; DocReferenceGraphScopeTests + DocReferenceGraphFencedBlockTests pass
# Commit: Task 316b — DocReferenceGraph skips tasks/ and knows test symbols

# ── TASK 317a — ReachabilityScanner Injection-Detection Tests (failing) ────
cat tasks/task-317a-reachability-injection-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; ReachabilityScannerInjectionTests FAIL
# Commit: Task 317a — ReachabilityScanner injection-detection tests (failing)

# ── TASK 317b — ReachabilityScanner Injection-Detection Fix ────────────────
cat tasks/task-317b-reachability-injection.md
# Verify: BUILD SUCCEEDED, zero warnings; ReachabilityScanner tests pass
# Commit: Task 317b — ReachabilityScanner reads annotation injection, skips comments

# ── TASK 318a — StubMarkerScanner Tuning Tests (failing) ───────────────────
cat tasks/task-318a-stub-marker-tuning-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; StubMarkerScannerTuningTests FAIL
# Commit: Task 318a — StubMarkerScanner tuning tests (failing)

# ── TASK 318b — StubMarkerScanner Tuning ───────────────────────────────────
cat tasks/task-318b-stub-marker-tuning.md
# Verify: BUILD SUCCEEDED, zero warnings; StubMarkerScanner tests pass
# Commit: Task 318b — StubMarkerScanner skips .cancel buttons and multi-line strings
```

---

## Scanner Tuning — Precision (task 319)

> Final scanner-tuning pass. Skips build-output directories (`build/`, `DerivedData/`,
> `.build/`) in all scanner file enumeration, and drops DocReferenceGraph's
> low-precision loose backticked-identifier check (keeping the high-precision
> fenced-block enum-case check). 319a is a RUNTIME-failure task — verify with `test`.
> 319b also rewrites the task-316a test and adds banners to four prior task docs.

```bash
# ── TASK 319a — DocReferenceGraph Precision Tests (failing) ────────────────
cat tasks/task-319a-doc-reference-precision-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; DocReferenceGraphPrecisionTests FAIL
# Commit: Task 319a — DocReferenceGraph precision tests (failing)

# ── TASK 319b — DocReferenceGraph Precision Fix ────────────────────────────
cat tasks/task-319b-doc-reference-precision.md
# Verify: BUILD SUCCEEDED, zero warnings; DocReferenceGraph Precision/Scope/FencedBlock tests pass
# Commit: Task 319b — DocReferenceGraph precision: skip build/, drop the loose check
```

## Tasks 320–324 — W4 trace-audit findings

> Authored from the W4 trace-the-calls audit (`merlin-eval/TRACE-AUDIT.md`). 320 wires
> the two dead `WorkerDiffView` toolbar buttons (empty `{ }` actions) to the staging
> buffer. 321 fixes a `DocReferenceGraph` false positive — `extractEnumCaseNames` parsed
> words out of `//` comments on `case` lines. 322 removes three dead `TelemetryEmitter`
> setters (zero callers). 323 fixes the `TaskScanner` doc-tier blind spot (it read only
> `task-NNb` docs; the "New surface" block lives in the `a` docs) and makes taskDrift
> always a nudge. 324 fixes `TaskScanner` symbol matching — qualified names, enum cases,
> non-symbol filtering — so the taskDrift metric is real, not noise. 320a is a
> COMPILE-failure task (verify with `build-for-testing`); 321a, 323a and 324a are
> RUNTIME-failure  tasks (verify with `test`); 322 is an implementation-only cleanup.

```bash
# ── TASK 320a — WorkerDiffView Reject/Accept Action Tests (failing) ────────
cat tasks/task-320a-worker-diff-actions-tests.md
# Verify (build-for-testing — compile-failure): BUILD FAILED; missing rejectAllChanges/acceptAndMergeChanges
# Commit: Task 320a — WorkerDiffViewActionTests (failing)

# ── TASK 320b — Wire WorkerDiffView Reject-All / Accept-and-Merge ──────────
cat tasks/task-320b-worker-diff-actions.md
# Verify: BUILD SUCCEEDED, zero warnings; WorkerDiffViewActionTests pass
# Commit: Task 320b — Wire WorkerDiffView reject-all / accept-and-merge

# ── TASK 321a — DocReferenceGraph Comment-Stripping Tests (failing) ────────
cat tasks/task-321a-doc-reference-comment-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; DocReferenceGraphCommentTests FAIL
# Commit: Task 321a — DocReferenceGraphCommentTests (failing)

# ── TASK 321b — DocReferenceGraph extractEnumCaseNames Strips // Comments ──
cat tasks/task-321b-doc-reference-comment.md
# Verify: BUILD SUCCEEDED, zero warnings; DocReferenceGraph comment/fenced/precision/dangling tests pass
# Commit: Task 321b — DocReferenceGraph extractEnumCaseNames strips // comments

# ── TASK 322 — Remove Dead TelemetryEmitter Setters ───────────────────────
cat tasks/task-322-remove-dead-telemetry-setters.md
# Verify: BUILD SUCCEEDED both schemes, zero warnings; TelemetryEmitterTests pass
# Commit: Task 322 — Remove dead TelemetryEmitter setters

# ── TASK 323a — TaskScanner Doc-Coverage & Drift-Severity Tests (failing) ─
cat tasks/task-323a- taskscanner-doc-coverage-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; all 3 new tests FAIL
# Commit: Task 323a — TaskScanner doc-coverage & drift-severity tests (failing)

# ── TASK 323b — TaskScanner Reads All Task Docs; Drift Is Always a Nudge ─
cat tasks/task-323b- taskscanner-doc-coverage.md
# Verify: full MerlinTests suite passes; MerlinTests-Live compiles; zero warnings
# Commit: Task 323b — TaskScanner reads all task docs; drift is always a nudge

# ── TASK 324a — TaskScanner Symbol-Matching Accuracy Tests (failing) ──────
cat tasks/task-324a- taskscanner-matching-tests.md
# Verify (test — runtime-failure): BUILD SUCCEEDED; all 5 new tests FAIL
# Commit: Task 324a — TaskScanner symbol-matching tests (failing)

# ── TASK 324b — TaskScanner Symbol-Matching Accuracy ──────────────────────
cat tasks/task-324b- taskscanner-matching.md
# Verify: full MerlinTests suite passes; MerlinTests-Live compiles; zero warnings
# Commit: Task 324b — TaskScanner symbol-matching accuracy
```

## Task 325 — W5 surface-census gap fill

> The W5 surface census (`merlin-eval/SURFACE-CENSUS.md` §1.2) found 12 interactive
> controls with no `AccessibilityID` — XCUITest cannot reach them, so they are untested
> surface. 325 adds the 12 constants and applies `.accessibilityIdentifier(...)`. 325a
> is a COMPILE-failure task (verify with `build-for-testing`).

```bash
# ── TASK 325a — AccessibilityID Gap-Fill Tests (failing) ───────────────────
cat tasks/task-325a-accessibility-id-gap-tests.md
# Verify (build-for-testing — compile-failure): BUILD FAILED; 12 missing AccessibilityID members
# Commit: Task 325a — AccessibilityID gap-fill tests (failing)

# ── TASK 325b — AccessibilityID Gap-Fill Implementation ────────────────────
cat tasks/task-325b-accessibility-id-gap.md
# Verify: BUILD SUCCEEDED both schemes, zero warnings; AccessibilityIDCoverageTests pass
# Commit: Task 325b — AccessibilityID gap-fill: the 12 controls task 306 missed
```

## Tasks 326–330 — W5 proving-suite harness

> The `MerlinE2ETests` / `MerlinTests` harness that drives the S1–S18 eval scenarios.
> Each is an implementation task (the test file is the deliverable); verify with
> `build-for-testing` (it compiles the harness — the proving suite is run separately).
> Fixtures must be built first per `merlin-eval/fixtures/S{1,2,4,5,6}-*.md`.

```bash
# ── TASK 326 — Eval Capability Harness (S1–S6) ─────────────────────────────
cat tasks/task-326-eval-capability-harness.md
# Verify: BUILD SUCCEEDED both schemes, zero warnings
# Commit: Task 326 — Eval capability harness (S1–S6)

# ── TASK 327 — Eval Agent-Tool Census (S18) ────────────────────────────────
cat tasks/task-327-eval-agent-tool-census.md
# Verify: BUILD SUCCEEDED, zero warnings; AgentToolCensusTests pass
# Commit: Task 327 — Eval agent-tool census (S18)

# ── TASK 328 — Eval Surface Harness (S7–S11) ───────────────────────────────
cat tasks/task-328-eval-surface-harness.md
# Verify: BUILD SUCCEEDED (MerlinTests-Live), zero warnings
# Commit: Task 328 — Eval surface harness (S7–S11)

# ── TASK 329 — Eval Render Harness (S10) ───────────────────────────────────
cat tasks/task-329-eval-render-harness.md
# Verify: BUILD SUCCEEDED, zero warnings; ConversationRenderTests pass
# Commit: Task 329 — Eval render harness (S10 chat rendering)

# ── TASK 330 — Eval Operator Harness (S12–S17) ─────────────────────────────
cat tasks/task-330-eval-operator-harness.md
# Verify: BUILD SUCCEEDED, zero warnings; OperatorConfigTests pass
# Commit: Task 330 — Eval operator harness (S12–S17)
```

## Tasks 331–332 — merlin-eval relocation

> Adds a shared directory blacklist (`DisciplineExclusions`) to every file-walking
> discipline scanner, then moves the eval suite (`merlin-eval/`) into the merlin repo so
> it is version-controlled with the project. 331a/331b are a TDD pair; 332 is the
> filesystem move + harness path fix + commit.

```bash
# ── TASK 331a — DisciplineExclusions Tests (failing) ───────────────────────
cat tasks/task-331a-discipline-exclusions-tests.md
# Verify (build-for-testing — compile-failure): BUILD FAILED; 4 "cannot find 'DisciplineExclusions'" errors
# Commit: Task 331a — DisciplineExclusionsTests (failing)

# ── TASK 331b — DisciplineExclusions Blacklist ─────────────────────────────
cat tasks/task-331b-discipline-exclusions.md
# Verify: BUILD SUCCEEDED both schemes, zero warnings; DisciplineExclusionsTests pass; grep lists 8 scanner files
# Commit: Task 331b — DisciplineExclusions blacklist

# ── TASK 332 — Relocate merlin-eval Into The Repo ──────────────────────────
cat tasks/task-332-relocate-merlin-eval.md
# Verify: move done, old sibling path gone; MerlinTests-Live BUILD SUCCEEDED, zero warnings
# Commit: Task 332 — Relocate merlin-eval into the merlin repo
```

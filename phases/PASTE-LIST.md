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
```

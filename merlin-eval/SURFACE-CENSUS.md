# Merlin Surface Census — mechanically derived

**This supersedes the hand-curated `SURFACE-INVENTORY.md` as the W5 coverage spec.**
That inventory was assembled by judgement and was a subset by construction — it
undercounted at every turn (16 "menu commands" vs a full menu bar; "~90" controls vs
~170; it never enumerated the agent's own tool surface). This census is derived **by
grep across all 258 `Merlin/` source files** — nothing curated. The rule:

> **Every row below must map to an eval test. An unmapped row is untested surface and
> is a GAP — see Part 4. Every value is logged end to end (initial → set → in-app →
> on-disk → reloaded).**

Counts are mechanical (`grep`); exact figures may shift ±a few with pattern choice.

---

# Part 1 — GUI surface

## 1.1 — SwiftUI views — 76

Every `struct … : View`. M3 host-render smoke must instantiate **all 76**.

- **Workspace shell:** `WorkspaceView`, `ContentView`, `ChatView`, `SideChatPane`
- **Sidebar (`SessionSidebar.swift`):** `SessionSidebar`, `ProjectSection`, `LiveSessionRow`,
  `PriorSessionRow`, `SubagentSection`, `ProjectHeaderPopover`, `PermissionModeBadge`,
  `SectionLabel`
- **Panels:** `ToolLogView`, `TerminalPane`, `ScreenPreviewView`, `DiffPane` +
  `DiffLineView` + `StagedChangeView`, `FilePane`, `PreviewPane`, `ProviderHUD`,
  `WorkerDiffView`, `SubagentSidebarRowView`, `PendingAttentionChipView`,
  `PendingAttentionPanelView` + `FindingRowView`, `AdvisoryRow`
- **Chat surface:** `VoiceDictationButton`, `AtMentionPicker`, `SkillsPicker`,
  `BtwOverlayView`
- **Settings (`SettingsWindowView.swift`):** `SettingsWindowView`, `GeneralSettingsView`,
  `AppearanceSettingsView`, `AgentSettingsView`, `HooksSettingsView`, `MCPSettingsView`,
  `SkillsSettingsView`, `ProvidersSettingsView`, `SearchSettingsView`,
  `PermissionsSettingsView`, `MemoriesSettingsView`, `AdvancedSettingsView`,
  `SchedulerSettingsView`, `ConnectorsSettingsView`
- **Settings sub-views:** `ProviderSettingsView` + `ProviderRow` + `APIKeyEntrySheet`,
  `RoleSlotSettingsView`, `MemoryBrowserView`, `PerformanceDashboardView`,
  `LoRASettingsSection` + `LoRAStatusRow`, `DPOReviewQueueView`,
  `ModelControlView` + `ModelControlSectionView` + `IntField` + `DoubleField` +
  `RestartInstructionsSheet`
- **Modals / dialogs:** `AuthPopupView`, `FirstLaunchSetupView`, `ProjectPickerView` +
  `ProjectRowView`, `MemoryReviewView`, `SchedulerView` + `ScheduledTaskRow` +
  `AddScheduledTaskView`, `ToolRequirementSheet`,
  `CalibrationFlowView` + `CalibrationProviderPickerView` + `CalibrationProgressView` +
  `CalibrationReportView` + `ScoreBar` + `ScoreGauge`
- **Windows:** `FloatingChatView`, `HelpWindowView`

## 1.2 — Interactive controls — ~170

By type (instantiation count): **Button 86–89 · TextField 27 · Picker 15–20 ·
Toggle 18 · SecureField 7 · Stepper 6 · TextEditor 2 · Menu 4 · Link 1.**
(0 Slider / DatePicker / ColorPicker / NavigationLink.)

**Control registry = `Merlin/Support/AccessibilityID.swift` — 158 constants.** Every
control must round-trip a value (set → effect → persist → reload). The 158 IDs:

`chatInput chatSendButton chatCancelButton chatAttachmentButton chatVoiceButton
chatPermissionModeButton chatStopButton chatToolbarActionPrefix chatResumeScrollButton
chatAtMentionPicker chatSkillsPicker sessionList newSessionButton
sessionProjectHeaderPrefix sessionProjectNewButton sessionProjectCloseButton
sessionArchivedTogglePrefix providerHUD settingsButton providerSelector
settingsProvidersRefreshButton settingsProviderModelFieldPrefix
settingsProviderMaxTokensFieldPrefix settingsProviderKeyButtonPrefix
settingsProviderEnabledTogglePrefix settingsProviderUseButtonPrefix
settingsProviderKeyField settingsProviderKeyCancelButton settingsProviderKeySaveButton
settingsGeneralKeepAwakeToggle settingsGeneralNotificationsToggle
settingsGeneralPermissionModePicker settingsGeneralMaxTokensStepper
settingsGeneralAutoCompactToggle settingsGeneralMaxSubagentThreadsStepper
settingsGeneralMaxSubagentDepthStepper settingsAppearanceThemePicker
settingsAppearanceFontSizeStepper settingsAppearanceFontNameField
settingsAppearanceAccentColorField settingsAppearanceDensityPicker
settingsAgentProviderPicker settingsAgentModelPicker settingsAgentCustomModelField
settingsAgentReasoningToggle settingsAgentPromptCompressionToggle
settingsAgentStandingInstructionsEditor settingsRoleSlotsPickerPrefix
settingsRoleActiveDomainPicker settingsRoleVerifyCommandField settingsRoleCheckCommandField
settingsRoleProjectPathField settingsRoleMemoryEnabledToggle settingsRoleRerankToggle
settingsRoleChunkLimitStepper settingsHooksDisciplineToggle
settingsHooksEnabledTogglePrefix settingsHooksDeleteButtonPrefix settingsHooksEventPicker
settingsHooksCommandField settingsHooksCancelButton settingsHooksConfirmAddButton
settingsHooksAddButton settingsMemoriesEnabledToggle settingsMemoriesIdlePicker
settingsMemoriesBackendPicker settingsMCPDeleteButtonPrefix settingsMCPNameField
settingsMCPCommandField settingsMCPArgsField settingsMCPCancelButton
settingsMCPConfirmAddButton settingsMCPAddButton settingsSkillsEnabledTogglePrefix
settingsSkillsOpenFolderButton settingsSearchAPIKeyField settingsSearchSaveButton
settingsPermissionsRemoveButtonPrefix settingsConnectorsGitHubTokenField
settingsConnectorsSlackTokenField settingsConnectorsLinearTokenField
settingsConnectorsXcalibreTokenField settingsConnectorsSaveButton
settingsAdvancedShowConfigButton settingsAdvancedShowMemoriesButton
settingsAdvancedResetButton settingsAdvancedConfirmResetButton
settingsAdvancedCancelResetButton settingsLoRAEnableToggle settingsLoRAAutoTrainToggle
settingsLoRAMinSamplesStepper settingsLoRABaseModelField settingsLoRAAdapterPathField
settingsLoRAAdapterBrowseButton settingsLoRAAutoLoadToggle settingsLoRAServerURLField
settingsModelControlFieldPrefix settingsModelControlFlashAttentionToggle
settingsModelControlCacheKPicker settingsModelControlCacheVPicker
settingsModelControlUseMmapToggle settingsModelControlUseMlockToggle
settingsModelControlApplyReloadButton settingsModelControlRestartButton
settingsModelControlRestartDoneButton settingsModelControlCopyCommandButton
terminalPaneInput terminalPaneRunButton terminalPaneStopButton toolLog
toolLogClearButton diffPaneCommentFieldPrefix diffPaneCommentSubmitButtonPrefix
diffPaneCommentCancelButtonPrefix diffPaneAcceptAllButton diffPaneRejectAllButton
filePaneOpenButton filePaneCloseButton workerDiffRejectAllButton
workerDiffAcceptMergeButton pendingAttentionCloseButton
pendingAttentionDismissButtonPrefix pendingAttentionRationaleField
pendingAttentionCancelDismissButton pendingAttentionConfirmDismissButton
memoryBrowserSearchField memoryBrowserSearchButton memoryBrowserDeleteButtonPrefix
memoryReviewList memoryReviewRejectButton memoryReviewApproveButton authArgumentButton
authAllowOnceButton authAllowAlwaysButton authDenyButton projectPickerClearRecentsButton
projectPickerCancelButton projectPickerOpenFolderButton projectPickerOpenButton
firstLaunchProviderPicker firstLaunchAPIKeyField firstLaunchSkipButton
firstLaunchContinueButton btwCloseButton btwQuestionField btwSubmitButton
schedulerAddButton schedulerNameField schedulerTimeField schedulerProjectPathField
schedulerPromptField schedulerConfirmAddButton schedulerCancelButton
calibrationCancelButton calibrationProviderPicker calibrationStartButton
calibrationDoneButton calibrationApplyAllButton`

**AX-ID GAP — 12 controls had no identifier:** the 6 `WorkspaceView` toolbar toggles
(Staged Changes, File Viewer, Terminal, Preview, Side Chat, Memories), the
`ScreenPreviewView` expand/collapse button, the `PreviewPane` close button, the 3
`ToolRequirementSheet` buttons (Install/Cancel/Done), and the `AdvisoryRow` "Fix this"
button (the performance pane's only control). → **Phase 325 authored** (`phases/
phase-325{a,b}-accessibility-id-gap*`) — adds all 12 constants + applies them.

## 1.3 — Modal / overlay surfaces — 18
11 `.sheet` · 4 `.popover` · 1 `.confirmationDialog` · 1 `.fileImporter` · `.contextMenu` ×4.
auth popup · first-launch · project picker · memory review · API-key entry ·
add-scheduled-task · restart-instructions · tool-requirement · calibration flow ·
dismiss-rationale · reset-settings confirm · @-mention popover · skills popover ·
project-header popover · Provider-HUD popover · project-dir file importer · session
context menus · BTW overlay · scroll-lock banner.

## 1.4 — Scenes & windows — 9
1 `WindowGroup` (workspace) · 1 `Settings` scene (⌘,) · `FloatingWindowManager` NSWindow
(pop-out session, ⌘⇧P) · `HelpWindowManager` ×2 (User Guide ⌘?, Developer Manual) ·
plus every `Window(`-created auxiliary window (8 `Window(` sites).

## 1.5 — Menu bar
**B1 — 16 custom commands** (`MerlinCommands.swift`): About; New Project Workspace (⌘N);
Session→Stop (⌘.), Compact Context (⌘⇧K); Window→Pop Out Session (⌘⇧P); Provider→(per
provider); View→Toggle Terminal (⌃`), Toggle Side Chat (⌘⇧/), Review Memories (⌘⇧M);
Copy Conversation (⌘⇧A); Help→User Guide (⌘?), Developer Manual.
**B2 — standard macOS menu bar** (OS/SwiftUI-provided, still Merlin's surface):
Settings… (⌘,), Hide Merlin (⌘H), Hide Others (⌥⌘H), Show All, Quit Merlin (⌘Q — must
persist sessions+config), Close (⌘W), Edit→Undo/Redo/Cut/Copy/Paste/Select All,
Window→Minimize (⌘M)/Zoom.

## 1.6 — Toolbar — 6 `ToolbarItem(Group)`
4 `ToolbarItem` + 2 `ToolbarItemGroup` — incl. the 6 `WorkspaceView` panel toggles and
the `ContentView` tool-log toggle.

---

# Part 2 — Operator / headless surface

## 2.1 — config.toml — 13 sections, 56 persisted `AppSettings` properties
Top-level (24): `auto_compact max_tokens keep_awake provider_name model_id
default_permission_mode notifications_enabled message_density standing_instructions
max_subagent_threads max_subagent_depth disabled_skill_names memories_enabled
memory_idle_timeout project_path rag_rerank rag_chunk_limit rag_freshness_threshold_days
rag_min_grounding_score agent_circuit_breaker_threshold agent_circuit_breaker_mode
xcalibre_token dpo_enabled prompt_compression_enabled`.
`[memory]` backend_id · `[kag]` enabled/hops/xcalibre_url · `[lora]` 7 keys ·
`[inference]` 10 keys · `[slots]` execute/reason/orchestrate/vision ·
`[domain]` active_domain/active_domains/verify_command/check_command ·
`[planner]` max_plan_retries/max_loop_iterations · `[critic]` critic_enabled/max_critic_retries ·
`[appearance]` theme/font_size/font_name/accent_color_hex/line_spacing ·
`[[providers]]` 13 fields/entry · `[[hooks]]` event/command/enabled ·
`[model_capabilities]` per-model reasoning flags.
Project `.merlin/project.toml`: adapter, adapterVersion, disciplineLayers,
manualCoverageBaseline, decayPerRelease.

## 2.2 — Hooks — 5 events
`PreToolUse` (allow/deny), `PostToolUse` (result rewrite), `UserPromptSubmit` (prompt
rewrite), `Stop` (proceed gate), `SessionStart` (system note). Run via `/bin/sh -c`.

## 2.3 — MCP
`~/.merlin/mcp.json` (global) + `<project>/.mcp.json` (project, overrides global). Per
server: command, args, env, transport, url. **3 transports:** stdio, http, sse.
`${VAR}` env expansion. Tools register as `mcp:<server>:<tool>`.

## 2.4 — inject.txt
`~/.merlin/inject.txt` — 2-second poll; content submitted as a user message, file deleted.

## 2.5 — Automations & scheduler
`ThreadAutomation` (session cron: id, sessionID, cronExpression, prompt, enabled, label) ·
`ScheduledTask` (name, cadence, time, projectPath, permissionMode, prompt, isEnabled);
**3 cadences** daily/hourly/weekly(Weekday); 60 s timer; `~/Library/Application Support/Merlin/schedules.json`.

## 2.6 — Environment variables — 10 reads
`HOME` (×8 — config/skills/MCP/memory/inject paths), `XCALIBRE_BASE_URL`,
`XCTestConfigurationFilePath` (×2 — test-env guard for voice + notifications).

## 2.7 — CLI launch arguments — 1
`--show-auth-popup-for-testing` — read at `AppState.swift:478` via
`ProcessInfo.processInfo.arguments` (flag constant at `AppState.swift:41`); forces the
auth popup for UI testing. The only launch argument the app parses.

## 2.8 — AppIntents — 3
`StartMerlinSessionIntent`, `SendMerlinPromptIntent(prompt:)`, `MerlinMetadataIntent`
(`AppIntentsSupport.swift`) — exposed to Shortcuts & Siri.

## 2.9 — `~/.merlin/` tree
Files: config.toml, mcp.json, api-keys.json, inject.txt, auth.json, telemetry.jsonl,
workspace.json, toolbar-actions.json, layout-workspace.json, CLAUDE.md.
Dirs (9): memories/ (+pending/), skills/, agents/, adapters/, bin/ (merlin-discipline),
lora/ (+pending/, reviewed.jsonl), kag/ (graph.sqlite), performance/, electronics/.
Project `.merlin/`: project.toml, pending.json, discipline-events.jsonl,
override-log.jsonl, memory.sqlite, worktrees/.

---

# Part 3 — Agent capability surface

## 3.1 — Built-in tools — ~45 (+ web_search conditional, + MCP dynamic)
- **File system (7):** read_file, write_file, create_file, delete_file, list_directory,
  move_file, search_files
- **Shell (2):** run_shell, bash
- **App control (4):** app_launch, app_list_running, app_quit, app_focus
- **Discovery (1):** tool_discover
- **Discipline (4):** generate_api_docs, generate_dev_guide, write_vale_styles,
  scaffold_manual_coverage
- **Xcode (12):** xcode_build, xcode_test, xcode_clean, xcode_derived_data_clean,
  xcode_open_file, xcode_xcresult_parse, xcode_simulator_list, xcode_simulator_boot,
  xcode_simulator_screenshot, xcode_simulator_install, xcode_spm_resolve, xcode_spm_list
- **GUI automation (10):** ui_inspect, ui_find_element, ui_get_element_value, ui_click,
  ui_double_click, ui_right_click, ui_drag, ui_type, ui_key, ui_scroll
- **Vision (2):** ui_screenshot, vision_query
- **RAG (2):** rag_search, rag_list_books
- **Subagent (1):** spawn_agent
- **Web (1, conditional):** web_search
- **KiCad / electronics (23, not built-in):** served by the `kicad` MCP server as
  `mcp:kicad:*` tools, registered at runtime by MCPBridge — not part of
  `ToolDefinitions.all`. The bare `kicad_*` names (`KiCadToolDefinitions`) are kept
  only for `ToolRouter.registerKiCadTools` and the contract tests.
- **MCP-registered:** dynamic, per configured server.

## 3.2 — Built-in skills — 13
commit, debug, explain, plan, refactor, review, summarise, test, project-init,
project-adopt, project-phase, project-revise, project-release. + personal
(`~/.merlin/skills/`) + project (`<project>/.merlin/skills/`).

## 3.3 — Agents & slots
Built-in agents (3): default, worker (own worktree), explorer (read-only toolset:
read_file/list_directory/search_files/bash/web_search/rag_search). + custom TOML
(`~/.merlin/agents/`). Slots (4): execute, reason, orchestrate, vision.

## 3.4 — Providers
**11 provider configs** (`ProviderRegistry.defaultProviders`): deepseek, openai,
anthropic, qwen, openrouter, ollama, lmstudio, jan, localai, mistralrs, vllm.
**4 provider classes:** AnthropicProvider, OpenAICompatibleProvider, DeepSeekProvider,
NullProvider. **7 local model managers:** Ollama, LMStudio, LocalAI, MistralRS, VLLM,
Jan, Null.

## 3.5 — Connectors — 5
GitHub (PR/issue/file/createPR/comment/merge), Slack (list/post), Linear
(list/create/updateStatus/comment), Brave web_search, xcalibre-server (RAG). Credentials
in Keychain (the xcalibre-server token in config).

## 3.6 — Slash commands — 4 + skills
`/compact`, `/calibrate` (`SlashCommandHandler.swift`); `/rewind [N]`, `/btw [prefill]`
(`ChatView.swift` dispatch). Plus every skill surfaced as `/<skill>`.

## 3.7 — Notifications
**9 internal** (`Notification.Name`): merlinNewSession, merlinGitHubTokenChanged,
merlinSelectProvider, merlinOpenPicker, merlinToggleTerminal, merlinToggleSideChat,
merlinReviewMemories, merlinInjectMessage, merlinProviderKeyDidChange.
**2 system** (`NotificationEngine.swift`): "Task complete", "Approval needed".

## 3.8 — Streaming events
`AgentEvent` (11): text, thinking, toolCallStarted, toolCallResult, subagentStarted,
subagentUpdate, systemNote, cleanStop, ragSources, groundingReport, error.
`SubagentEvent` (5): toolCallStarted, toolCallCompleted, messageChunk, completed, failed.

## 3.9 — Chat rendering kinds (`ConversationHTMLRenderer`)
ChatEntry roles: user, assistant, system, error. Render kinds: message ×4, thinking
block, tool-call rows (running/done/error), grounding report, RAG sources block,
subagent block. JS bridge: thinking toggle, tool-row toggle, scroll-lock.

## 3.10 — Automation substrate
Voice (`VoiceDictationEngine`, Speech framework, states idle/recording/error) ·
screen capture (`ScreenCaptureTool`, ScreenCaptureKit) · AX inspection
(`AXInspectorTool`, depth 8) · CGEvent injection (`CGEventTool`, 60+ keycodes,
click/drag/type/key/scroll) · vision query (`VisionQueryTool`).

---

# Part 4 — Coverage map & gaps

| Census area | Scenario | Status |
|---|---|---|
| 76 views (host-render) | S8/S9/S10/S11 + M3 smoke | must assert **all 76** |
| ~170 controls / 158 AX-IDs | S8/S9/S10/S11 | covered; **+12 un-IDed → setup gap (§1.2)** |
| 18 modals · 9 windows · menu bar · toolbar | S7/S11 | covered (B2 + ~12 IDs added this session) |
| config.toml 13 sections / 56 settings | S12 + S8 | covered |
| hooks · MCP · inject · automations · env | S12 | covered |
| AppIntents (3) | S16 | covered (incl. MerlinMetadataIntent — add) |
| ~/.merlin tree | S12/S15/S14 | covered |
| 11 providers · 5 connectors · keys | S13 | covered |
| 13 skills · 3 agents · 4 slots | S14 | covered |
| memories · notifications | S15 / S17 | covered |
| ~67 agent tools | **S18** | covered — S18 authored |
| 4 discipline generator tools | **S18** | covered — S18 authored |
| CLI arg `--show-auth-popup-for-testing` | S12 | covered |

## Confirmed gaps (the census exposes what the curated inventory hid)

1. **The ~67 agent tools had no scenario** — S1–S6 hit a subset incidentally; `move_file`,
   `app_quit`, the 12 `xcode_*`, the 4 discipline generators, `tool_discover`,
   `vision_query` etc. had no dedicated coverage. → **CLOSED — `scenarios/S18-agent-tools.md`
   authored**, covers all ~67 tools + a registry-census check.
2. **The 12 un-IDed controls** (§1.2) — **CLOSED — phase 325a/325b authored** (adds the
   12 `AccessibilityID` constants and applies `.accessibilityIdentifier(...)`).
3. **`MerlinMetadataIntent`** — a 3rd AppIntent the old inventory missed; S16 updated to
   cover all 3.

> Note: an earlier draft of this census claimed no CLI argument existed — that was a
> census error (a too-narrow grep). `--show-auth-popup-for-testing` does exist (§2.7);
> corrected. The census itself is verified, not assumed.

## Discrepancies vs `SURFACE-INVENTORY.md`
- "16 menu commands" → 16 custom **+ ~15 standard macOS items**.
- "~90 controls" → **~170** (158 carry AX-IDs).
- "two AppIntents" → **3**.
- Tool surface (~67 tools) — **absent from the old inventory entirely**.

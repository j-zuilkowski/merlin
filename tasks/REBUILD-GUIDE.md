# Merlin — Rebuild Guide

This document is the definitive reference for reconstructing Merlin from scratch using the
task files in this directory. Follow it sequentially. Each task builds on the last.

---

## Prerequisites

- macOS 14+, Xcode 15.4+, Swift 5.10
- `xcodegen` installed (`brew install xcodegen`)
- No third-party Swift packages in production targets
- `SWIFT_STRICT_CONCURRENCY=complete` — zero warnings required

```bash
# Confirm tooling
xcodegen --version
swift --version
```

---

## How to Use This Guide

1. Read `spec.md` first — understand the layered design before writing any code.
2. Run each task's **Verify** command. If it says "BUILD FAILED", that is expected for `a`
    tasks (tests-first). If it says "BUILD SUCCEEDED" with passing tests, move on.
3. Run each task's **Commit** command exactly as written.
4. Never batch commits across  tasks.
5. After any `project.yml` change, run `xcodegen generate` before building.

---

## Layer Map

Merlin is built in 9 vertical layers. Tasks in lower layers must be complete before
starting higher ones.

```
Layer 9 — Self-Improvement (LoRA, DPO, Calibration)     tasks 116–131, 165
Layer 8 — Reliability & Observability (v9)               tasks 133, 140–150
Layer 7 — Local Model Management (v7)                    tasks 125–132
Layer 6 — Memory Backend Plugins (v6 / v9)               tasks 113–115, 134–138
Layer 5 — Agent Reliability Framework (v5)               tasks 95–115, 116–128
Layer 4 — Subagents & Multi-Agent (v4)                   tasks 54–80
Layer 3 — Skills, RAG, Memory (v3)                       tasks 38–53
Layer 2 — Core Engine & Providers (v2)                   tasks 25–37
Layer 1 — Foundation (scaffold, types, tools)            tasks 00–24
```

---

## Task Reference

### Layer 1 — Foundation

| Task | File | Delivers |
|-------|------|----------|
| 00 | `task-00-preflight.sh` | Repo scaffold, project.yml, xcodegen |
| 01 | `task-01-scaffold.md` | MerlinApp, AppState, ContentView skeleton |
| 02a/b | `task-02a/b-shared-types` | Message, CompletionRequest, AgentEvent, ChunkDelta |
| 03a/b | `task-03a/b-provider-tests / task-03b-deepseek-provider` | LLMProvider protocol, DeepSeekProvider |
| 04 | `task-04-lmstudio-provider.md` | LMStudioProvider + SSEParser |
| 05 | `task-05-keychain.md` | KeychainManager — API key storage |
| 06 | `task-06-tool-definitions.md` | ToolDefinitions static catalog |
| 07a/b | `task-07a/b-filesystem-shell` | FileSystemTools, ShellTool |
| 08a/b | `task-08a/b-xcode-tools` | XcodeTools (build, test, run) |
| 09a/b | `task-09a/b-ax-screencapture` | AXInspectorTool, ScreenCaptureTool |
| 10 | `task-10-cgevent-vision.md` | CGEventTool, VisionQueryTool |
| 11 | `task-11-appcontrol-discovery.md` | AppControlTools, ToolDiscovery |
| 12a/b | `task-12a/b-auth` | AuthMemory, PatternMatcher |
| 13a/b | `task-13a/b-authgate` | AuthGate — per-tool permission gating |
| 14a/b | `task-14a/b-contextmanager` | ContextManager (basic append/compact/digest) |
| 15 | `task-15-toolrouter.md` | ToolRouter — routes tool calls through AuthGate |
| 16 | `task-16-thinking-detector.md` | ThinkingModeDetector |
| 17a/b | `task-17a/b-agenticengine` | AgenticEngine v1 (basic loop, tool dispatch) |
| 18 | `task-18-sessions.md` | Session, SessionManager, SessionStore |
| 19 / 19b | `task-19-appstate-entrypoint.md` / `task-19b-tool-registration.md` | AppState wiring, ToolRegistration |
| 20 | `task-20-chatview.md` | ChatView v1 |
| 21 | `task-21-secondary-views.md` | DiffPane, FilePane, TerminalPane |
| 22 | `task-22-authpopup.md` | AuthPopupView |
| 23 | `task-23-test-fixture-app.md` | TestTargetApp, NullAuthPresenter |
| 24 | `task-24-live-e2e.md` | E2E test harness |

> **See also:** `task-14c-contextmanager-v5-addendum.md` and
> `task-17c-agenticengine-v5-addendum.md` for all extensions made to these
> files in later  tasks.

---

### Layer 2 — Core Engine & Providers

| Task | File | Delivers |
|-------|------|----------|
| 25a/b | `task-25a/b-rag` | XcalibreClient, RAGTools (basic search) |
| 26a/b | `task-26a/b-provider` | OpenAICompatibleProvider, AnthropicProvider, SSEParser |
| 27a/b | `task-27a/b-model-picker` | ProviderRegistry, model picker UI |
| 28a/b | `task-28a/b-menu` | MerlinCommands, keyboard shortcuts |
| 29 | `task-29-project-picker.md` | ProjectPickerView, RecentProjectsStore |
| 30a/b | `task-30a/b-session-manager` | SessionManager v2, SessionSidebar |
| 31a/b | `task-31a/b-permission-mode` | PermissionMode, AuthGate integration |
| 32a/b | `task-32a/b-staging-buffer` | StagingBuffer (write_file batching) |
| 33a/b | `task-33a/b-diff-engine` | DiffEngine, DiffPane v2 |
| 34 | `task-34-chatview-v2.md` | ChatView v2 (markdown rendering, code blocks) |
| 35a/b | `task-35a/b-diff-comment` | DiffComment, diff review flow |
| 36a/b | `task-36a/b-constitution` | ConstitutionLoader — reads constitution.md into system prompt |
| 37a/b | `task-37a/b-context-injection` | ContextInjector, project-path injection |

---

### Layer 3 — Skills, RAG, Memory

| Task | File | Delivers |
|-------|------|----------|
| 38a/b | `task-38a/b-skills-registry` | SkillsRegistry, Skill, skill loading from ~/.merlin/skills/ |
| 39a/b | `task-39a/b-skill-invocation` | AgenticEngine.invokeSkill(), SkillsPicker |
| 40a/b | `task-40a/b-...` | *(see task file for detail)* |
| … | … | … |
| 46a/b | `task-46a/b-appsettings` | AppSettings v1 (TOML load/save, basic settings) |
| 47a/b | `task-47a/b-...` | Memory generation |
| … | … | … |
| 53 | *(see task file)* | End of Layer 3 |

> **See also:** `task-46c-appsettings-v5-addendum.md` for all properties added
> to AppSettings in  tasks 46–165.

> **Note:** Tasks 40–53 should be followed in file-sort order. Use
> `ls tasks/ | sort -V | grep "task-[34][0-9]"` to get the precise list.

---

### Layer 4 — Subagents & Multi-Agent (v4)

| Task | File | Delivers |
|-------|------|----------|
| 54a/b | Subagent engine | SubagentEngine, SubagentEvent, SubagentBlockView |
| 55a/b | Worker subagent | WorkerSubagentEngine, worktree isolation |
| 56–58 | Agent registry, spawn tool, worktree | AgentRegistry, SpawnAgentTool, WorktreeManager |
| 60a/b | Skill compaction | ContextManager skill-reinjection after compaction |
| 61–80 | *(see task files)* | Connectors (GitHub, Linear, Slack), PRMonitor, ThreadAutomation, SchedulerEngine, HookEngine, WebSearch, AtMentionPicker |

---

### Layer 5 — Agent Reliability Framework (v5)

| Task | File | Delivers |
|-------|------|----------|
| 95–106 | *(see task files)* | DomainRegistry, SoftwareDomain, AgentSlot, PlannerEngine, CriticEngine, slot-based system prompt addendum, V5 Settings UI |
| 107a/b | `task-107a/b-skill-frontmatter-v5` | SkillFrontmatter v5 (context, slot, domain annotations) |
| 108a/b | RAG source attribution | RAGSourceAttributionTests, RAGSourcesView |
| 109a/b | Project path | AppSettings.projectPath, project-aware prompt injection |
| 110a/b | Memory browser | MemoryBrowserView |
| 111a/b | RAG search tool | RAGSearchTool wired into ToolRouter |
| 112a/b | RAG settings | RAG settings section in SettingsWindowView |
| 113a/b | OutcomeRecord persistence | OutcomeRecord, ModelPerformanceTracker |
| 114a/b | StagingBuffer signals | OutcomeSignals in StagingBuffer |
| 115a/b | Critic-gated memory | Memory write suppressed on critic failure |

---

### Layer 6 — Self-Training Data (v6 partial)

| Task | File | Delivers |
|-------|------|----------|
| 116a/b | LoRA AppSettings | loraEnabled, loraAutoTrain, etc. in AppSettings |
| 117a/b | OutcomeRecord training fields | prompt/response capture in OutcomeRecord |
| 118a/b | LoRATrainer | LoRATrainer actor — triggers llama.cpp fine-tune |
| 119a/b | LoRACoordinator | LoRACoordinator — gates training on sample count |
| 120a/b | LoRA provider routing | ProviderRegistry routes to LoRA adapter when loaded |
| 121a/b | LoRA settings UI | LoRASettingsSection in SettingsWindowView |
| 122a/b | Memory xcalibre index | xcalibre-server memory chunk index |

---

### Layer 7 — Inference Defaults & Model Management

| Task | File | Delivers |
|-------|------|----------|
| 123a/b | Sampling params | InferenceDefaults in AppSettings, CompletionRequest fields |
| 124a/b | Parameter advisor | ModelParameterAdvisor, ParameterAdvisory, AdvisoryRow |
| 125a/b | LocalModelManagerProtocol | Protocol, capabilities, LocalModelConfig |
| 126a/b | Extended managers | OllamaModelManager, JanModelManager, LMStudioModelManager, MistralRSModelManager, LocalAIModelManager, VLLMModelManager |
| 126c | NullModelManager, LocalModelManagerSupport | Fallback manager + URL/shell-quote helpers |
| 127a/b | Model manager wiring | AgenticEngine wires LocalModelManager per slot |
| 128a/b | ModelControlView | ModelControlView, CalibrationFlowView |
| 129a/b | CalibrationRunner | CalibrationRunner, CalibrationSuite, CalibrationTypes |
| 130a/b | CalibrationAdvisor | CalibrationAdvisor — converts run results to advisories |
| 131a/b | CalibrationSkill | Skill that triggers calibration from chat |
| 132 | `task-132-v7-docs.md` | v7 architecture notes |

---

### Layer 8 — Reliability & Observability (v8/v9)

| Task | File | Delivers |
|-------|------|----------|
| 133 | `task-133-v8-docs.md` | v8 architecture notes |
| 134a/b | MemoryBackendPlugin | MemoryBackendPlugin protocol, NullMemoryPlugin |
| 135a/b | LocalVectorPlugin | LocalVectorPlugin — sqlite-vec embeddings |
| 136a/b | Memory engine backend wiring | MemoryEngine uses MemoryBackendPlugin |
| 137a/b | AgenticEngine memory plugin | AgenticEngine.setMemoryBackend() |
| 138a/b | Memory backend AppSettings | AppSettings.memoryBackendID, AppState wires at launch |
| 139 | `task-139-v9-docs.md` | v9 architecture notes |
| 140a/b | Circuit breaker | consecutiveCriticFailures → halt/warn mode |
| 141a/b | Grounding confidence | GroundingReport, ragMinGroundingScore |
| 142a/b | Semantic fault injection | SemanticFaultInjection test doubles |
| 143a/b | Dynamic model fetch | ProviderRegistry live model list from API |
| 144a/b | Virtual provider ID | Virtual provider ID normalization |
| 145a/b | Provider routing cleanup | Slot-to-provider resolution refactor |
| 146a/b | Provider settings UI | ProviderSettingsView, ProviderHUD |
| 147a/b | Adaptive loop ceiling | effectiveLoopCeiling() per project size |
| 148a/b | Document verification | CriticEngine cross-references written file content |
| 149a/b | LMStudio context auto-resize | LMStudioModelManager.ensureContextLength() |
| 150a/b | Loop continuation | Batch-split + continuation injection for long tasks |

**Diagnostic  tasks** (can be applied after Layer 8 or interleaved):

| Task | File | Delivers |
|-------|------|----------|
| diag-01a/b | TelemetryEmitter | TelemetryEmitter, TelemetryEvent, TelemetrySpan |
| diag-02a/b | Provider telemetry | TTFT/TPS metrics emitted per provider |
| diag-03a/b | Engine telemetry | Tool call, loop, turn events |
| diag-04a/b | Memory telemetry | Memory read/write/hit events |
| diag-05a/b | Context/planner/critic telemetry | Compaction, critic verdict, planner events |
| diag-06a/b | Infra telemetry | Process memory, GUI actions |
| diag-07a/b | Accessibility IDs | AccessibilityID constants, test identifiers |
| diag-08a/b | Voice dictation | VoiceDictationEngine (speech-to-text input) |

---

### Layer 9 — Xcalibre Integration & Context Management

| Task | File | Delivers |
|-------|------|----------|
| 151a/b (Merlin) | Context pre-run compaction | ContextManager.compactIfNeededBeforeRun() |
| 151a/b (xcalibre) | CHM extraction | xcalibre-processing CHM support |
| 152–163 | *(xcalibre processing  tasks)* | LIT, SNB, PDB, TCR, LRF, DjVu, AZW4, TXT, CBZ, PDB metadata |

---

### Layer 9b — Self-Improvement (continued)

| Task | File | Delivers |
|-------|------|----------|
| 164a/b | Critic retry loop | AgenticEngine retries on critic failure up to maxCriticRetries |
| 165a/b | DPO pair collection | DPOQueue, DPOPendingEntry, correction-triggered pair capture |

---

## Supplementary Files (No Dedicated Task)

These source files exist in the codebase but are not the primary deliverable of a numbered
task. They were introduced as support code within other  tasks or as later additions.
A rebuild must include them — see the linked task for context.

| File | Where Introduced | Notes |
|------|-----------------|-------|
| `App/AppFocusedValues.swift` | Task 20 / v5 | `FocusedValues` keys for `isEngineRunning`, `activeProviderID` |
| `Support/AppIntentsSupport.swift` | Task 19 | `MerlinMetadataIntent` — minimal App Intents registration |
| `Engine/ContextUsageTracker.swift` | Task 14 / diag | `@Published usedTokens`, `percentUsed`, `statusString` |
| `Engine/Protocols/CriticEngineProtocol.swift` | Task 95–102 | Protocol + default impl; `CriticEngine` conforms |
| `Engine/Protocols/ModelPerformanceTrackerProtocol.swift` | Task 113 | Protocol; `ModelPerformanceTracker` conforms |
| `Engine/Protocols/PlannerEngineProtocol.swift` | Task 95 | Protocol; `PlannerEngine` conforms |
| `Engine/Protocols/XcalibreClientProtocol.swift` | Task 25 | Protocol; `XcalibreClient` conforms |
| `Providers/ProviderRegistry+ReasoningEffort.swift` | Task 109 | `reasoningEffortSupported(for:overrides:)` static helper |
| `Providers/LocalModelManager/NullModelManager.swift` | Task 126c | No-op manager for unknown provider IDs |
| `Providers/LocalModelManager/LocalModelManagerSupport.swift` | Task 126c | `normalizedOpenAICompatibleBaseURL()`, `shellQuote()` |
| `Views/Shared/AdvisoryRow.swift` | Task 124 | Single-advisory row view used by ModelControlView |
| `UI/Sidebar/WorkerDiffView.swift` | Task 55 | Diff review panel for worker subagent output |
| `Views/Calibration/CalibrationFlowView.swift` | Task 128/129 | Sheet coordinator driving the 3-step calibration flow |
| `Windows/FloatingWindowManager.swift` | Task 72 | Pop-out session windows (always-on-top NSWindow) |
| `Windows/HelpWindowManager.swift` | Task 28 / v5 | Retains NSWindow references to prevent ARC dealloc |
| `Windows/HelpWindowView.swift` | Task 28 / v5 | WKWebView-based Markdown documentation viewer |
| `Toolbar/ToolbarAction.swift` | Task 80+ | `ToolbarAction` model — label, command, shortcut |
| `Toolbar/ToolbarActionStore.swift` | Task 80+ | Actor managing ordered toolbar action persistence |

---

## Key Architectural Decisions

Before writing any code, understand these or you will build the wrong thing:

1. **TDD always.** The `a` task writes failing tests; the `b` task makes them pass.
   Never write production code in an `a` task.

2. **AgenticEngine grows across many  tasks.** Task 17b is version 1. By task 165 it has
   ~1400 lines. The addendum docs (`task-17c`, `task-17d`) describe the key extensions.
   Read them before modifying AgenticEngine.

3. **AppSettings is the single source of truth.** No feature reads `UserDefaults` or config
   files directly. Everything goes through `AppSettings.shared`. The addendum
   `task-46c-appsettings-v5-addendum.md` documents all properties added after task 46b.

4. **ContextManager.compactIfNeededBeforeRun() and skill reinjection.** Task 14b implements
   basic compaction. Task 60b adds skill reinjection after compaction — critical for
   maintaining skill context in long sessions. The addendum `task-14c` documents this.

5. **Slot-based provider routing.** From v5 onward, `AgentSlot` (.execute, .reason, .vision,
   .embed) routes requests to different providers. `AppSettings.slotAssignments` maps slots
   to provider IDs. Always resolve slot → provider rather than using a single "active" provider.

6. **ToolRegistry is dynamic.** Built-in tools register at launch via
   `ToolRegistry.shared.registerBuiltins()`. MCP tools register at runtime. Never hardcode
   tool counts or assume a static list.

7. **SWIFT_STRICT_CONCURRENCY=complete.** All types that cross actor boundaries must be
   `Sendable`. Use `@MainActor` on all `ObservableObject` subclasses and their views.

8. **No force-unwraps, no `try!`, no `fatalError` in production.** Tests use `XCTUnwrap`.

---

## Quick-Start Checklist

To verify a fresh rebuild is complete:

```bash
# 1. Build + run all unit tests
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-rebuild-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD'

# 2. Launch the app
open build/Debug/Merlin.app

# 3. Verify version
# "About Merlin" should show the MARKETING_VERSION from project.yml
```

All unit tests should pass. Zero warnings, zero errors.

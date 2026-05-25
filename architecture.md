# Merlin — Architecture Document

## Overview

Merlin is a personal, non-distributed agentic development assistant for macOS. It connects to multiple LLM providers — remote (DeepSeek, OpenAI, Anthropic, Qwen, OpenRouter) and local (LM Studio, Ollama, Jan.ai, LocalAI, Mistral.rs, vLLM-Metal, llama.cpp) — exposes a rich tool registry covering file system, shell, Xcode, and GUI automation, and presents a SwiftUI chat interface.

**[v1]** Single serial session, direct file writes, fixed layout.
**[v2]** Multiple windows (one per project), parallel sessions in Git worktrees, staged diff/review layer, draggable pane workspace, skills, MCP, scheduling, PR monitoring, external connectors.
**[v2.0]** Electronics/KiCad feature set: `merlin-kicad-mcp`, raster/PDF schematic ingestion, KiCad project generation, FreeRouting-backed route loop, ERC/DRC/parity/SPICE/fab gates, vendor-native BOM/order workflows.
**[v3]** Agent intelligence + UX completeness: unified settings window, config system, AI-generated memories, hooks, thread automations, web search, reasoning effort, toolbar actions, notifications, personalization, context usage indicator, floating pop-out window, voice dictation.
**[v4]** Subagents (Explorer + Worker), WorktreeManager, SubagentEngine, SubagentStreamUI, full settings surface (all 12 sections), WorkspaceLayoutManager, wired panes (FilePane, TerminalPane, PreviewPane, SideChat), DisabledSkillNames enforcement, keep-awake (IOPMAssertion), AgentRegistry, HookEngine wiring, tool registry launch.
**[v5]** Supervisor-worker multi-LLM: DomainRegistry, DomainPlugin, SoftwareDomain, AgentSlot routing (execute/reason/orchestrate/vision), ModelPerformanceTracker, CriticEngine, PlannerEngine; RAG memory extension: RAGSourcesView, MemoryBrowserView, memory write gated on critic verdict; V5 settings UI: RoleSlotSettingsView, PerformanceDashboardView; skill frontmatter role/complexity; OutcomeRecord persistence; StagingBuffer accept/reject counters wired into OutcomeSignals.
**[v6]** LoRA self-training: LoRATrainer (exportJSONL + mlx_lm.lora), LoRACoordinator (threshold-gated auto-train, isTraining guard), LoRA provider routing (execute slot → mlx_lm.server when adapter loaded — LM Studio and vLLM-Metal are alternative MLX-native serving targets), LoRASettingsSection; OutcomeRecord prompt/response fields; exportTrainingData filters empty-text records; AppSettings [lora] TOML section.
**[v7]** Inference parameter expansion + local model management: CompletionRequest extended with 8 sampling params (topP, topK, minP, repeatPenalty, frequencyPenalty, presencePenalty, seed, stop); AppSettings [inference] TOML section with applyInferenceDefaults(); ModelParameterAdvisor (finishReason truncation, score variance, trigram repetition, context overflow); LocalModelManagerProtocol with 6 shipped provider implementations + NullModelManager; ModelControlView (per-provider load param editor + RestartInstructionsSheet); accepted memories dual-path to xcalibre RAG.
**[v8]** Cross-provider model calibration: `CalibrationSuite` (18-prompt battery across reasoning, coding, instruction-following, summarization), `CalibrationRunner` (sequential across prompts, concurrent local + reference dispatch within each prompt, critic scoring with explicit degraded-fallback reporting), `CalibrationAdvisor` (maps score gaps to ParameterAdvisory — context length, temperature, max tokens, repeat penalty), `CalibrationCoordinator` + `/calibrate` skill (provider picker → live progress → report with per-category breakdown and one-tap apply-all via existing applyAdvisory() pipeline).
**[v9]** Local memory store + behavioral reliability: `MemoryBackendPlugin` plugin system; `LocalVectorPlugin` (SQLite + `NLContextualEmbedding`); xcalibre retained for book content only; circuit breaker (phase 140); grounding confidence signal (phase 141).
**[v10]** KAG — Knowledge-Augmented Generation: `KAGBackendPlugin` protocol; `LocalKAGPlugin` (SQLite graph store at `~/.merlin/kag/`); `XcalibreKAGPlugin` (preferred — fuses session working graph with xcalibre book knowledge graph via REST); `KAGEngine` post-turn triple extraction; `RAGTools.buildEnrichedMessage` extended with graph subgraph injection; `kagEnabled` + `kagHops` in AppSettings.
**[v1.5]** Session history & archive: `Session.archived` field, `SessionStore` project-scoped per-project directory (`sessions/<project-id>/`), `archive`/`unarchive`/`activeSessions`/`archivedSessions`, `SessionManager.restore(session:)` with auto-compaction, `ContextManager.load(_:)`, `RelativeTimestampFormatter`, Prior Sessions sidebar section with timestamps and context menus, legacy session migration to `__legacy__/`. (phases 181–184)
**[v1.6]** Multi-project workspace: single `WindowGroup("Merlin", id: "workspace")` replaces per-project windows; `WorkspaceCoordinator` (testable `init(workspaceURL:)`, workspace persistence to `~/.merlin/workspace.json`, `activeProjectManager`); `SessionSidebar` iterates all open projects; Terminal and SideChat panes follow active project; `ProjectPickerView` sheet mode; session auto-title via `AgenticEngine.onTitleUpdate` + `applyTitleUpdateIfNeeded`. (phases 185–188, tag v1.6.0) — **v1.6.1** patch: `ChatView` `@EnvironmentObject SessionManager` → `@FocusedObject SessionManager?`; `WorkspaceView` exposes `activeProjectManager` as `.focusedObject()` — fixes `EXC_BREAKPOINT` crash on session activation. (phase 189, tag v1.6.1)

**[v1.7.0]** Knowledge-Augmented Generation (KAG): `KAGBackendPlugin` protocol; `NullKAGPlugin` (default); `LocalKAGPlugin` (SQLite graph at `~/.merlin/kag/graph.sqlite`); `XcalibreKAGPlugin` (preferred — writes session triples to xcalibre-server via `POST /api/v1/graph/triples`, reads fused book+session graph via `GET /api/v1/graph/traverse`); `KAGEngine` post-turn triple extraction (idle timer, background LLM call, domain-agnostic); `RAGTools.buildEnrichedMessage` extended with graph subgraph injection; `KAGBackendRegistry` + `AppSettings` additions (`kagEnabled`, `kagHops`, `kagXcalibreURL`). Phase files: `phases/phase-190a/190b` (KAGTriple + NullKAGPlugin + KAGBackendRegistry + LocalKAGPlugin + KAGEngine stub), `phases/phase-191a/191b` (XcalibreKAGPlugin + KAGEngine real extraction + RAGTools extension + AppSettings wiring). **Shipped v1.7.0.**

**[v1.8.0]** Context compaction improvements + KAG promoted to default-on: `ContextManager.compactIfNeededBeforeRun(isContinuation:)` auto-compacts when `estimatedTokens > 10 000` at the start of non-continuation runs; Session > Compact Context (Cmd+Shift+K) for manual trigger; `stepsPerTurn = 1` (hardcoded), `batchSize = 1`; adaptive ceiling: base 50 + log₂(files)×10, no upper cap; `maxLoopIterations = 100`; near-ceiling warning at 8 remaining steps; loop continuation chain fixed. Phase files: `phases/phase-151a/151b` (compaction), `phases/phase-192a/192b` (KAG settings wiring). **Shipped v1.8.0.**

**[v1.8.1]** Session isolation + activity indicator + auto-title fixes: `AppState` Combine subscriber on `engine.$isRunning` ensures status dot resets to idle when a run completes regardless of view lifecycle; `WorkspaceView.sessionContent(session:)` adds `.id(session.id)` so each session gets a fresh `ContentView` and stale `@State` is never carried across switches; `LiveSession.init` saves an initial `Session` record to `SessionStore` immediately so `applyTitleUpdateIfNeeded` can resolve `activeSession` and write auto-titles; `ContextManager.compact(force:)` hard-truncates to the last 20 messages (plus a sentinel) when no tool-exchange groups are present, eliminating the empty-compaction 400 error. Phase files: `phases/phase-193a/193b`. **Shipped v1.8.1.**

**[v2.0.0]** Electronics/KiCad domain + session hardening: `merlin-kicad-mcp` 22-tool contract with 9 canonical schemas (raster ingestion, KiCad project/schematic/PCB generation, footprint assignment, board constraints, net-class policy, placement criteria, SPICE simulation, visual QA, BOM/vendor ordering, fabrication/acceptance); multi-domain session scoping (`activeDomainIDs` per `LiveSession`/`AgenticEngine`); `DomainRegistry` stateless lookup helpers (`activeDomain(ids:)`, `taskTypes(ids:)`); `SoftwareDomain.defaultID`/`defaultActiveDomainIDs` centralised; `LiveSession` lifecycle hardened: `lifecycleTasks: [Task<Void, Never>]` array tracks all startup tasks, `isClosed` guard prevents double-teardown, `close() async` cancels tasks and stops MCP/automation/memory/engine; `AuthMemory` atomic write sets `chmod 0600`; `MemoryBackendPlugin` gains project-scoped `search(query:topK:projectPath:)` overload; `LocalVectorPlugin` filters by `project_path` in SQL; `AppSettings` FSEvents debounced 250 ms; `CancellationState` converted from `@unchecked Sendable` class to `actor`. Phase files: `phases/phase-208` through `phases/phase-231`. **Shipped v2.0.0** (build 15, tag `v2.0.0`).

**[v2.1.0]** Budget-Aware Execution: per-provider context-window enforcement at request-build time, replacing reactive 400-recovery loops; pre-flight token estimator; working-set caps for system prompt / RAG / recent turns / tool-call bursts; cross-provider routing to a larger-context model as a last resort before decomposition. See §V2.1 — Budget-Aware Execution. **Shipped v2.1.0.**

**[v2.2.x]** Project Discipline Subsystem: `DisciplineEngine` enforcement layer + five `/project:*` creation skills (`init`, `phase`, `revise`, `release`, `adopt`); git-hook integration scans for TDD pair drift, missing docstrings, doc-code sync, prose readability; pre-commit blocks; session-start "pending attention" surface. See §V2.2 — Project Discipline Subsystem. Patch releases (`v2.2.0` → `v2.2.5`) tightened the scanners and the `/project:adopt` flow. **Shipped through v2.2.5** (build 24, tag `v2.2.5`).
**[v2.3 planned]** First-class llama.cpp local provider: `llamacpp` default provider on `localhost:8081/v1`; `LlamaCppModelManager`; router-mode capability for one-server general+vision pairs; runtime model load/unload through llama-server router endpoints; GGUF + `mmproj` model configuration; role-slot assignment through existing virtual provider IDs (`llamacpp:<model-id>`). Main workspace slot-status redesign: top provider HUD removed; left-sidebar collapsed slot panel shows execute/reason/orchestrate/vision routing from explicit slot assignments only.

**Target hardware:** M4 Mac Studio, 128GB unified memory
**Language:** Swift (SwiftUI + Swift Concurrency)
**Distribution:** Direct, non-sandboxed `.app` bundle — personal use only

---

## System Architecture

### [v1] Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          SwiftUI Shell                              │
│   ChatView │ ToolLogView │ ScreenPreviewView │ AuthPopupView        │
├─────────────────────────────────────────────────────────────────────┤
│                         Agentic Engine                              │
│                                                                     │
│  ┌─────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │  ContextManager  │  │   ToolRouter     │  │   AuthGate        │  │
│  │  (1M window +   │  │  (discovery +    │  │  (sandbox +       │  │
│  │   compaction)   │  │   dispatch)      │  │   memory)         │  │
│  └─────────────────┘  └──────────────────┘  └───────────────────┘  │
├─────────────────────────┬───────────────────────────────────────────┤
│     Provider Layer      │            Tool Registry                  │
│                         │                                           │
│  ┌─────────────────┐    │  FileSystemTools    XcodeTools            │
│  │ OpenAICompat-   │    │  ShellTool          SimulatorTools        │
│  │ ibleProvider    │    │  AppLaunchTool      ToolDiscovery         │
│  │ (10 providers)  │    │  AXInspectorTool    ScreenCaptureTool     │
│  └─────────────────┘    │  CGEventTool        VisionQueryTool       │
│  ┌─────────────────┐    │                                           │
│  │ Anthropic-      │    │                                           │
│  │ Provider        │    │                                           │
│  └─────────────────┘    │                                           │
└─────────────────────────┴───────────────────────────────────────────┘
```

### [v2] Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SwiftUI Workspace                               │
│                                                                              │
│  ┌────────────┐  ┌──────────────┐  ┌──────────┐  ┌─────────┐  ┌─────────┐  │
│  │  ChatPane  │  │   DiffPane   │  │ FilePane │  │Terminal │  │Preview  │  │
│  │  + side    │  │  (Accept /   │  │          │  │  Pane   │  │  Pane   │  │
│  │    chat    │  │   Reject)    │  │          │  │         │  │         │  │
│  └────────────┘  └──────────────┘  └──────────┘  └─────────┘  └─────────┘  │
│                        Draggable · Collapsible · Persisted layout            │
├──────────────────────────────────────────────────────────────────────────────┤
│                           Session Manager [v2]                               │
│                                                                              │
│  Session A (worktree/a)   Session B (worktree/b)   Session C (worktree/c)   │
│  ┌────────────────────┐   ┌────────────────────┐   ┌────────────────────┐   │
│  │  AgenticEngine     │   │  AgenticEngine     │   │  AgenticEngine     │   │
│  │  ContextManager    │   │  ContextManager    │   │  ContextManager    │   │
│  │  StagingBuffer     │   │  StagingBuffer     │   │  StagingBuffer     │   │
│  └────────────────────┘   └────────────────────┘   └────────────────────┘   │
├──────────────────────────────────────────────────────────────────────────────┤
│                           Shared Infrastructure                              │
│                                                                              │
│  AuthGate + AuthMemory [v1]   SkillsRegistry [v2]   MCPBridge [v2]           │
│  SchedulerEngine [v2]         PRMonitor [v2]         CLAUDEMDLoader [v2]     │
│  ConnectorsLayer [v2]                                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                           Provider Layer [v1]                                │
│                                                                              │
│  OpenAICompatibleProvider (10 providers)   AnthropicProvider                 │
│  ProviderConfig + ProviderRegistry                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                     Tool Registry [v1] + MCP tools [v2]                      │
│                                                                              │
│  FileSystemTools  ShellTool  XcodeTools  AXInspectorTool  ScreenCaptureTool  │
│  CGEventTool  VisionQueryTool  AppControlTools  ToolDiscovery  [mcp:*]       │
└──────────────────────────────────────────────────────────────────────────────┘
```

### [v4] Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         Full Workspace [v4]                                  │
│                                                                              │
│  FilePane  TerminalPane  PreviewPane  SideChat (all wired + persisted)       │
│  FloatingWindowManager  WorkspaceLayoutManager                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                        Subagent System [v4]                                  │
│                                                                              │
│  SubagentEngine (explorer, read-only)   WorkerSubagentEngine (worktree)      │
│  AgentRegistry (built-in + custom TOML) SpawnAgentTool → AgentEvent stream   │
├──────────────────────────────────────────────────────────────────────────────┤
│                     Full Settings Surface [v4]                               │
│                                                                              │
│  General  Appearance  Providers  Memories  Connectors  MCP  Skills  Hooks    │
│  Search   Permissions  Advanced  Scheduler  (all sections live)              │
├──────────────────────────────────────────────────────────────────────────────┤
│                     System Utilities [v4]                                    │
│                                                                              │
│  KeepAwakeManager (IOPMAssertion)  NotificationsGuard  DisabledSkillNames    │
│  HookEngine main loop wiring  DefaultPermissionMode  ToolRegistry launch     │
└──────────────────────────────────────────────────────────────────────────────┘
```

### [v5] Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    Supervisor-Worker Multi-LLM [v5]                          │
│                                                                              │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐       │
│  │  PlannerEngine   │    │  AgenticEngine   │    │  CriticEngine    │       │
│  │  (complexity     │───▶│  runLoop()       │───▶│  stage1: domain  │       │
│  │   classify)      │    │                  │    │  stage2: reason  │       │
│  └──────────────────┘    └──────────────────┘    └──────────────────┘       │
│                                   │                       │                  │
│                      AgentSlot routing                 verdict               │
│                   (execute/reason/orchestrate/vision)  (pass/fail/skipped)  │
├──────────────────────────────────────────────────────────────────────────────┤
│                       Domain System [v5]                                     │
│                                                                              │
│  DomainRegistry.shared    DomainPlugin protocol    SoftwareDomain            │
│  verificationBackend      systemPromptAddendum      taskTypes                │
│  addendumHash (SHA256 prefix — tracks which addendum produced each outcome) │
├──────────────────────────────────────────────────────────────────────────────┤
│                   ModelPerformanceTracker [v5]                               │
│                                                                              │
│  OutcomeSignals → computeScore() → OutcomeRecord                            │
│  profiles: [key: ModelPerformanceProfile]   (calibrated at 30 samples)     │
│  records:  [key: [OutcomeRecord]]           (persists to records-<id>.json) │
│  successRate(for:taskType:) returns nil until calibrated                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                       RAG Memory Extension [v5]                              │
│                                                                              │
│  AgentEvent.ragSources([RAGChunk])  RAGSourcesView (Sources footer)         │
│  MemoryBrowserView (search + delete xcalibre memories)                      │
│  XcalibreClient.searchMemory()  projectPath scoping                         │
│  ragRerank + ragChunkLimit (hardware-configurable)                          │
│  xcalibre.writeMemoryChunk suppressed when critic returned .fail            │
└──────────────────────────────────────────────────────────────────────────────┘
```

### [v6] Architecture

```
Training data flow:

  AgenticEngine.runLoop()
       │
       ▼  (end of turn)
  performanceTracker.record(
       modelID:, taskType:, signals:,
       prompt: userMessage,
       response: lastResponseText
  )
       │
       ▼
  OutcomeRecord persisted to records-<model-id>.json
       │
       ▼  (when loraEnabled + loraAutoTrain + sample threshold met)
  LoRACoordinator.considerTraining()
       │  guard !isTraining
       ▼
  tracker.exportTrainingData(minScore: 0.8)
       │  filters empty prompt/response records
       ▼
  LoRATrainer.exportJSONL()
       │  → temp .jsonl in MLX-LM chat format
       ▼
  python -m mlx_lm.lora --train --model <base> --data <jsonl> --adapter-path <dir>
       │
       ▼  (on completion)
  LoRACoordinator.finishTraining(result:) → isTraining = false, lastResult set
       │
       ▼  (when loraAutoLoad + adapter file exists)
  AppState wires loraProvider = OpenAICompatibleProvider(baseURL: loraServerURL)
       │
       ▼
  AgenticEngine.provider(for: .execute) → loraProvider (adapter inference)

Three LLM pool wiring:

  execute slot ──────→ mlx_lm.server (LoRA adapter, M4 Mac local)
  reason/critic slot → external API provider (base model, unmodified)
  vision slot ───────→ Qwen2.5-VL-72B via LM Studio (M4 Mac local)
  RAG embed/search ──→ nomic-embed-text + phi-3-mini (Windows RTX 2070)
```

### [v7] Architecture

```
Inference Parameter Expansion [v7]:

  CompletionRequest
    ├── (existing) maxTokens, temperature
    └── (new) topP, topK, minP, repeatPenalty, frequencyPenalty,
               presencePenalty, seed, stop

  AppSettings [inference] TOML section
    ├── inferenceTopP, inferenceTopK, inferenceMinP, inferenceRepeatPenalty
    ├── inferenceFrequencyPenalty, inferencePresencePenalty, inferenceSeed, inferenceStop
    └── applyInferenceDefaults(to: &CompletionRequest) — fills nil fields, respects overrides

  encodeRequest() Body
    └── serialises all new fields; nil → omitted from JSON (no provider surprises)

ModelParameterAdvisor [v7]:

  OutcomeRecord.finishReason: String?  (backward-compat decode)
  OutcomeSignals.finishReason: String? (captured from last CompletionChunk)

  ModelParameterAdvisor.checkRecord(_:) → immediate per-turn checks:
    finishReason == "length"   → ParameterAdvisory(.maxTokensTooLow)
    context overflow string    → ParameterAdvisory(.contextLengthTooSmall)

  ModelParameterAdvisor.analyze(records:modelID:) → batch checks:
    score std-dev > 0.25 (≥5 records)           → .temperatureUnstable
    trigram repetition > 50% in ≥60% of records → .repetitiveOutput

  Advisories surface in Settings → Performance with "Fix this" button.

Local Model Management [v7]:

  LocalModelManagerProtocol
    ├── capabilities: ModelManagerCapabilities
    │     ├── canReloadAtRuntime: Bool
    │     ├── supportedLoadParams: Set<LoadParam>
    │     ├── supportsRouterMode: Bool
    │     ├── supportsRuntimeModelLoad: Bool
    │     └── supportsRuntimeModelUnload: Bool
    ├── loadedModels() → [LoadedModelInfo]
    ├── ensureModelLoaded(modelID:) async throws       — no-op unless router/load API exists
    ├── unloadModel(modelID:) async throws             — no-op/unsupported unless router/unload API exists
    ├── reload(modelID:config:) async throws   — ModelManagerError.requiresRestart if unsupported
    └── restartInstructions(modelID:config:)   — shell command + config snippet

  Provider implementations:
    LMStudioModelManager   — REST API /api/v1/unload + /api/v1/load; lms CLI fallback
                             canReloadAtRuntime = true
                             supportedLoadParams: contextLength, gpuLayers, cpuThreads,
                                                  flashAttention, cacheTypeK/V, ropeFrequencyBase,
                                                  batchSize

    OllamaModelManager     — Modelfile generation + POST /api/create; force-unload via keep_alive:0
                             canReloadAtRuntime = true
                             supportedLoadParams: contextLength, gpuLayers, cpuThreads,
                                                  ropeFrequencyBase, batchSize, useMmap, useMlock

    JanModelManager        — OpenAI-compatible reload endpoint; reads and rewrites Jan model config at `~/jan/models/<id>/model.json`
                             canReloadAtRuntime = true
                             supportedLoadParams: contextLength, gpuLayers, cpuThreads

    LocalAIModelManager    — YAML snippet + restart instructions (no runtime reload)
                             canReloadAtRuntime = false
                             supportedLoadParams: contextLength, gpuLayers, cpuThreads,
                                                  ropeFrequencyBase, batchSize, useMmap

    MistralRSModelManager  — mistralrs-server CLI command (restart only)
                             canReloadAtRuntime = false
                             supportedLoadParams: contextLength, gpuLayers, cpuThreads,
                                                  flashAttention, ropeFrequencyBase, batchSize

    VLLMModelManager       — native `vllm serve` CLI (restart only)
                             canReloadAtRuntime = false
                             supportedLoadParams: contextLength, gpuLayers, cacheTypeK,
                                                  ropeFrequencyBase, batchSize

    LlamaCppModelManager   — llama-server; single-model mode = restart only,
                             router mode = runtime load/unload via /models/load + /models/unload
                             canReloadAtRuntime = true only when router mode is detected
                             supportsRouterMode = true
                             supportedLoadParams: contextLength, gpuLayers, cpuThreads,
                                                  flashAttention, cacheTypeK/V, ropeFrequencyBase,
                                                  batchSize, useMmap, useMlock

    NullModelManager       — no-op; used for unrecognised local providers

  AppState registry:
    localModelManagers: [String: any LocalModelManagerProtocol]  — keyed by providerID
    activeLocalProviderID: String?
    applyAdvisory(_ advisory: ParameterAdvisory) async throws
      → load-time kinds (.contextLengthTooSmall) → manager.reload()
      → inference kinds (.maxTokensTooLow, .temperatureUnstable, .repetitiveOutput)
           → AppSettings inference defaults update

  AgenticEngine:
    isReloadingModel: Bool         — run loop polls and suspends while true
    onAdvisory: (@Sendable (ParameterAdvisory) async -> Void)?

  ModelControlView (Settings → Providers → local provider):
    ├── Fields filtered by capabilities.supportedLoadParams
    ├── "Apply & Reload" button (canReloadAtRuntime = true)
    ├── "Show Restart Instructions" button (canReloadAtRuntime = false)
    └── RestartInstructionsSheet — copyable shell command + config snippet

Memory dual-path [v7]:
  Accepted AI-generated memories → ~/.merlin/memories/ (file injection, unchanged)
                                 → xcalibre.writeMemoryChunk(chunkType:"factual",
                                     tags:["session-memory"]) (RAG indexing, new)
```

---

## Local Model Management [v7]

### Design Decision: Protocol over Provider-Specific Paths

Every supported local provider has a different mechanism for changing load-time parameters. Rather than adding per-provider branches throughout the codebase, all management is routed through `LocalModelManagerProtocol`. Callers (AppState, ModelControlView, ModelParameterAdvisor wiring) are fully decoupled from provider details.

Router/load-unload capability flags default to `false` so existing provider managers do not gain accidental behavior. A manager must opt in explicitly before AppState or ProviderRegistry calls runtime load/unload APIs.

### Capability Matrix

| Provider | Runtime Reload | Router Mode | Context Length | GPU Layers | CPU Threads | Flash Attn | KV Cache Type | Rope Base | Batch Size | mmap/mlock |
|---|---|---|---|---|---|---|---|---|---|---|
| LM Studio | ✅ REST + CLI | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ K/V | ✅ | ✅ | ❌ |
| Ollama | ✅ Modelfile | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Jan.ai | ✅ reload API | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| LocalAI | ❌ restart | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Mistral.rs | ❌ restart | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| vLLM-Metal | ❌ restart | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ K | ✅ | ✅ | ❌ |
| llama.cpp | ✅ router / ❌ single-model | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ K/V | ✅ | ✅ | ✅ |

Runtime notes:
- LM Studio, Ollama, and Jan all participate in `ensureContextLength(...)`.
- Ollama enriches running-model state via `/api/show`.
- Jan enriches `knownConfig` from `~/jan/models/<id>/model.json`.
- llama.cpp participates in runtime model load/unload only when `llama-server` runs in router mode. In single-model mode it remains restart-only and returns `RestartInstructions`.

### Advisory → Action Routing

```
ModelParameterAdvisor advisory
        │
        ▼
AppState.applyAdvisory(_:)
        │
        ├── .contextLengthTooSmall
        │     └── manager.reload(modelID:config:)
        │           ├── (canReloadAtRuntime) → REST/Modelfile reload
        │           └── (!canReloadAtRuntime) → throw .requiresRestart(instructions)
        │                                         → AppState.pendingRestartInstructions
        │
        ├── .maxTokensTooLow          → AppSettings.inferenceMaxTokens += 50%
        ├── .temperatureUnstable      → AppSettings.inferenceTemperature -= 0.1
        └── .repetitiveOutput         → AppSettings.inferenceRepeatPenalty = 1.15
```

### File Layout

```
Merlin/Providers/LocalModelManager/
  LocalModelManagerProtocol.swift   — protocol + all shared types
  LMStudioModelManager.swift
  OllamaModelManager.swift
  JanModelManager.swift
  LocalAIModelManager.swift
  MistralRSModelManager.swift
  VLLMModelManager.swift
  LlamaCppModelManager.swift
  NullModelManager.swift

Merlin/Views/Settings/
  ModelControlView.swift            — ModelControlView + ModelControlSectionView + RestartInstructionsSheet
```

---

## llama.cpp First-Class Local Provider [v2.3 planned]

### Design Decision: Router Capability on the Local Manager, Not a New Provider Wire Format

llama.cpp's `llama-server` remains an OpenAI-compatible chat provider. Merlin should not add a new `ProviderKind` for it. The first-class work is local runtime management: model discovery, model load/unload, GGUF launch parameters, and general+vision pairing. Those concerns belong in `LocalModelManagerProtocol` and `LlamaCppModelManager`.

`/router` is treated as a capability shorthand for llama-server router mode. The HTTP chat path remains `/v1/chat/completions`; the router management path is the model catalog/load/unload API exposed by llama-server when launched without a single fixed `--model` and with `--models-dir`, `--models-preset`, or the llama cache as the model source.

### Default Provider

```swift
ProviderConfig(
    id: "llamacpp",
    displayName: "llama.cpp",
    localModelManagerID: "llamacpp",
    baseURL: "http://localhost:8081/v1",
    model: "",
    isEnabled: false,
    isLocal: true,
    supportsThinking: false,
    supportsVision: true,
    kind: .openAICompatible
)
```

Port `8081` is intentional. Upstream llama-server defaults to `8080`, but Merlin already reserves `8080` for LocalAI. A first-class llama.cpp provider must not collide with LocalAI during the local-provider pair workflow.

### General + Vision Pairing

Merlin already supports virtual local provider IDs of the form `backend:model`. llama.cpp router mode should use that existing mechanism:

```toml
[slots]
execute = "llamacpp:qwen3-coder-30b-a3b-instruct-q8_0"
vision = "llamacpp:qwen3-vl-8b-instruct-q8_0"
```

Both slots resolve to the same base URL (`http://localhost:8081/v1`) but send different `model` values in the OpenAI-compatible request. Router mode owns loading the requested model. The execute model can be a GGUF coding/general model; the vision model can be a GGUF VLM plus `mmproj`.

This is the preferred Merlin design over two separate llama-server processes because it preserves the existing slot picker, keeps one provider backend in Settings, and lets one local manager account for loaded/unloaded state. Two-process mode remains a fallback for debugging or for upstream router regressions.

### LlamaCppModelManager Contract

```swift
final class LlamaCppModelManager: LocalModelManagerProtocol {
    let providerID = "llamacpp"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,              // true only when router mode is detected
        supportedLoadParams: [
            .contextLength, .gpuLayers, .cpuThreads,
            .flashAttention, .cacheTypeK, .cacheTypeV,
            .ropeFrequencyBase, .batchSize, .useMmap, .useMlock
        ],
        supportsRouterMode: true,
        supportsRuntimeModelLoad: true,
        supportsRuntimeModelUnload: true
    )

    func loadedModels() async throws -> [LoadedModelInfo]
    func ensureModelLoaded(modelID: String) async throws
    func unloadModel(modelID: String) async throws
    func reload(modelID: String, config: LocalModelConfig) async throws
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions?
}
```

Required behavior:

1. Detect router mode by probing `/models` or `/v1/models` and checking for router model state metadata when available. If the server only exposes the single loaded model, downgrade to restart-only behavior.
2. `loadedModels()` returns all addressable router models so `ProviderRegistry.allSlotPickerEntries` can expose `llamacpp:<model-id>` entries.
3. `ensureModelLoaded(modelID:)` calls `POST /models/load` when the router reports the model as unloaded, sleeping, or absent from active memory but available in the catalog.
4. `unloadModel(modelID:)` calls `POST /models/unload` for explicit user unloads and for future memory-pressure policy.
5. `reload(modelID:config:)` in router mode unloads and reloads the same model with the selected load parameters. In single-model mode it throws `.requiresRestart`.
6. `restartInstructions(...)` generates either a router-mode launch command or a single-model launch command, depending on the user's selected local runtime mode.
7. Provider creation remains synchronous. Runtime autoload happens in an async preflight immediately before the request, not inside `ProviderRegistry.provider(for:)`.

### Load Parameter Mapping

| Merlin `LoadParam` | llama-server flag |
|---|---|
| `contextLength` | `--ctx-size` |
| `gpuLayers` | `--n-gpu-layers` |
| `cpuThreads` | `--threads` |
| `flashAttention` | `--flash-attn` |
| `cacheTypeK` | `--cache-type-k` |
| `cacheTypeV` | `--cache-type-v` |
| `ropeFrequencyBase` | `--rope-freq-base` |
| `batchSize` | `--batch-size` |
| `useMmap` | `--mmap` / `--no-mmap` |
| `useMlock` | `--mlock` |

Additional first-class llama.cpp runtime settings are required because they are not generic load parameters:

| Setting | Purpose |
|---|---|
| `serverPath` | Path to `llama-server`; default `llama-server` on `PATH`, Homebrew path acceptable |
| `routerEnabled` | Start without a fixed `--model`; enables catalog + runtime load/unload |
| `modelsDir` | Directory scanned by router mode for GGUF files |
| `modelsPresetPath` | Optional llama-server `.ini` preset file for per-model config |
| `modelPath` | Single-model fallback path when router mode is off |
| `modelAlias` | Stable model ID exposed by `/v1/models` for single-model mode |
| `mmprojPath` | Vision projector path for a VLM in single-model mode or per-model preset |
| `parallelSlots` | llama-server `--parallel` concurrency setting |
| `ubatchSize` | llama-server micro-batch setting |
| `chatTemplate` | Explicit chat template override when GGUF metadata is insufficient |
| `apiKey` | Optional local bearer token if the user starts llama-server with auth |
| `autoloadModels` | Whether Merlin should call `ensureModelLoaded` before the first request |

These should be persisted as provider-specific local runtime configuration, not added directly to the generic `ProviderConfig` unless they apply to every provider. `ProviderConfig` should continue to hold the wire identity (`id`, `baseURL`, `model`, flags). llama.cpp launch/runtime details belong in a local manager settings record keyed by `providerID`.

### Router Preset Shape

Router mode should be documented and generated as an `.ini` file when the user wants Merlin-managed launch commands:

```ini
[server]
host = 127.0.0.1
port = 8081
models-dir = /Users/you/Models/gguf
parallel = 2

[model.qwen3-coder-30b-a3b-instruct-q8_0]
model = /Users/you/Models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf
ctx-size = 32768
n-gpu-layers = -1

[model.qwen3-vl-8b-instruct-q8_0]
model = /Users/you/Models/gguf/Qwen3-VL-8B-Instruct-Q8_0.gguf
mmproj = /Users/you/Models/gguf/mmproj-Qwen3-VL-8B-Instruct-f16.gguf
ctx-size = 16384
n-gpu-layers = -1
```

The exact upstream preset syntax must be validated during implementation against the installed llama.cpp version. The architectural contract is stable: one Merlin provider, one base URL, many addressable model IDs.

### Request Flow

```text
RoleSlotSettingsView
  └── user assigns execute = llamacpp:<general-model>
      user assigns vision  = llamacpp:<vision-model>
        │
        ▼
AgenticEngine request preparation
  ├── async preflight: LlamaCppModelManager.ensureModelLoaded("<model>")
  └── ProviderRegistry.provider(for: "llamacpp:<model>")
        │
        └── returns OpenAICompatibleProvider(baseURL: http://localhost:8081/v1,
                                             modelID: "<model>")
              │
              ▼
        llama-server router selects the loaded model by request.model
```

### LoRA / Fine-Tuning Boundary

llama.cpp is a serving target for Merlin's LoRA output, not the primary training backend. The V6 path remains:

```text
OutcomeRecord corpus
  → mlx_lm.lora training
  → optional mlx_lm.fuse
  → convert/fuse output to GGUF
  → serve through llama-server router as a normal GGUF model
```

If llama.cpp adapter loading is used later, treat it as an inference-time optimization for compatible GGUF/PEFT adapter formats. It must not replace `LoRATrainer` until it supports Merlin's current MLX training workflow at the same quality and reliability level.

### Validation Requirements

First-class support is not complete until all of these pass:

1. `ProviderRegistry.defaultProviders` contains disabled-by-default `llamacpp`.
2. `AppState.makeManager(for:)` resolves `llamacpp` to `LlamaCppModelManager`.
3. `/v1/models` or `/models` discovery populates slot picker entries for both general and vision models.
4. Assigning `execute = llamacpp:<general>` and `vision = llamacpp:<vision>` routes both slots through one base URL with different request model IDs.
5. Router `POST /models/load` and `POST /models/unload` are covered by unit tests with mocked URLSession responses.
6. Single-model fallback returns restart instructions instead of pretending runtime reload is available.
7. Live smoke test covers text completion, tool-call prompt shape, vision image request, `/health`, `/v1/models`, and no HTTP 400 responses.
8. Local-provider docs state the one-local-provider-pair-at-a-time rule: do not run llama.cpp router beside LM Studio/Jan/LocalAI pairs during calibration unless memory pressure has been measured.

---

## Cross-Provider Calibration [v8]

### Design Decision: Closures over Protocol Coupling

`CalibrationRunner` takes `(String) async throws -> String` closures for local and reference
providers rather than `any LLMProvider` directly. This keeps the calibration engine decoupled
from the provider abstraction layer and makes it trivially testable with stubs. The provider
closures receive the full `CalibrationPrompt.prompt` string, and the scorer closure is invoked
once per response so local and reference answers are judged independently.

### Calibration Flow

```
User types /calibrate
        │
        ▼
CalibrationCoordinator.begin(localProviderID:localModelID:)
  → CalibrationSheet.pickProvider([remoteProviderIDs])
        │
        ▼  user selects reference + taps Start
CalibrationCoordinator.start(referenceProviderID:)
  → builds localClosure     with makeProviderClosure(providerID: localProviderID)
  → builds referenceClosure with makeProviderClosure(providerID: referenceProviderID)
  → builds scorerClosure    with makeScorerClosure()
        │
        ▼
CalibrationRunner.run(suite: .default)           ← prompts run sequentially; local + reference run concurrently per prompt
  for each prompt:
    async let local     = localClosure(prompt.prompt)
    async let reference = referenceClosure(prompt.prompt)
    localScore     = scorer(prompt.prompt, local)
    referenceScore = scorer(prompt.prompt, reference)
  → [CalibrationResponse]  (sorted by prompt.id)
        │
        ▼
CalibrationAdvisor.analyze(responses:localModelID:localProviderID:)
  checks:
    overallDelta < 0.15         → return []
    overallDelta ≥ 0.40          → .contextLengthTooSmall  (suggestedValue: "32768")
    local score σ ≥ 0.22         → .temperatureUnstable    (suggestedValue: "0.3")
    ≥50% responses length < 30%  → .maxTokensTooLow        (suggestedValue: "4096")
    ≥50% responses trigram rep   → .repetitiveOutput       (suggestedValue: "1.15")
  → [ParameterAdvisory]
        │
        ▼
CalibrationReport { responses, advisories, overallDelta, responsesByCategory }
        │
        ▼
CalibrationSheet.report(report)
  → CalibrationReportView:
      overall score gauges  (local % vs reference %)
      per-category bar chart (reasoning / coding / instruction-following / summarization)
      degraded-scoring warning block when critic fallback was used
      advisory list with suggested values
      "Apply All Suggestions" → applyAdvisory() for each advisory
                                (runtime reload or restart instructions — same path as v7)
```

### Prompt Battery [v8]

| ID | Category | Signal targeted |
|---|---|---|
| r1–r5 | Reasoning (5) | multi-step deduction, context retention |
| c1–c5 | Coding (5) | code synthesis, bug detection, technical formatting |
| i1–i4 | Instruction Following (4) | format compliance, truncation, schema adherence |
| s1–s4 | Summarization (4) | compression quality, repetition, salient detail selection |

### File Layout

```
Merlin/Calibration/
  CalibrationTypes.swift       — CalibrationCategory, CalibrationPrompt, CalibrationResponse, CalibrationReport
  CalibrationSuite.swift       — CalibrationSuite + default 18-prompt battery
  CalibrationRunner.swift      — actor; sequential prompt battery, concurrent local/reference per prompt
  CalibrationAdvisor.swift     — CalibrationAdvisor + CategoryScores; maps gaps to ParameterAdvisory
  CalibrationCoordinator.swift — @MainActor ObservableObject; CalibrationSheet enum; registerSkill()

Merlin/Views/Calibration/
  CalibrationProviderPickerView.swift — step 1: choose reference provider
  CalibrationProgressView.swift       — step 2: live progress bar
  CalibrationReportView.swift         — step 3: scores, breakdown, apply-all
```

---

## Local Memory Store [v9]

### Motivation

xcalibre-server was the original memory backend, but Merlin no longer depends on it for session memory. v9 moves approved memories and episodic summaries into a local SQLite store so memory writes and retrieval work fully on-device.

### Architecture

```text
MemoryEngine.approve()               AgenticEngine.runLoop()
        │                                     │
        ▼                                     ▼
MemoryBackendPlugin (protocol)    memoryBackend.search(query:topK:)
        │                                     │
        ▼                                     ▼
LocalVectorPlugin ──── SQLite ────── MemorySearchResult → RAGChunk
        │                                                     │
        └── NLContextualEmbedding                             ▼
            (512-dim, mean-pooled)              RAGTools.buildEnrichedMessage
```

xcalibreClient is still available in `AgenticEngine` for optional book-content search (`source: "all"`). Memory writes and memory RAG retrieval are handled by the local backend.

### Plugin protocol

| Symbol | Role |
|---|---|
| `MemoryBackendPlugin` | Actor protocol for write, search, and delete |
| `MemoryBackendRegistry` | `@MainActor` registry owned by `AppState` |
| `NullMemoryPlugin` | Default no-op backend |
| `LocalVectorPlugin` | SQLite + `NLContextualEmbedding` production backend |
| `EmbeddingProviderProtocol` | Testable embedding abstraction |
| `NLContextualEmbeddingProvider` | Apple neural embeddings (macOS 14+, no dependencies) |

`MemoryBackendPlugin` exposes two `search` signatures:

```swift
func search(query: String, topK: Int) async throws -> [MemorySearchResult]
func search(query: String, topK: Int, projectPath: String) async throws -> [MemorySearchResult]
```

The project-scoped overload adds a `WHERE project_path = ?` clause in `LocalVectorPlugin` so retrieval is confined to memories written for the active project. Backends that do not implement the three-argument form inherit a default-extension post-filter that calls the two-argument form and filters in memory. `AgenticEngine` always calls the project-scoped overload, passing `currentProjectPath`.

### File layout

```text
Merlin/Memories/
  MemoryBackendPlugin.swift     — protocol, registry, NullMemoryPlugin, MemoryChunk, MemorySearchResult
  EmbeddingProvider.swift       — EmbeddingProviderProtocol, NLContextualEmbeddingProvider
  LocalVectorPlugin.swift       — SQLite actor backend
TestHelpers/
  MockEmbeddingProvider.swift   — deterministic embedding provider for tests
  CapturingMemoryBackend.swift   — records writes for assertions
```

### Behavioral Reliability Framework

Merlin's v9 reliability features were designed against the failure taxonomy in:

["Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems"](https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems) — S. Patil, VentureBeat, 2025

#### Failure patterns

| Failure pattern | Description | Merlin response |
|---|---|---|
| Context degradation | Retrieval becomes stale or incomplete, so answers look polished but lose grounding | `GroundingReport` (phase 141) tracks staleness, average score, and `isWellGrounded` |
| Orchestration drift | Multi-step runs diverge under load | `CriticEngine` evaluates each turn; `ModelParameterAdvisor` tracks score trends |
| Silent partial failure | A subsystem degrades before it fully breaks | `consecutiveCriticFailures` plus the circuit breaker (phase 140) surfaces sustained degradation |
| Automation blast radius | A bad step propagates into later steps and decisions | `AuthGate` blocks unauthorised tool calls; critic failure suppresses backend memory writes |

#### Mitigations

| Mitigation | Description | Merlin implementation |
|---|---|---|
| Behavioral telemetry | Track grounding, fallback, and confidence per turn | `PerformanceTracker`, `ModelParameterAdvisor`, `AgentEvent.ragSources`, `AgentEvent.groundingReport` |
| Semantic fault injection | Simulate stale retrieval, truncation, empty tools, and context drop | `StalenessInjectingMemoryBackend`, `TruncatingMockProvider`, `EmptyToolResultRouter`, `DroppingContextManager` in `TestHelpers/SemanticFaults/` (phase 142) |
| Safe halt conditions | Stop cleanly when confidence cannot be maintained | `agentCircuitBreakerMode = "halt"` (default) halts after repeated critic failures and surfaces the failure to the user |
| Shared ownership | Each reliability signal has one owner | `CriticEngine` owns per-turn quality, `ModelParameterAdvisor` owns trend detection, `GroundingReport` owns retrieval confidence, and the circuit breaker owns halt decisions |

---

## KAG — Knowledge-Augmented Generation [v10]

### Motivation

The RAG memory store (v9) retrieves semantic chunks based on similarity — "what was said about X." What's missing is retrieval of *structural relationships* — "what entities exist, how they relate, and how they changed across sessions." KAG adds a graph layer alongside the vector layer so the engine can traverse relationships, not just rank chunks.

KAG is especially valuable for non-software domains where entities have rich relational structure: PCB components sharing power nets, building structural members in a load path, recipe ingredients with substitution graphs, or codebase symbols in a call graph. For software-only tasks grep and shell tools cover structural queries adequately. For PCB, construction, culinary, and other domains those tools don't exist — there is no grep for "which components share a power net" or "which structural members are in the load path of this column."

### What goes where

| Concern | Owner | Reason |
|---|---|---|
| Triple extraction from sessions | Merlin (post-turn LLM call) | LLM access; session content is here |
| Triple extraction from books | xcalibre-server (ingestion pipeline) | Books are here; one-time extraction at ingest |
| Graph storage + traversal | xcalibre-server (preferred) / `LocalKAGPlugin` (fallback) | Rust/SQLite performance; cross-session persistence; book+session graph fusion |
| Graph query at retrieval | xcalibre-server `GET /api/v1/graph/traverse` or `LocalKAGPlugin` | Fused result: book knowledge triples + session working triples in one traversal |
| Domain-specific live graph tools | Domain MCP servers | PCB domain knows KiCad format; construction knows IFC; neither Merlin core nor xcalibre needs to understand these |

### Architecture

```text
Turn end — post-turn triple extraction
        │
        ▼
KAGEngine.extractTriples(sessionContent:)
        │
        ├──▶ LocalKAGPlugin  ─── ~/.merlin/kag/graph.sqlite  (fallback, no xcalibre)
        │
        └──▶ XcalibreKAGPlugin ─ POST /api/v1/graph/triples  (preferred — fuses with book graph)

Turn start — enriched retrieval
        │
        ▼
RAGTools.buildEnrichedMessage()
        ├── vector search (existing) ──▶ semantic chunks
        └── graph traversal ──────────▶ KAG subgraph (anchor: entities in user message, hops: 2)
                │
                ▼
        Combined context: chunks + graph triples injected before user message
```

### Triple extraction

After each turn (same idle timer as memory generation), a background LLM call extracts `(subject, predicate, object)` triples from the session content:

```
turn ends → idle timer fires
  → MemoryEngine.generate()       (existing — semantic chunk write)
  → KAGEngine.extractTriples()    (new — structured triple write)
      system prompt: "Extract entity relationships as (subject, predicate, object) triples.
                     Entities: files, functions, components, symbols, rooms, ingredients, etc.
                     Predicates: calls, imports, inherits, depends_on, shares_net, supports,
                     contains, substitutes_for, complements, defined_in, etc.
                     Return JSON array only."
      → writes triples to active KAGBackendPlugin
```

Extraction is domain-agnostic: the model extracts whatever entity types appear in the session. The domain MCP server's `systemPromptAddendum` shapes what the model focuses on — a PCB session naturally surfaces net and component relationships; a culinary session surfaces ingredient and technique relationships.

### Plugin protocol

`KAGBackendPlugin` mirrors `MemoryBackendPlugin`:

```swift
protocol KAGBackendPlugin: Actor {
    func write(triples: [KAGTriple]) async throws
    func traverse(anchor: String, hops: Int, domainID: String?) async -> [KAGTriple]
    func deleteSession(_ sessionID: String) async throws
}

struct KAGTriple: Codable, Sendable {
    var subject: String
    var predicate: String
    var object: String
    var domainID: String
    var sessionID: String
    var confidence: Double          // 0.0–1.0; extracted triples default to 0.8
    var source: KAGTripleSource     // .session | .book
    var timestamp: Date
}

enum KAGTripleSource: String, Codable, Sendable {
    case session   // extracted from a Merlin turn
    case book      // extracted by xcalibre-server from book content at ingestion
}
```

| Plugin | Backend | When to use |
|---|---|---|
| `NullKAGPlugin` | No-op | Default; KAG disabled |
| `LocalKAGPlugin` | `~/.merlin/kag/graph.sqlite` | xcalibre-server not available |
| `XcalibreKAGPlugin` | xcalibre-server REST API | Preferred; fuses session graph with book knowledge graph |

### The fusion advantage (XcalibreKAGPlugin)

When xcalibre-server is active, a single graph traversal spans *both* the session graph (what you built) and the book knowledge graph (what the reference material says):

**PCB example** — anchor "U4", hops=2:
- From session: `(U4) –[shares_net]→ (VCC)`, `(U4) –[had_thermal_issue]→ (session:2026-04-10)`
- From books: `(high_current_IC) –[requires]→ (thermal_relief_via)`, `(VCC) –[connects]→ (C12, C15)`

**Culinary example** — anchor "turmeric", hops=2:
- From session: `(our_curry) –[uses]→ (turmeric)`, `(our_curry) –[outcome]→ (too_bitter)`
- From books: `(turmeric) –[flavor_profile]→ (earthy, bitter)`, `(saffron) –[substitutes_for]→ (turmeric)`, `(saffron) –[milder_than]→ (turmeric)`

The LLM receives working knowledge and reference knowledge fused — without the user needing to ask separately.

### File layout

```text
Merlin/KAG/
  KAGBackendPlugin.swift    — protocol, NullKAGPlugin, KAGTriple, KAGTripleSource
  KAGEngine.swift           — post-turn triple extraction (async, background)
  LocalKAGPlugin.swift      — SQLite actor: ~/.merlin/kag/graph.sqlite
  XcalibreKAGPlugin.swift   — HTTP client wrapping XcalibreClient graph endpoints
TestHelpers/
  CapturingKAGBackend.swift — records writes for assertions
```

### AppSettings additions

```swift
/// TOML key `kag_enabled`. Default: `false` until LocalKAGPlugin ships.
@Published var kagEnabled: Bool = false
/// TOML key `kag_hops`. Traversal depth at retrieval time.
@Published var kagHops: Int = 2
```

---

## CAG — Cache-Augmented Generation [v11, planned]

> **Status:** not implemented. This section reserves the design space; phase work is deferred. Today every Merlin turn re-bills the full input prompt — no `cache_control` markers are sent, and prefix instability across turns defeats implicit server-side and local KV reuse.

### Motivation

RAG (v9) and KAG (v10) handle *retrieval* — pulling the right knowledge into context per turn. They do nothing about the cost of the **static** prefix that ships with every request: the system prompt, tool schemas (~30+ tools), CLAUDE.md injections, pinned phase docs, and active domain plugin addenda. On a long agentic loop (Phase 150h sets `maxLoopIterations = 100`), that prefix is re-paid 100 times.

CAG splits the prompt into two layers:

- **Cold layer (cached)** — static, high-value, rarely changing. Cached once, reused across turns.
- **Hot layer (per-turn)** — conversation history, RAG chunks, KAG triples, tool results, user input.

The wins are concrete: Anthropic's prompt cache reads at ~10% of input cost; DeepSeek's server-side cache is automatic when prefixes are byte-stable; local LM Studio / vLLM-Metal reuse the KV cache across requests in the same session when the prefix is byte-stable. Claude Code itself reports ~92% cache hit rate using this pattern.

CAG is complementary to RAG/KAG, not a replacement: cache the *retriever's framing*, retrieve the *content*.

### What goes where

| Layer | Contents | Owner | Cache strategy |
|---|---|---|---|
| **Cold — system** | Base system prompt, OS/version block, tool registry schemas, permission-mode prelude | `ContextManager` cold-prefix builder | Anthropic `cache_control: ephemeral` on system block; stable byte order for DeepSeek + local KV |
| **Cold — project** | Active CLAUDE.md, active domain plugin `systemPromptAddendum`, pinned phase docs (manual pin) | `ContextManager` cold-prefix builder | Same cache block as above; flushed on project switch (see `WorkspaceCoordinator`) |
| **Hot — retrieved** | RAG chunks (v9), KAG subgraph (v10), AI-generated memories injected this turn | `RAGTools.buildEnrichedMessage()` | Never cached — injected *after* the cold prefix so cache stays valid |
| **Hot — conversational** | Prior turn history, current user message, tool call results | `LiveSession` | Never cached — last block; mutates every turn |

The invariant: the cold layer must be a **byte-identical prefix** across every request in a session. Any mutation (tool reorder, settings change, new injected memory) invalidates the cache. Hot content always appends; never prepends or interleaves.

### Architecture

```text
Turn start — prompt assembly
        │
        ▼
ContextManager.buildPrompt(session:)
        │
        ├── coldPrefix() ──────────────────────────────────► cache boundary
        │     • system prompt                                  (cache_control: ephemeral
        │     • tool schemas (sorted deterministically)         on Anthropic; stable
        │     • CLAUDE.md + domain addenda                      bytes for DeepSeek/local)
        │     • pinned phase docs
        │
        └── hotSuffix() ──────────────────────────────────────► (not cached)
              • RAG/KAG injection block
              • prior turn history
              • current user message
                      │
                      ▼
              Provider.send(prompt:)
                      │
                      ├── AnthropicProvider     — sets cache_control on system block
                      ├── DeepSeekProvider      — relies on byte-stable prefix (server auto)
                      ├── OpenAICompatibleProv. — same (OpenAI cache is automatic)
                      └── LocalModelManager     — same (llama.cpp/vLLM-Metal KV reuse)
```

### Cold-prefix discipline

Stabilizing the prefix is most of the work. Concrete rules:

1. **Tool schemas sorted by `name`** before serialization. Today `ToolRegistry.shared.allDefinitions()` returns in registration order, which mutates as MCP tools register/unregister.
2. **CLAUDE.md content read once at session start**, snapshotted into the cold prefix, and not re-read mid-session. A file-watcher change invalidates the cache and starts a new session prefix (explicit decision: don't try to surgically patch the cached prefix).
3. **Settings that affect the system prompt** (reasoning effort verbiage, permission mode banner) are pinned at session start. Mid-session toggles take effect on the *next* session, not the current one — same rationale as #2.
4. **RAG/KAG injections live in the hot suffix**, immediately before the current user message — never folded into the system block.
5. **Domain plugin addenda** are part of the cold prefix; switching the active plugin starts a new cached prefix.

### Provider implementation surface

| Provider | Mechanism | Required change |
|---|---|---|
| `AnthropicProvider` | `cache_control: {type: "ephemeral"}` on system block (and optionally on the last tool definition to cache the entire tool array) | Add `anthropic-beta: prompt-caching-2024-07-31` header; wrap system + tools in cache-marked blocks; emit cache hit/miss metrics from response `usage.cache_read_input_tokens` / `cache_creation_input_tokens` |
| `DeepSeekProvider` | Automatic server-side cache on stable prefix | None at the wire level; only the prefix-stability discipline above |
| `OpenAICompatibleProvider` | Automatic on OpenAI; varies on other compat servers | None at the wire level for OpenAI; document that compat servers may not cache |
| `LMStudioModelManager` / `VLLMModelManager` | Implicit KV cache reuse across same-session requests | None at the wire level. **Distinct from existing `cacheTypeK` / `--kv-cache-dtype`** — those configure cache *quantization*, not reuse |

### Metrics

Cache effectiveness is invisible without metrics. Add to the existing `ProviderBudget` / token-accounting path:

- `cacheReadTokens` — Anthropic `usage.cache_read_input_tokens` (and equivalent from other providers when exposed)
- `cacheCreationTokens` — Anthropic `usage.cache_creation_input_tokens`
- `cacheHitRate` — `cacheReadTokens / (cacheReadTokens + cacheCreationTokens + uncachedInputTokens)`, rolling per-session

Surface in the same place per-provider spend appears (Settings → Budget). Target after rollout: ≥80% hit rate on multi-turn agentic loops.

### Failure modes

- **Silent cache misses** — without metrics, a reorder or settings mutation kills the cache and costs rise with no visible cause. Mitigation: the metrics above are non-optional.
- **Cache thrash on project switch** — switching projects starts a new cold prefix every time. Acceptable for now; revisit if users hop projects frequently in a single session.
- **Tool registry churn from MCP** — MCP tools registering after session start mutate the tool list and invalidate the cache. Mitigation: MCP tool registration is part of session startup; tools registered mid-session don't enter the cached prefix until the next session.
- **Cache-too-much** — cramming optional content into the cold prefix balloons the per-session cache-write cost. Only pin content that will be referenced repeatedly within the session.

### File layout (planned)

```text
Merlin/CAG/
  CachePolicy.swift         — cold/hot classification, stable-sort helpers
  CacheMetrics.swift        — per-provider hit/miss accounting
Merlin/Engine/
  ContextManager.swift      — gains coldPrefix() / hotSuffix() split
Merlin/Providers/
  AnthropicProvider.swift   — emits cache_control blocks; reads usage cache fields
```

### AppSettings additions (planned)

```swift
/// TOML key `cag_enabled`. Default: `false` until phase work lands.
@Published var cagEnabled: Bool = false
/// TOML key `cag_pin_claude_md`. Whether project CLAUDE.md joins the cold prefix.
@Published var cagPinClaudeMD: Bool = true
/// TOML key `cag_pinned_phase_docs`. Explicit list of phase doc paths to pin.
@Published var cagPinnedPhaseDocs: [String] = []
```

### Open questions (resolve before phase work)

1. **Cache scope: per-session vs. per-project?** Anthropic's ephemeral cache has a 5-minute TTL — per-session is the natural fit. Cross-session reuse would need the longer-TTL beta.
2. **How does CAG interact with `ContextManager.compactIfNeededBeforeRun` (Phase 151a/b)?** Compaction mutates history — that's hot content, so the cold prefix survives. But if compaction ever touches the system block, cache dies. Decision: compaction is hot-only by contract.
3. **Worker subagents (V5 supervisor-worker)** — do workers inherit the supervisor's cold prefix, or build their own? Different system prompts argue for separate caches; shared tool schemas argue for shared. Likely answer: separate cold prefix per role, but the tool-schemas sub-block is identical across roles and Anthropic can cache it independently with a second `cache_control` marker.

---

## Provider Layer [v1]

### Design Decision: OpenAI Function Calling Format

All tool definitions use the OpenAI function calling wire format throughout. A single `ToolDefinition` schema works across all OpenAI-compatible providers with no translation layer. Anthropic requires in-provider translation (see below).

### Protocol [v1]

```swift
protocol LLMProvider: AnyObject, Sendable {
    var id: String { get }
    var baseURL: URL { get }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error>
}
```

### Provider Implementations

**`OpenAICompatibleProvider`** [v1] — single class covering all OpenAI-compatible endpoints. Parameterised by `baseURL`, `apiKey` (nil = no auth header for local providers), and `model`. Handles SSE via `SSEParser`. Used for: DeepSeek, OpenAI, Qwen, OpenRouter, Ollama, Jan.ai, LocalAI, Mistral.rs, vLLM-Metal, LM Studio, llama.cpp.

**`AnthropicProvider`** [v1] — separate implementation for the Anthropic Messages API. Differences from OpenAI-compatible:
- Auth: `x-api-key` + `anthropic-version: 2023-06-01` headers
- Request: `system` is a top-level field; tool definitions use `input_schema` not `parameters`
- SSE events: `content_block_delta` with `text_delta`, `thinking_delta`, `input_json_delta`
- Tool calls arrive as `tool_use` content blocks with `input_json_delta` argument fragments
- Tool results must be grouped into user-role messages as `tool_result` content blocks
- `AnthropicProvider` translates all of this to/from the shared `CompletionChunk` / `Message` types so `AgenticEngine` is unaware of the format difference

### ProviderConfig [v1]

```swift
enum ProviderKind: String, Codable, Sendable {
    case openAICompatible
    case anthropic
}

struct ProviderConfig: Codable, Sendable, Identifiable {
    var id: String               // "openai", "anthropic", "ollama", etc.
    var displayName: String
    var localModelManagerID: String?
    var baseURL: String          // user-configurable; local providers default to localhost
    var model: String            // model ID sent in requests
    var isEnabled: Bool
    var isLocal: Bool            // skip key requirement; probe for availability at launch
    var supportsThinking: Bool   // guards ThinkingConfig injection
    var supportsVision: Bool     // used by vision routing in AgenticEngine
    var kind: ProviderKind
    var budget: ProviderBudget?
}
```

### ProviderRegistry [v1]

`ProviderRegistry` is a `@MainActor ObservableObject` that owns all provider configuration. Config persists to `~/Library/Application Support/Merlin/providers.json`. API keys are in Keychain, one item per provider (`com.merlin.provider.<id> / api-key`).

```swift
@MainActor
final class ProviderRegistry: ObservableObject {
    @Published var providers: [ProviderConfig]        // remote + local provider configs
    @Published var activeProviderID: String
    @Published var availabilityByID: [String: Bool]   // live probe results for local providers

    func setAPIKey(_ key: String, for id: String) throws
    func readAPIKey(for id: String) -> String?
    func makeLLMProvider(for config: ProviderConfig) -> any LLMProvider
    func probeLocalProviders() async                  // fires at app launch
    var primaryProvider: any LLMProvider              // active provider as LLMProvider
    var visionProvider: any LLMProvider               // explicit vision assignment, else active-provider fallback
}
```

### Default Providers [v1]

| Provider | Kind | Base URL | Local | Thinking | Vision | Enabled by default |
|---|---|---|---|---|---|---|
| DeepSeek | OAI-compat | `api.deepseek.com/v1` | No | Yes | No | Yes |
| OpenAI | OAI-compat | `api.openai.com/v1` | No | No | Yes | No |
| Anthropic | Anthropic | `api.anthropic.com/v1` | No | Yes | Yes | No |
| Qwen | OAI-compat | `dashscope.aliyuncs.com/compatible-mode/v1` | No | No | Yes | No |
| OpenRouter | OAI-compat | `openrouter.ai/api/v1` | No | No | No | No |
| Ollama | OAI-compat | `localhost:11434/v1` | Yes | No | No | No |
| LM Studio | OAI-compat | `localhost:1234/v1` | Yes | No | Yes | Yes |
| Jan.ai | OAI-compat | `localhost:1337/v1` | Yes | No | Yes | No |
| LocalAI | OAI-compat | `localhost:8080/v1` | Yes | No | Yes | No |
| Mistral.rs | OAI-compat | `localhost:1235/v1` | Yes | No | No | No |
| vLLM-Metal | OAI-compat | `localhost:8000/v1` | Yes | No | No | No |
| llama.cpp | OAI-compat | `localhost:8081/v1` | Yes | No | Yes | No |

All base URLs are user-configurable in `ProviderSettingsView`.

### Main Workspace Slot Status [v2.3]

Providers are inventory; slots are routing. The main workspace must show routing state, not provider inventory. Enabling or configuring a provider in `ProviderSettingsView` must not create any visible workspace status badge unless a role slot is explicitly assigned to that provider.

The old top-of-window provider/status HUD and the visible permission-mode chip are retired from the main workspace. They were ambiguous because they showed a single effective provider or mode even though Merlin routes across four slots. Replacement is a collapsed slot-status panel at the bottom of the left session sidebar, below the session list and above the `New Project Workspace` button.

The panel always renders four rows:

```text
Slots
Execute       DeepSeek V4 Flash
Reason        DeepSeek V4 Pro
Orchestrate   Not configured
Vision        Not configured
```

Rules:

1. Rows are driven only by `AppSettings.slotAssignments`.
2. `ProviderRegistry.activeProviderID`, `ProviderRegistry.primaryProvider`, enabled provider state, and runtime fallback rules must not populate a row.
3. Every slot is always present. Unassigned slots render disabled/secondary with a grey status dot and the label `Not configured`.
4. Configured slots render the resolved provider/model display name from `ProviderRegistry.displayName(for:)`.
5. Virtual local model IDs (`backend:model`) render as the backend display name plus model name, consistent with the Settings picker.
6. Orchestrate may still fall back to reason internally, but the UI row must remain `Not configured` unless `slotAssignments[.orchestrate]` is set.
7. Vision may fall back internally for legacy behavior, but the UI row must remain `Not configured` unless `slotAssignments[.vision]` is set.
8. Status dots attach to the same rows: grey is not configured, green is ready or the last turn finished, orange is busy, and red means the last command/request on that slot threw an error.

Implementation surface:

```text
Merlin/Views/
  SlotStatusPanel.swift        — collapsed four-row slot routing summary
  SessionSidebar.swift         — embeds SlotStatusPanel in sidebar footer area

Data dependencies:
  AppSettings.slotAssignments
  ProviderRegistry.displayName(for:)
  AppState.slotRuntimeStates              — activity/error state only; never determines assignment
```

Acceptance criteria:

1. Enabling/configuring DeepSeek, LM Studio, llama.cpp, or any provider does not change the sidebar slot panel when all `slotAssignments` are nil.
2. With no slot assignments, the sidebar shows all four rows as `Not configured`.
3. Assigning only `execute` updates only the Execute row; Reason, Orchestrate, and Vision remain `Not configured`.
4. Assigning `execute = "llamacpp:qwen3-coder"` and `vision = "llamacpp:qwen3-vl"` shows both rows using the same provider backend with distinct model names.
5. The top main-screen provider badge is absent.
6. Unit/UI tests cover provider-enabled-without-slot, partial slot assignment, virtual provider display, and orchestrate/vision fallback not leaking into the panel.

### Thinking Mode Auto-Detection [v1]

Thinking mode is enabled when `ThinkingModeDetector` fires AND the active provider's `supportsThinking` is `true`. Signal words: `debug`, `why`, `architecture`, `design`, `explain`, `error`, `failing`, `unexpected`, `broken`, `investigate`. Suppressed for: `read`, `write`, `run`, `list`, `build`, `open`, `create`, `delete`.

`AgenticEngine` receives `primarySupportsThinking: Bool` from `AppState` (sourced from `ProviderRegistry`). Thinking config is only injected into the request when this flag is true.

```json
{ "thinking": { "type": "enabled" }, "reasoning_effort": "high" }
```

### Runtime Provider Selection [v1]

```
User message arrives
│
├── GUI screenshot task?   → explicit vision assignment, else active provider
└── All other tasks        → registry.primaryProvider (user-selected active provider)
```

The pro/execute split is retired. One active provider per session. A skill's `model` frontmatter field overrides the active provider for that skill's turn. [v2]

---

## Session Manager [v2] / WorkspaceCoordinator [v1.6]

### Single-Window Multi-Project Model [v1.6]

As of v1.6, Merlin uses a single `WindowGroup("Merlin", id: "workspace")`. Multiple projects are held simultaneously inside one window by `WorkspaceCoordinator` — see the **V1.6** section for full details. The multi-window model described below was superseded; it is preserved here for historical context.

### Multi-Window Model [v2, superseded by v1.6]

Each app window was scoped to exactly one project root. Opening a second project opened a second window.

```
File > Open Project…  (or drag a folder onto the Dock icon)
→  openWindow(value: ProjectRef(path: "/Users/jon/Projects/foo"))
→  new NSWindow with its own SessionManager + WorkspaceView
```

The entry point used `WindowGroup(for: ProjectRef.self)`. `ProjectRef` is a `Codable`, `Hashable` struct wrapping a resolved absolute path:

```swift
struct ProjectRef: Codable, Hashable, Transferable {
    var path: String          // absolute, resolved
    var displayName: String   // last path component
}
```

On launch with no existing windows, `ProjectPickerView` was shown. In v1.6 this is replaced by `WorkspaceCoordinator.showingProjectPicker` which presents the picker as a sheet inside the workspace window.

### LiveSession Lifecycle [v2.0]

`LiveSession` (`Sessions/LiveSession.swift`) wraps one `AppState` together with all per-session subsystems. It is created by `SessionManager` and torn down via `close() async`.

**Startup sequence** — `init` wires three background tasks stored in `lifecycleTasks: [Task<Void, Never>]`:

1. `MCPBridge.start(config:toolRouter:)` — merges global + project MCP configs and launches configured servers
2. Inject-file polling — watches `~/.merlin/inject.txt` every 2 s and posts `merlinInjectMessage` notifications
3. `MemoryEngine.startIdleTimer(timeout:)` — starts the idle timer if `AppSettings.memoriesEnabled`

**Shutdown** — `close() async` is guarded by `isClosed: Bool` to prevent double-teardown. It cancels all `lifecycleTasks`, calls `appState.stopEngine()`, `mcpBridge.stop()`, and `memoryEngine.stopIdleTimer()`. A `deinit` fallback cancels tasks if `close()` was not called.

**Domain scoping** — `LiveSession.init` carries `activeDomainIDs: [String]` and assigns them directly to `appState.engine.activeDomainIDs`. The shared `DomainRegistry` is queried via stateless helpers (`activeDomain(ids:)`, `taskTypes(ids:)`) so no global mutable state is touched when switching sessions.

### Parallel Sessions

Within a window, each session is an independent unit of work with its own:
- `AgenticEngine` instance (own context, own provider selection)
- Git worktree at `~/.merlin/worktrees/<session-id>/` (within the window's project repo)
- `StagingBuffer` holding pending writes awaiting Accept/Reject
- Permission mode (Ask / Auto-accept / Plan)
- CLAUDE.md loaded from the worktree root at session creation

Sessions are listed in a sidebar. Switching sessions is instant — all session state is in-memory while open.

```swift
@MainActor
final class SessionManager: ObservableObject {
    let projectRef: ProjectRef
    @Published var sessions: [Session] = []
    @Published var activeSessionID: UUID?

    func newSession(model: ModelID, mode: PermissionMode) async -> Session
    func closeSession(_ id: UUID) async
    func switchSession(to id: UUID)
}
```

`SessionManager` is owned by the window's root view and injected via `@StateObject`. It is not global.

### Git Worktree Isolation [v2]

```
1. git worktree add ~/.merlin/worktrees/<session-id> HEAD  (in projectRef.path repo)
2. All reads/writes in this session operate on the worktree path
3. User accepts diff → git commit in worktree
4. User merges → git merge worktree branch into project working tree
5. Session closed → git worktree remove <session-id>
```

For project roots that are not git repos, worktree isolation is skipped and the session operates directly on the project path (no diff/staging layer available; Auto-accept mode is forced).

---

## Agentic Engine [v1]

### Loop Structure

```
1.  Receive user message
2.  Auto-inject RAG context if xcalibreClient is configured and available (Option C)
3.  Append to context
4.  Select provider (see Runtime Provider Selection)
5.  Build CompletionRequest — inject ThinkingConfig only if primarySupportsThinking = true
6.  Stream completion — accumulate text and tool_calls
7.  If no tool_calls in response → stream final text to UI, end turn
8.  For each tool_call:
    a. Pass through AuthGate (approve / deny / remember)
    b. If denied → append denial result to context, continue loop
    c. If approved → execute tool, stream output to ToolLogView
    d. Append tool result to context
9.  Go to step 4 (loop continues until a turn produces no tool_calls)
```

Parallel tool calls are dispatched concurrently via Swift structured concurrency (`async let` / `TaskGroup`).

`AgenticEngine` receives `primarySupportsThinking: Bool` from the active `ProviderConfig` (via `ProviderRegistry`). It is recalculated each loop iteration so switching providers mid-session takes effect immediately.

```swift
var xcalibreClient: XcalibreClient?
var primarySupportsThinking: Bool { registry.activeConfig?.supportsThinking ?? false }
```

**[v2] Interrupt:** A stop button in the toolbar cancels the active `Task` and `AsyncThrowingStream` at any point. A `[Interrupted]` system note is appended. The session is left in a valid state.

### Error Policy [v1]

1. **First failure** — retry once silently after 1 second
2. **Second failure** — surface to user: tool name, arguments, error message, options: Retry / Skip / Abort
3. Auth patterns are never written on failed calls

### Context Manager [v1]

- Maintains the full message array including tool call results
- Tracks running token estimate (character count ÷ 3.5)
- At **800,000 tokens**: fires compaction
  - Summarises tool call result messages older than 20 turns into a compact digest
  - Preserves all user and assistant messages verbatim
  - Appends a `[context compacted]` system note
- Invoked skills are re-attached after compaction (5,000 tokens each, 25,000 token combined budget, most-recently-invoked first) [v2]

---

## Diff / Review Layer [v2]

### StagingBuffer

In **Ask** and **Plan** modes, `write_file`, `create_file`, `delete_file`, and `move_file` calls are intercepted and queued rather than applied to disk. In **Auto-accept** mode, writes apply immediately.

```swift
actor StagingBuffer {
    func stage(_ change: StagedChange)
    func accept(_ id: UUID) async throws
    func reject(_ id: UUID)
    func acceptAll() async throws
    func rejectAll()
    var pendingChanges: [StagedChange] { get }
}

struct StagedChange: Identifiable {
    var id: UUID
    var path: String
    var kind: ChangeKind          // write, create, delete, move
    var before: String?
    var after: String?
    var comments: [DiffComment]
}
```

### DiffPane [v2]

Renders each `StagedChange` as a unified diff (line-level, colour-coded). Controls per change: Accept, Reject, Comment. A `+N -N` badge in the toolbar opens the pane. After accepting all changes, the user can commit directly from the pane with an auto-generated title.

### Inline Diff Commenting [v2]

Clicking a diff line attaches a comment. On submit, all comments are sent to the agent as a follow-up message. The agent revises and the diff updates in place.

---

## Permission Modes [v2]

| Mode | File writes | Shell commands | Tool calls |
|---|---|---|---|
| **Ask** (default) | Staged, Accept/Reject required | Run, streamed | AuthGate applies |
| **Auto-accept** | Applied immediately | Run | AuthGate applies |
| **Plan** | Blocked — no writes | Blocked | Read-only tools only |

Mode is set per-session and shown in the toolbar. Cycle with `⌘⇧M`.

### Plan Mode [v2]

The agent is instructed via system prompt that it may not write, create, delete, or move files, and may not run shell commands. It may read files, inspect the AX tree, and call `list_directory`/`search_files`. The agent produces a structured plan which the user reviews and optionally edits. Clicking **Execute Plan** switches the session to Ask mode and submits the plan.

---

## Auth Gate & Sandbox [v1]

Every tool call passes through `AuthGate` before execution. MCP tools are subject to the same gate. [v2]

### Decision Flow

```
AuthGate.check(toolCall)
│
├── Matches a remembered ALLOW pattern? → execute silently
├── Matches a remembered DENY pattern?  → block silently, return error result
└── No match → show AuthPopupView
    ├── Allow Once     → execute, do not persist
    ├── Allow Always for <pattern> → execute, persist allow rule
    ├── Deny Once      → block, do not persist
    └── Deny Always for <pattern>  → block, persist deny rule
```

### Pattern Matching [v1]

| Tool | Example Pattern |
|---|---|
| `read_file` | `~/Documents/localProject/**` |
| `run_shell` | `xcodebuild *` |
| `app_launch` | `com.apple.Xcode` |
| `write_file` | `~/Documents/localProject/merlin/**` |
| `mcp:github:*` | `*/pull_request*` [v2] |

### Auth Memory Storage [v1]

Persisted to `~/Library/Application Support/Merlin/auth.json`. The file is written atomically and immediately `chmod 0600` via `FileManager.setAttributes([.posixPermissions: 0o600])` — readable only by the owning user, never group or world.

```json
{
  "allowPatterns": [
    { "tool": "read_file", "pattern": "~/Documents/localProject/**", "addedAt": "..." }
  ],
  "denyPatterns": [
    { "tool": "run_shell", "pattern": "rm -rf *", "addedAt": "..." }
  ]
}
```

### Auth Popup UI [v1]

Displays tool name, full arguments, reasoning step, suggested glob pattern, keyboard shortcuts: `⌘↩` Allow Once, `⌥⌘↩` Allow Always, `⎋` Deny.

---

## CLAUDE.md Loader [v2]

At session creation, `CLAUDEMDLoader` searches for instruction files from the project root upward:

```
<project-root>/CLAUDE.md
<project-root>/.merlin/CLAUDE.md
~/CLAUDE.md
```

All found files are concatenated (global last, project first) and prepended to the session system prompt as a `[Project instructions]` block. No tools are called — pure text injection at session init.

---

## Context Injection [v2]

### @filename

Typing `@` in the prompt input opens an autocomplete file picker. Selecting a file appends its contents inline as `[File: path]`. Large files are truncated at 2,000 lines; a line range can be specified: `@AgenticEngine.swift:50-120`.

### Attachment

The prompt input accepts drag-and-drop and clipboard paste:

| Type | Handling |
|---|---|
| Source files (`.swift`, `.md`, `.json`, etc.) | Inlined as `[File: name]` block |
| Images (`.png`, `.jpg`, `.heic`) | Sent to LM Studio for vision description, result inlined |
| PDF | Text extracted via PDFKit, inlined as `[PDF: name]` block |
| Binary | Rejected with error |

---

## Skills / Slash Commands [v2]

See `skill-standard.md` for the full specification. Summary:

- Skills are `SKILL.md` files (YAML frontmatter + markdown) in `~/.merlin/skills/<name>/` (personal) or `.merlin/skills/<name>/` (project)
- Invoked with `/skill-name` or automatically by the model when the description matches
- Frontmatter controls: invocation mode, allowed tools, model override, subagent fork, path scoping, argument substitution, shell injection
- `SkillsRegistry` loads all skills at session start and watches directories for live changes

### Built-in Skills [v2]

| Skill | Description | Invocation |
|---|---|---|
| `/review` | Code review of staged changes | User or model |
| `/plan` | Switch to plan mode and map out a task | User only |
| `/commit` | Generate commit message from staged diff | User only |
| `/test` | Write tests for a function or module | User or model |
| `/explain` | Explain selected code in plain English | User or model |
| `/debug` | Debug a failing test or error | User or model |
| `/refactor` | Propose a refactor for a code section | User or model |
| `/summarise` | Summarise the current session | User only |

---

## MCP Server Support [v2]

`MCPBridge` starts configured servers (stdio transport via `Foundation.Process`) and registers their tools into `ToolRouter` as `mcp:<server>:<tool>`. All MCP tool calls go through `AuthGate`. Server configs live in `~/.merlin/mcp.json` or a plugin's `.mcp.json`.

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}" }
    }
  }
}
```

stdio transport only in v2. HTTP/SSE deferred to v3.

---

## Scheduler [v2]

`SchedulerEngine` is the supported scheduled-task path. It persists recurring tasks in `~/Library/Application Support/Merlin/schedules.json`, opens a background session at fire time, applies the task's permission mode, waits for MCP readiness, runs the prompt, closes the session, and posts a macOS notification with a summary. Legacy `ThreadAutomation*` types remain internal-only and are not the supported user-facing scheduling surface.

```json
{
  "tasks": [
    {
      "id": "uuid",
      "name": "Daily code review",
      "cadence": "daily",
      "time": "09:00",
      "projectPath": "~/Documents/localProject/merlin",
      "permissionMode": "plan",
      "prompt": "/review"
    }
  ]
}
```

On fire: opens a background session, runs the prompt to completion, posts a macOS notification with a summary.

---

## AI-Generated Memories [v3]

Opt-in (disabled by default). `AppSettings.memoriesEnabled` is the gate. When enabled, a 5-minute idle timer fires after a session goes inactive. A `MemoryEngine` — a lightweight `AgenticEngine` instance using the fastest model in the session's current provider — receives the session transcript and generates a memory file.

### Pipeline

```
session idle (5 min)
    → MemoryEngine.generate(transcript:)
        → writes .md file to ~/.merlin/memories/pending/<uuid>.md
        → posts UNUserNotification: "Memory ready for review"
user opens Settings > Memories > pending queue
    → reviews / edits / accepts or rejects
        → accepted: moved to ~/.merlin/memories/<uuid>.md
        → rejected: deleted
next session init (CLAUDEMDLoader)
    → reads ~/.merlin/memories/*.md
    → injects as second system prompt block after CLAUDE.md content
```

### Exclusion rules (enforced in MemoryEngine system prompt)

- No verbatim file contents
- No strings matching secret patterns (tokens, API keys, passwords, private keys)
- No raw tool result payloads
- Extract only: preferences, workflow conventions, project patterns, known pitfalls

### MemoryEngine

Isolated `AgenticEngine` instance; no tool access; single turn; result written to `pending/`. Generation happens off the main actor in a detached `Task`. If generation fails, the pending file is not created and the failure is logged silently — no user-facing error.

---

## Hooks [v3]

`HookEngine` intercepts the agentic lifecycle at defined event points. Hooks are shell scripts defined inline in `~/.merlin/config.toml`. Project-level hooks in `.merlin/config.toml` require the trusted-project flag (same as MCP servers).

### Hook events

| Event | When | Can block |
|---|---|---|
| `PreToolUse` | Before tool call reaches AuthGate | Yes — returning `deny` prevents the call |
| `PostToolUse` | After tool completes | No — can inject a `systemMessage` into context |
| `UserPromptSubmit` | Before user message is sent to provider | No — can augment prompt via `systemMessage` |
| `Stop` | After a turn completes | No — can trigger continuation |

### Ordering

`PreToolUse` hooks run before `AuthGate`. Automated policy fires first; human approval is only requested for calls that pass hook policy. A crashing or timing-out `PreToolUse` hook is treated as `deny` (fail-closed).

### I/O protocol

Hook scripts receive a JSON object on stdin:

```json
{ "session_id": "…", "event": "PreToolUse", "tool_name": "write_file",
  "tool_input": { "path": "…", "content": "…" } }
```

They return JSON on stdout:

```json
{ "decision": "allow" }
{ "decision": "deny", "reason": "write to /etc is forbidden" }
{ "systemMessage": "Note: file has been linted." }
```

Exit code `0` with empty stdout = allow/passthrough. Exit code `2` with stderr = deny with message.

### Config.toml representation

```toml
[[hooks.PreToolUse]]
matcher = "write_file"
command = "/Users/jon/.merlin/hooks/block-etc-writes.sh"

[[hooks.PostToolUse]]
matcher = "run_shell"
command = "/Users/jon/.merlin/hooks/log-commands.sh"
```

### HookEngine

```swift
actor HookEngine {
    func runPreToolUse(toolName: String, input: [String: Any]) async -> HookDecision
    func runPostToolUse(toolName: String, result: String) async -> String?  // optional systemMessage
    func runUserPromptSubmit(prompt: String) async -> String?
    func runStop() async -> Bool  // true = continue
}

enum HookDecision: Sendable {
    case allow
    case deny(reason: String)
}
```

---

## PR Monitor [v2]

`PRMonitor` polls GitHub PRs associated with the active project (60s active, 5min background). On `checksFailed`: posts a notification; opening it launches a new session pre-loaded with the PR diff and CI output. On `checksPassed`: merges if auto-merge was enabled for that PR. Requires a GitHub token in Connectors config.

---

## External Connectors [v2]

Thin read/write wrappers for external services. Credentials in Keychain per service.

| Connector | Read | Write |
|---|---|---|
| **GitHub** | PR status, CI checks, issues, file contents | Create PR, comment, merge, push |
| **Slack** | Channel messages (configured channels) | Post message |
| **Linear** | Issues, project status, cycle items | Create issue, update status, comment |

Connectors are opt-in. MCP server equivalents (e.g. `@modelcontextprotocol/server-github`) can replace native connectors if preferred.

---

## Tool Registry [v1]

All tools are defined as OpenAI function call schemas and registered at app launch.

### ToolRegistry [v3]

`ToolRegistry` is a Swift `actor` and the runtime source of available tools. `ToolDefinitions` retains static schema definitions for built-in tools; `ToolRegistry.shared.registerBuiltins()` copies them into the registry at app launch. Dynamic tools (MCP, web search, future conditional tools) register and unregister at runtime without restarting the app.

```swift
actor ToolRegistry {
    static let shared = ToolRegistry()
    func register(_ tool: ToolDefinition)
    func unregister(named: String)
    func all() -> [ToolDefinition]
    func contains(named: String) -> Bool
    func registerBuiltins()
}
```

`ToolRouter` queries `ToolRegistry.shared.all()` for dispatch. There is no enforced count on built-in tools. Tests assert named tools are present via `contains(named:)`, not a total count.

### File System Tools [v1]

| Tool | Description |
|---|---|
| `read_file(path)` | Returns file contents with line numbers |
| `write_file(path, content)` | Writes or overwrites a file |
| `create_file(path)` | Creates an empty file |
| `delete_file(path)` | Deletes a file |
| `list_directory(path, recursive?)` | Returns directory tree |
| `move_file(src, dst)` | Moves or renames |
| `search_files(pattern, path, content_pattern?)` | Glob + optional grep |

### Shell Tool [v1]

`run_shell(command, cwd?, timeout_seconds?)`

- Executes via `Foundation.Process`
- Captures stdout and stderr separately
- Streams output lines to ToolLogView in real time
- Default timeout: 120 seconds; Xcode builds: 600 seconds
- Working directory defaults to the active project path (worktree path in v2)

### App Launch & Control [v1]

| Tool | Description |
|---|---|
| `app_launch(bundle_id, arguments?)` | Launch via NSWorkspace |
| `app_list_running()` | Returns running app bundle IDs and PIDs |
| `app_quit(bundle_id)` | Graceful quit |
| `app_focus(bundle_id)` | Bring app to foreground |

### Tool Discovery [v1]

`tool_discover()` — scans `$PATH` at call time, returns installed CLI tools with `--help` summaries. All discovered tools are invoked via `run_shell` and go through AuthGate. Known GUI-launching binaries are blocklisted from `--help` probing.

### Xcode Tools [v1]

| Tool | Description |
|---|---|
| `xcode_build(scheme, configuration, destination?)` | Runs `xcodebuild`, streams output |
| `xcode_test(scheme, test_id?)` | Runs test suite or single test |
| `xcode_clean()` | Cleans build folder |
| `xcode_derived_data_clean()` | Nukes DerivedData |
| `xcode_open_file(path, line)` | Opens file at line in Xcode via AppleScript |
| `xcode_xcresult_parse(path)` | Extracts failures, warnings, coverage from `.xcresult` |
| `xcode_simulator_list()` | Returns available simulators |
| `xcode_simulator_boot(udid)` | Boots a simulator |
| `xcode_simulator_screenshot(udid)` | Captures simulator screen |
| `xcode_simulator_install(udid, app_path)` | Installs `.app` on simulator |
| `xcode_spm_resolve()` | Runs `swift package resolve` |
| `xcode_spm_list()` | Lists resolved SPM dependencies |

Build output is parsed for errors and warnings and structured before being appended to context.

### Preview Tools [v2]

Registered only when a preview server is running.

| Tool | Description |
|---|---|
| `preview_get_dom()` | Returns DOM of the current preview URL |
| `preview_screenshot()` | Screenshot of the preview pane |
| `preview_get_console()` | Browser console log |

---

## GUI Automation [v1]

Three strategies operate in concert. The agent selects observation strategy per app based on AX availability; CGEvent is always the execution layer.

### Strategy A — Accessibility Tree (AXUIElement) [v1]

| Tool | Description |
|---|---|
| `ui_inspect(bundle_id)` | Returns full AX element tree as structured JSON |
| `ui_find_element(bundle_id, role?, label?, value?)` | Locates a specific element |
| `ui_get_element_value(element_id)` | Reads current value |

Requires Accessibility permission.

### Strategy B — Screenshot + Vision [v1]

| Tool | Description |
|---|---|
| `ui_screenshot(bundle_id?, region?)` | Captures window or region via ScreenCaptureKit |
| `vision_query(image_id, prompt)` | Sends frame to Qwen2.5-VL-72B, returns response |

Capture parameters: logical resolution, JPEG quality 85, crop to active window, target under 1MB before encoding. Vision model called at `temperature: 0.1`, 256-token max, structured JSON output: `{"x": int, "y": int, "action": string, "confidence": float}`.

Requires Screen Recording permission.

### Strategy C — Input Simulation (CGEvent) [v1]

| Tool | Description |
|---|---|
| `ui_click(x, y, button?)` | Mouse click |
| `ui_double_click(x, y)` | Double click |
| `ui_right_click(x, y)` | Context menu trigger |
| `ui_drag(from_x, from_y, to_x, to_y)` | Click-drag |
| `ui_type(text)` | Keyboard input |
| `ui_key(key_combo)` | Modifier + key (e.g. `cmd+s`) |
| `ui_scroll(x, y, delta_x, delta_y)` | Scroll |

### Runtime Strategy Selection [v1]

```swift
func selectGUIStrategy(for bundleID: String) async -> GUIObservationStrategy {
    let tree = await AXInspector.probe(bundleID)
    return tree.elementCount > 10 && tree.hasLabels ? .accessibilityTree : .visionModel
}
```

Probe result cached per-app for the session duration.

---

## Session Persistence [v1]

Sessions saved to `~/Library/Application Support/Merlin/sessions/` as JSON. Written incrementally after each turn.

```json
{
  "id": "uuid",
  "title": "auto-generated from first user message",
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601",
  "providerID": "deepseek",
  "messages": [
    {
      "role": "user | assistant | tool",
      "content": "...",
      "toolCalls": [],
      "toolCallId": "...",
      "thinkingContent": "...",
      "timestamp": "ISO8601"
    }
  ],
  "authPatternsUsed": ["pattern1", "pattern2"]
}
```

**[v2] additions to session record:** `worktreePath`, `permissionMode`, `modelID`, `scheduledTaskID` (if fired by scheduler), `skillsInvoked`.

---

## SwiftUI Interface

### Views

**[v1] ChatView** — primary conversation thread. Markdown rendered with CommonMark two-space hard line break. Tool calls shown as collapsible cards. Thinking content in dimmed expandable block.

**[v2] ChatView additions** — stop button (visible while `isSending`), `@` autocomplete file picker, attachment button, model picker dropdown, scroll-lock: manual upward scroll pauses auto-scroll-to-bottom while streaming continues off-screen; auto-scroll resumes when user scrolls back within 40pt of the bottom. Permission mode remains configurable through settings/commands rather than a persistent main-surface badge.

**[v3] ChatView — WKWebView message renderer (planned)**

The conversation message list will be migrated from SwiftUI `Text`-per-message to a single `WKWebView` (`NSViewRepresentable`) rendering the entire thread as HTML. SwiftUI's `Text` views are isolated selection units at the AppKit level; dragging a selection across message boundaries is architecturally impossible regardless of `.textSelection(.enabled)` placement. This mirrors the approach used by the Claude desktop app and OpenAI Codex, both of which are Electron (Chromium) apps and get cross-message selection for free from the browser's DOM selection model.

Design:
- `ConversationWebView: NSViewRepresentable` wraps a `WKWebView` in non-editable, non-navigable mode
- All messages rendered as a single HTML document via `WKWebView.loadHTMLString(_:baseURL:)`; baseURL set to `~/.merlin/` so `file://` image references resolve
- Streaming: new content appended via `WKWebView.evaluateJavaScript("appendChunk(...)")` — no full reload
- Markdown: rendered server-side (Swift → HTML) before passing to the web view; fenced code blocks get syntax-highlighted `<pre><code>` blocks
- Images: PNG/JPEG/WebP/SVG embedded as `data:image/...;base64,...` URIs for in-memory content (screenshots, vision outputs); `file://` URIs for on-disk assets
- Interactive elements (thinking toggle, tool expand/collapse, copy button) bridged via `WKScriptMessageHandler` — JavaScript posts events, Swift handles them
- Theme: CSS custom properties (`--bg`, `--fg`, `--bubble-user`, `--bubble-assistant`, etc.) injected at load time and updated via `evaluateJavaScript` on theme change; respects `prefers-color-scheme`
- Selection and copy: fully native — browser selection, system copy menu, Cmd+A, Cmd+C all work across the entire thread
- Find (Cmd+F): `WKFindConfiguration` on macOS 13+ gives in-page find for free

**LLM-generated image display (planned, depends on WKWebView renderer):**

WKWebView is a prerequisite for inline image display but is not sufficient alone. Two layers must both be in place:

1. **Rendering (unlocked by WKWebView):** `<img src="data:image/png;base64,...">` or `<img src="https://...">` in the message HTML displays generated images inline. SwiftUI `Text` cannot do this at all.

2. **Parsing (separate work required):** The streaming response parser currently reads only text deltas. To surface generated images it must also detect image payloads in API responses and produce a `ChatItem` with an image kind rather than plain text. Each provider returns images differently:
   - OpenAI image generation (`gpt-image-1`, DALL-E 3): `data[]` array with `b64_json` or `url` fields — separate endpoint, not in the chat stream
   - GPT-4o multimodal output: image content block in the chat completion response
   - DeepSeek, Anthropic, local models: do not generate images

Once the WKWebView renderer exists, adding image kinds to the parser and passing them as base64 data URIs or remote URLs becomes straightforward. Without the renderer it is architecturally blocked regardless of parser support.

**[v1] ToolLogView** — live stdout/stderr stream from running tools. Colour-coded by source.

**[v1] ScreenPreviewView** — last screenshot from `ui_screenshot`. On-demand only.

**[v1] AuthPopupView** — modal, non-dismissable via background click.

**[v1 retired] Provider/status HUD** — the old toolbar indicator for active provider and thinking/tool state is superseded in v2.3. Routing status now lives in the left-sidebar `SlotStatusPanel`, and the main surface must not show provider inventory or fallback-derived routing.

**[v1] FirstLaunchSetupView** — Keychain setup on first run. Calls `appState.reloadProviders(apiKey:)` after saving.

**[v2] ProjectPickerView** — shown at launch when no windows are open. Recent projects list (resolved paths, last-opened timestamp), Open button (triggers folder panel), clear-recents option. Selecting a project calls `openWindow(value: projectRef)` and dismisses the picker.

**[v2] SessionSidebar** — lists open sessions with title and activity indicator, embeds `SlotStatusPanel`, and provides the new session button.

**[v2] DiffPane** — staged changes as unified diff, Accept/Reject/Comment per change, commit button.

**[v2] FilePane** — read-only syntax-highlighted file viewer. Opens on click of any file path in chat.

**[v2] TerminalPane** — persistent user-controlled terminal (`Ctrl+\``).

**[v2] PreviewPane** — `WKWebView` + dev server log stream.

**[v2] SkillsPicker** — `/` overlay with fuzzy-searchable skill list.

**[v2] SideChat** — slide-over ephemeral chat panel (`⌘⇧/`). No context shared with active session. Not persisted.

**[v2] SchedulerView** — settings panel for managing recurring tasks.

**[v2] ConnectorsView** — GitHub / Slack / Linear credentials and status.

**[v2] MCPServersView** — MCP server configuration and tool listing.

### Workspace Layout [v2]

Default arrangement: SessionSidebar | ChatPane | DiffPane (top) / TerminalPane (bottom) | FilePane. Preview Pane hidden by default. All panes draggable, collapsible, resizable. Layout persisted to `~/Library/Application Support/Merlin/layout.json`.

### App Entitlements [v1]

```xml
<key>com.apple.security.app-sandbox</key>
<false/>

<key>com.apple.security.network.client</key>
<true/>
```

System permissions (requested on first use): Accessibility, Screen Recording.

---

## Settings Window [v3]

A unified configuration surface accessible via Cmd+, (SwiftUI `Settings { }` scene) and Edit > Options (calls `NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)`). Two entry points, one singleton window.

### Navigation model

`NavigationSplitView` with a list sidebar on the left and a detail view on the right — macOS System Settings style. Sections grow as v3 features are added; each feature phase contributes its own section.

### AppSettings

`@MainActor ObservableObject` singleton. Single source of truth for all configurable state. All features read from `AppSettings`; none read directly from UserDefaults, Keychain, or config.toml. Writes immediately to the appropriate backing store on change.

| Backing store | What lives there |
|---|---|
| `~/.merlin/config.toml` | Memories toggle, idle timeout, hooks, search config, reasoning overrides, toolbar actions, agent standing instructions |
| Keychain | API keys, connector tokens, search API key |
| UserDefaults | UI-only state — theme, fonts, font sizes, message density, window layout |

`config.toml` is watched via FSEvents; external edits update `AppSettings` live. `ConnectorsView` (phase 43) is absorbed into the Connectors section and removed as a standalone view.

### Sections

| Section | Contents |
|---|---|
| **General** | Startup behavior, default permission mode, notifications, keep-awake toggle |
| **Appearance** | Theme, UI font + size, code font + size, message density, accent color, live preview pane |
| **Providers** | API key per provider, endpoint URL for local providers (LM Studio, Ollama), model capability overrides |
| **Agent** | Default model, reasoning effort default, standing custom instructions |
| **Memories** | Enable/disable, idle timeout, generation model, pending review queue (list with accept/reject per file) |
| **Connectors** | GitHub / Slack / Linear tokens and status (replaces ConnectorsView) |
| **MCP** | MCP server list — add/remove/edit, connection status |
| **Skills** | Skill directory paths, per-skill enable/disable |
| **Hooks** | View and edit hook definitions inline, grouped by event type |
| **Search** | Brave API key, enable/disable |
| **Permissions** | Auth pattern memory — current allow/deny list, clear all |
| **Advanced** | "Show config file in Finder", "Show memories folder in Finder", reset to defaults |

### Appearance section

- **Theme** — Picker: System / Light / Dark; applied via SwiftUI `preferredColorScheme`
- **UI font** — Family picker + size stepper; applied to message text, sidebar, labels
- **Code font** — Monospace-filtered family picker + size; applied to tool output, code blocks, diff view
- **Message density** — Segmented: Compact / Comfortable / Spacious; controls vertical padding in ChatView
- **Accent color** — `ColorPicker`; stored in UserDefaults; overrides SwiftUI accent environment
- **Live preview pane** — Non-interactive sample ChatView rendered inline, updates in real time as values change

### Build order

Settings window shell (navigation + Appearance + AppSettings stub) is built in the config.toml foundation phase. Each subsequent v3 phase adds its own section to the list.

---

## API Key Management [v1]

One Keychain item per remote provider. Local providers require no key.

```
Service:   com.merlin.provider.<id>
Account:   api-key
Accessible: kSecAttrAccessibleAfterFirstUnlock
```

Examples:
```
com.merlin.provider.deepseek  / api-key
com.merlin.provider.openai    / api-key
com.merlin.provider.anthropic / api-key
com.merlin.provider.qwen      / api-key
com.merlin.provider.openrouter/ api-key
```

> **Note:** The xcalibre RAG server token (`xcalibre_token`) is **not** stored in Keychain. It lives in `~/.merlin/config.toml` and is read via `AppSettings.xcalibreToken`. Local services with no secret value do not warrant Keychain storage.

`ProviderRegistry.setAPIKey(_:for:)` writes and `readAPIKey(for:)` reads. Keys never written to disk in plaintext, never included in session JSON, never logged.

`ProviderSettingsView` lets the user enter API keys and toggle providers from the settings sheet. On the first launch for any remote provider, `FirstLaunchSetupView` prompts for the active provider's key and writes it via `ProviderRegistry`.

**[v2]** Connector tokens (GitHub, Slack, Linear) stored as separate Keychain items under `com.merlin.<service>`.

---

## Project Structure

```
Merlin/
├── App/
│   ├── MerlinApp.swift
│   ├── AppState.swift
│   ├── MerlinCommands.swift
│   ├── ProjectRef.swift              [v2] — Codable/Hashable/Transferable project root
│   ├── RecentProjectsStore.swift     [v2] — persists recent project paths
│   └── ToolRegistration.swift
├── Agents/                           [v4]
│   ├── AgentDefinition.swift         — TOML-loaded agent definition
│   ├── AgentRegistry.swift           — loads ~/.merlin/agents/*.toml; built-ins
│   ├── SpawnAgentTool.swift          — spawn_agent ToolDefinition
│   ├── SubagentEngine.swift          — V4a explorer subagent (AsyncStream<SubagentEvent>)
│   ├── SubagentEvent.swift           — event enum for subagent stream
│   ├── WorkerSubagentEngine.swift    — V4b write-capable worker; worktree isolation
│   └── WorktreeManager.swift        [v2/v4] — git worktree CRUD + exclusive locking
├── Auth/
│   ├── AuthGate.swift
│   ├── AuthMemory.swift
│   └── PatternMatcher.swift
├── Automations/                      [v3]
│   ├── ThreadAutomation.swift
│   ├── ThreadAutomationEngine.swift
│   └── ThreadAutomationStore.swift
├── Config/                           [v3]
│   ├── AppSettings.swift             — @MainActor singleton; config.toml source of truth
│   ├── AppearanceSettings.swift
│   ├── HookConfig.swift
│   ├── SettingsProposal.swift
│   ├── TOMLDecoder.swift
│   ├── TOMLParser.swift
│   └── TOMLValue.swift
├── Connectors/                       [v2]
│   ├── Connector.swift               — protocol: init(token:), isConfigured
│   ├── ConnectorCredentials.swift    — Keychain per service (com.merlin.<service>)
│   ├── GitHubConnector.swift
│   ├── LinearConnector.swift
│   ├── PRMonitor.swift               — 60s/300s GitHub polling; auto-merge
│   └── SlackConnector.swift
├── Engine/
│   ├── AgenticEngine.swift
│   ├── CLAUDEMDLoader.swift          [v2] — searches 3 paths; injects at session init
│   ├── ContextInjector.swift         [v2] — @mention + attachment handling
│   ├── ContextManager.swift
│   ├── ContextUsageTracker.swift     [v3]
│   ├── DiffComment.swift             [v2]
│   ├── DiffEngine.swift              [v2] — Myers diff; DiffHunk/DiffLine
│   ├── PermissionMode.swift          [v2] — ask / autoAccept / plan
│   ├── StagingBuffer.swift           [v2] — intercept writes in ask/plan mode
│   ├── ThinkingModeDetector.swift
│   └── ToolRouter.swift
├── Hooks/                            [v3]
│   ├── HookDecision.swift
│   └── HookEngine.swift              — PreToolUse/PostToolUse/UserPromptSubmit/Stop; fail-closed
├── Keychain/
│   └── KeychainManager.swift
├── MCP/                              [v2]
│   ├── MCPBridge.swift               — stdio transport via Foundation.Process
│   ├── MCPConfig.swift               — loads ~/.merlin/mcp.json
│   └── MCPToolDefinition.swift
├── Memories/                         [v3]
│   ├── MemoryEngine.swift            — idle timer; pending/ queue; sanitization
│   └── MemoryEntry.swift
├── Notifications/                    [v3]
│   └── NotificationEngine.swift
├── Providers/
│   ├── LLMProvider.swift
│   ├── OpenAICompatibleProvider.swift
│   ├── AnthropicProvider.swift
│   ├── AnthropicSSEParser.swift
│   ├── ProviderConfig.swift          — ProviderConfig + ProviderKind + ProviderRegistry
│   ├── ProviderRegistry+ReasoningEffort.swift [v3]
│   ├── ReasoningEffort.swift         [v3]
│   ├── SSEParser.swift
│   ├── DeepSeekProvider.swift        — kept for live test backward compat
│   └── LMStudioProvider.swift        — kept for live test backward compat
├── RAG/
│   ├── XcalibreClient.swift          — RAG HTTP client, actor-based; token from AppSettings
│   └── RAGTools.swift
├── Scheduler/                        [v2]
│   ├── ScheduledTask.swift
│   └── SchedulerEngine.swift
├── Sessions/
│   ├── Session.swift
│   ├── SessionStore.swift
│   ├── SessionManager.swift          [v2] — parallel session lifecycle per window
│   └── LiveSession.swift             [v2] — one AppState + PermissionMode per session
├── Skills/                           [v2]
│   ├── Skill.swift
│   ├── SkillFrontmatter.swift
│   └── SkillsRegistry.swift          — personal (~/.merlin/skills/) + project (.merlin/skills/)
├── Toolbar/                          [v3]
│   ├── ToolbarAction.swift
│   └── ToolbarActionStore.swift
├── Tools/
│   ├── ToolDefinitions.swift
│   ├── ToolRegistry.swift            [v3] — dynamic actor; registerBuiltins()
│   ├── FileSystemTools.swift
│   ├── ShellTool.swift
│   ├── AppControlTools.swift
│   ├── ToolDiscovery.swift
│   ├── XcodeTools.swift
│   ├── AXInspectorTool.swift
│   ├── ScreenCaptureTool.swift
│   ├── CGEventTool.swift
│   ├── VisionQueryTool.swift
│   └── WebSearch/                    [v3]
│       ├── BraveSearchClient.swift
│       └── WebSearchTool.swift
├── UI/
│   ├── Chat/                         [v4]
│   │   ├── SubagentBlockView.swift
│   │   └── SubagentBlockViewModel.swift
│   ├── Memories/                     [v3]
│   │   └── MemoryReviewView.swift
│   ├── Settings/                     [v3]
│   │   └── SettingsWindowView.swift
│   └── Sidebar/                      [v4]
│       ├── SubagentSidebarEntry.swift
│       ├── SubagentSidebarRowView.swift
│       ├── SubagentSidebarViewModel.swift
│       └── WorkerDiffView.swift
├── Views/
│   ├── AtMentionPicker.swift         [v2]
│   ├── AuthPopupView.swift
│   ├── ChatView.swift
│   ├── ConnectorsView.swift          [v2]
│   ├── ContentView.swift
│   ├── DiffPane.swift                [v2]
│   ├── FirstLaunchSetupView.swift
│   ├── ProjectPickerView.swift       [v2]
│   ├── SchedulerView.swift           [v2]
│   ├── ScreenPreviewView.swift
│   ├── SessionSidebar.swift          [v2]
│   ├── SkillsPicker.swift            [v2]
│   ├── ToolLogView.swift
│   ├── WorkspaceView.swift           [v2] — SessionSidebar + ChatPane layout
│   └── Settings/
│       └── ProviderSettingsView.swift
├── Voice/                            [v3]
│   └── VoiceDictationEngine.swift    — SFSpeechRecognizer; Ctrl+M toggle
└── Windows/                          [v3]
    └── FloatingWindowManager.swift   — pop-out floating chat window
```

---

## Key Dependencies

No third-party Swift packages in the production target.

| Framework | Purpose | Version |
|---|---|---|
| `SwiftUI` | UI | v1 |
| `Foundation` | Networking, Process, JSON | v1 |
| `ScreenCaptureKit` | Window and screen capture | v1 |
| `Accessibility` | AXUIElement tree inspection | v1 |
| `CoreGraphics` | CGEvent input simulation | v1 |
| `AppKit` | NSWorkspace app launch/control | v1 |
| `Security` | Keychain read/write | v1 |
| `PDFKit` | PDF text extraction for attachments | v2 |
| `WebKit` | WKWebView for preview pane (v2); WKWebView for conversation message renderer (v3 planned) | v2 |
| `BackgroundTasks` | Scheduled task wake-ups | v2 |
| `XCTest` | All test layers (test targets only) | v1 |

MCP servers are external processes (stdio). No Swift package dependency introduced.

---

## Testing Strategy [v1]

All implementation phases are preceded by a test phase.

### Test Layers

**Layer 1 — Unit (fast, always run)** [v1]
Pure logic, no I/O. Covers: PatternMatcher, ThinkingModeDetector, ContextManager, token estimation, session serialisation.

**Layer 2 — Integration (fast, always run)** [v1]
Real file system, real `Foundation.Process`, mocked LLM responses. Covers: all tools, xcresult parsing, AX probing, screenshot pipeline.

**[v2] Layer 2 additions:** StagingBuffer accept/reject, WorktreeManager create/remove, CLAUDEMDLoader discovery, SkillsRegistry loading and frontmatter parsing, MCPBridge tool registration.

**Layer 3 — Live Provider (slow, manual trigger)** [v1]
Real DeepSeek API + real LM Studio. Scheme: `MerlinTests-Live`. Requires `DEEPSEEK_API_KEY` env var and LM Studio running.

**Layer 4 — End-to-End Visual (slow, manual trigger)** [v1]
Full agentic loop with real models + SwiftUI UI. Drives `TestTargetApp` fixture.

### Visual Testing [v1]

| Concern | Method | Automated |
|---|---|---|
| Widget clipped outside container | `XCUIElement.frame` within parent bounds | Yes |
| Overlapping elements | Frame intersection checks | Yes |
| Accessibility violations | `XCUIApplication().performAccessibilityAudit()` | Yes |
| Rendering artifacts | `XCTAttachment(screenshot:)` | Manual review |

---

## Decisions Summary

| Decision | v1 | v2 |
|---|---|---|
| Window model | Single window | One window per project (`WindowGroup(for: ProjectRef.self)`); project picker on launch |
| Session model | Single serial thread | Parallel sessions in Git worktrees, scoped to window's project |
| File write policy | Direct to disk | Staged via StagingBuffer, Accept/Reject in DiffPane |
| Permission model | AuthGate only | AuthGate + Ask / Auto-accept / Plan modes |
| CLAUDE.md | Not supported | Auto-loaded at session init |
| Skills | None | Slash-command registry, global + per-project, Agent Skills standard |
| MCP | None | stdio transport, tools auto-registered into ToolRouter |
| Scheduling | None | SchedulerEngine with BackgroundTasks; Plan mode default |
| PR monitoring | Shell only | PRMonitor polls GitHub API; auto-merge on green |
| External connectors | None | GitHub, Slack, Linear (opt-in) |
| Workspace layout | Fixed | Draggable/collapsible panes, persisted |
| Interrupt | None | Stop button cancels active Task + stream |
| Chat scroll | Always follows bottom | Auto-scroll pauses on manual upward scroll; resumes within 40pt of bottom |
| Context injection | Manual | @filename autocomplete + file/image/PDF attachment |
| Model selection | Fixed per provider | Per-session model picker |
| In-app preview | None | WKWebView + dev server process + preview tools |
| MCP transport | N/A | stdio only (HTTP/SSE deferred to v3) |
| Tool call wire format | OpenAI function calling | Unchanged |
| LLM providers | DeepSeek (remote) + LM Studio (local) | 10 providers via OpenAICompatibleProvider + AnthropicProvider; ProviderRegistry |
| Provider config | Hardcoded in AppState | ProviderConfig JSON + Keychain per provider; ProviderSettingsView |
| API key storage | Single Keychain item (`com.merlin.deepseek`) | One item per provider (`com.merlin.provider.<id>`); connector tokens added per-service |
| Thinking mode | Always injected when detector fires | Gated by `supportsThinking` flag on active ProviderConfig |
| Vision routing | Fixed to LM Studio | First local provider with `supportsVision = true` |
| Provider selection | Pro (complex) / Flash (simple) split | Single active provider per session; skill `model` field overrides |
| RAG | None | xcalibre-server auto-inject (3 chunks) + explicit rag_search/rag_list_books tools |
| Context compaction | 800K token threshold | Unchanged; skills re-attached after compaction |
| Auth sandbox | Pattern memory + popup | Unchanged; MCP tools subject to same gate |
| App sandbox | Non-sandboxed | Unchanged |
| Third-party dependencies | None | None (MCP servers are external processes) |
| TDD | Yes | Yes |
| GUI automation test target | TestTargetApp fixture | Unchanged |

| Decision | v3 |
|---|---|
| Platform | macOS only |
| Config system | `~/.merlin/config.toml` (FSEvents-watched; external edits reflect live) |
| Settings window | SwiftUI `Settings {}` scene + Edit > Options; `NavigationSplitView` sidebar + detail; `AppSettings` singleton |
| Settings source of truth | `AppSettings` @MainActor ObservableObject; features never read UserDefaults/Keychain/TOML directly |
| Appearance | Theme, UI font, code font, message density, accent color; live preview pane in settings |
| ConnectorsView | Absorbed into Settings > Connectors; standalone view removed |
| Hooks | Inline in config.toml; PreToolUse runs before AuthGate (fail-closed on crash) |
| Memories | Opt-in; idle trigger (5 min); pending review queue in ~/.merlin/memories/pending/; fastest model in session's provider |
| Web search | Brave Search API; absent when no key configured |
| Reasoning effort | Per-model capability flag; LM Studio uses name-pattern matching + user override in config.toml |

---

## Subagents [v4]

### Overview

V4 adds parallel subagent execution. The parent `AgenticEngine` can spawn child agents via a
`spawn_agent` tool call. Children run concurrently in a `TaskGroup`, stream events back into
the parent's message stream in real time, and are displayed as inline collapsible blocks in the
chat UI. V4a children are read-only explorers. V4b children are write-capable workers, each
isolated in their own git worktree.

### AgentDefinition

Defined in TOML. Loaded from `~/.merlin/agents/*.toml` by `AgentRegistry` at launch. Three
built-in definitions are always present (cannot be overridden by user files):

| Name | Role | Tool set | Description |
|---|---|---|---|
| `default` | default | full (inherits parent) | General purpose; same tools as parent |
| `worker` | worker | full + write | Write-capable; gets its own git worktree in V4b |
| `explorer` | explorer | read-only | Fast research agent; no writes, no shell mutations |

TOML schema for custom agents (`~/.merlin/agents/my-agent.toml`):
```toml
name = "my-agent"
description = "Short description shown in spawn_agent tool picker"
instructions = "You are a specialist in..."
model = "claude-haiku-4-5-20251001"   # optional; inherits parent model if absent
role = "explorer"                       # explorer | worker | default
allowed_tools = ["read_file", "grep"]  # optional; overrides role defaults
```

### AgentRegistry

```swift
actor AgentRegistry {
    static let shared = AgentRegistry()
    func load(from dir: URL) async throws   // loads ~/.merlin/agents/*.toml
    func all() -> [AgentDefinition]
    func definition(named: String) -> AgentDefinition?
    func registerBuiltins()
}
```

### spawn_agent tool

Registered in `ToolRegistry` alongside built-in tools. The LLM calls it to spawn a subagent:

```json
{
  "name": "spawn_agent",
  "description": "Spawn a subagent to run a task in parallel. The agent streams its activity back here.",
  "parameters": {
    "agent": "explorer",
    "prompt": "Search the codebase for all uses of URLSession and summarize the patterns."
  }
}
```

`AgenticEngine` handles this tool call by creating a `SubagentEngine`, subscribing to its event
stream, and forwarding `SubagentEvent` values into the parent's `MessageStream`.

### SubagentEvent

```swift
enum SubagentEvent: Sendable {
    case toolCallStarted(toolName: String, input: [String: Any])
    case toolCallCompleted(toolName: String, result: String)
    case messageChunk(String)
    case completed(summary: String)
    case failed(Error)
}
```

### SubagentEngine

```swift
actor SubagentEngine {
    init(
        definition: AgentDefinition,
        prompt: String,
        parent: AgenticEngine,
        depth: Int
    )
    var events: AsyncStream<SubagentEvent> { get }
    func start() async
    func cancel()
}
```

Each `SubagentEngine`:
- Has its own isolated `ContextManager`
- Inherits the parent's `HookEngine` (hooks apply to all subagent tool calls)
- Uses a tool set gated by the agent's role (explorer = read-only, worker = full)
- Respects `AppSettings.maxSubagentDepth` — refuses to spawn further children beyond the limit
- Runs within the parent's `TaskGroup` slot — `AppSettings.maxSubagentThreads` controls concurrency
- Executes real tool calls and feeds their actual results back into the child model loop before completion

Current hard limit:
- nested `spawn_agent` from inside a subagent is explicitly rejected rather than emulated

### Explorer tool set (V4a read-only)

| Category | Allowed tools |
|---|---|
| File system | `read_file`, `list_directory`, `search_files` |
| Search | `grep`, `find_files` |
| Shell | `bash` — read-only commands only (no writes, no sudo, no pipes to mutating commands) |
| Web | `web_search` (if API key configured) |
| Knowledge | `rag_search` |

Write tools (`write_file`, `create_file`, `delete_file`, `move_file`, `apply_diff`) and all
Xcode/CGEvent/AX tools are absent from the explorer tool set.

### V4a UI — Inline collapsible blocks

Each active subagent renders as a collapsible block in the parent's `ChatView`:

```
▼ [explorer] Searching codebase for URLSession patterns…
  ● grep — searching 47 files
  ● read_file — Sources/Network/APIClient.swift
  ✓ Found 12 uses across 4 files. Summary: all calls go through APIClient…
```

Blocks collapse to a single summary line when the subagent completes.

### WorktreeManager (V4b)

```swift
actor WorktreeManager {
    func create(sessionID: UUID, in repo: URL) async throws -> URL
    func remove(sessionID: UUID) async throws
    func lock(sessionID: UUID) async throws
    func unlock(sessionID: UUID)
    func isLocked(sessionID: UUID) -> Bool
}
```

Each V4b worker subagent gets an isolated worktree at `~/.merlin/worktrees/<sessionID>/`.
The lock prevents two workers from writing to the same path concurrently. `StagingBuffer` per
subagent tracks proposed changes for user review before merge.

### V4b UI — Sidebar child entries

Write-capable subagents are promoted from inline blocks to child entries in `SessionSidebar`,
indented under the parent:

```
● Session: refactor auth module
  ↳ [worker] Updating AuthGate…
  ↳ [worker] Writing tests…
```

Each child entry opens its own diff view showing the `StagingBuffer` for that worktree.

### AppSettings additions (v4)

```toml
max_subagent_threads = 4   # max concurrent subagent TaskGroup slots
max_subagent_depth = 2     # max spawn_agent nesting depth
```

---

| Decision | v4 |
|---|---|
| Dispatch | `spawn_agent` tool call — model-driven, same pattern as all other tools |
| Result communication | Streaming `AsyncStream<SubagentEvent>` — no structured return intermediary |
| Explorer tool set | read_file, list_directory, search_files, grep, bash (read-only), web_search, rag_search |
| Hook inheritance | Children inherit parent HookEngine — hooks apply to all subagent tool calls |
| Thread/depth limits | `max_subagent_threads` and `max_subagent_depth` in AppSettings / config.toml |
| V4a UI | Inline collapsible blocks in parent chat stream |
| V4b UI | Promote write-capable workers to SessionSidebar child entries with per-worktree diff view |
| Streaming shell pane | Deferred to v5 |

---

## V5 — Domain Plugin System

Merlin is a general-purpose agentic assistant, not a software development tool. Current focus is software development (Swift/Xcode, any language via SSH or remote plugin), but the architecture is designed so that new domains — electronics (schematics, PCB gerber files), construction (building plans, wiring, plumbing, code compliance), culinary (recipes), or any other — can be added without modifying core Merlin code.

A domain is packaged as an MCP server. It registers at startup and contributes domain-specific task types, a verification backend, complexity keywords, tools, and prompt guidance. The core V5 mechanisms (critic, tracker, planner, routing) consume whatever the active domain provides — they have no knowledge of which domain is running.

### DomainPlugin Protocol

Every domain implements this contract:

```swift
protocol DomainPlugin {
    var id: String { get }                          // e.g. "software", "electronics", "construction"
    var displayName: String { get }
    var taskTypes: [DomainTaskType] { get }         // domain-specific task classifications
    var verificationBackend: VerificationBackend { get }
    var highStakesKeywords: [String] { get }        // elevates complexity tier on match
    var systemPromptAddendum: String? { get }       // domain-specific system prompt addition
    var mcpToolNames: [String] { get }              // tools this domain contributes via MCP
}
```

**MCP bridge — `MCPDomainAdapter`**

MCP servers are external processes communicating via JSON-RPC — they cannot directly conform to a Swift protocol. An MCP domain server advertises its capabilities through a standard resource schema (`merlin://domain/manifest`), and a Swift `MCPDomainAdapter` reads that manifest at connection time and wraps it into a `DomainPlugin`:

```swift
struct MCPDomainAdapter: DomainPlugin {
    // Populated from the MCP server's domain manifest at startup
    init(manifest: DomainManifest, mcpServerID: String)
}

struct DomainManifest: Decodable {
    var id: String
    var displayName: String
    var taskTypes: [DomainTaskType]
    var highStakesKeywords: [String]
    var systemPromptAddendum: String?
    var verificationCommands: [String: [VerificationCommand]]  // taskType.name → commands
}
```

The built-in `SoftwareDomain` and `ElectronicsDomain` conform directly to `DomainPlugin` in Swift. External domains arrive via `MCPDomainAdapter`; manifest IDs such as `pcb` or `kicad` are canonicalised to the product-facing `electronics` domain where appropriate.

### DomainTaskType

Replaces the hardcoded `TaskType` enum. Each domain registers its own task types, which the tracker records against and the planner classifier uses:

```swift
struct DomainTaskType: Hashable, Codable {
    var domainID: String    // "software", "pcb", "construction", etc.
    var name: String        // "codeGeneration", "schematicDesign", "floorPlan", etc.
    var displayName: String
}
```

`DomainRegistry.shared` maintains the live set of registered task types. The `ModelPerformanceTracker` keys profiles on `DomainTaskType` rather than a hardcoded enum, so it automatically tracks performance for any domain that registers.

### VerificationBackend Protocol

Stage 1 of the critic is domain-provided, not hardcoded to compile/test/lint:

```swift
protocol VerificationBackend {
    // Returns nil if this domain has no deterministic verification for the given task type.
    // The backend is initialised with its config at construction — no config parameter here.
    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]?
}

enum PassCondition {
    case exitCode(Int)                    // process exit code must match
    case outputContains(String)           // stdout/stderr must contain this substring
    case custom((String) -> Bool)         // arbitrary predicate on combined output
}

struct VerificationCommand {
    var label: String           // "Compile", "DRC", "Code compliance check"
    var command: String         // shell command — may be local, SSH, or plugin-provided
    var passCondition: PassCondition
}
```

Remote execution (SSH, plugin API) is handled at the command level — `command` can be `ssh user@host 'cargo check'` or any other shell-executable string. Merlin's `ShellTool` runs it without knowing whether it's local or remote.

Built-in backends shipped with Merlin:

| Backend | Domain | Checks |
|---|---|---|
| `SoftwareVerificationBackend` | Software development | Compile, test, lint — configured via `verify_command` / `check_command` |
| `NullVerificationBackend` | Domains with no deterministic check | Stage 1 always passes; Stage 2 (model) handles all verification |

Future backends (shipped as domain plugins):

| Backend | Domain | Checks |
|---|---|---|
| `PCBVerificationBackend` | Electronics | DRC, electrical rules check (ERC), Gerber export validation |
| `ComplianceVerificationBackend` | Construction | Building code compliance — queries xcalibre or online code databases |

### DomainRegistry

```swift
actor DomainRegistry {
    static let shared: DomainRegistry

    func register(_ plugin: DomainPlugin) async
    func unregister(id: String) async
    func activeDomain() -> DomainPlugin        // falls back to SoftwareDomain if none set
    func taskTypes() -> [DomainTaskType]       // active domain only (multi-domain deferred)
    func plugin(for id: String) -> DomainPlugin?
}
```

Domains register at MCP server startup and unregister when the server disconnects. The active domain is set in `AppSettings` and shown in the toolbar alongside the active provider. One active domain at a time — multi-domain sessions are deferred.

### Built-in: Software Domain

The software development domain is the default plugin, always registered. It provides:

```swift
struct SoftwareDomain: DomainPlugin {
    let id = "software"
    let displayName = "Software Development"

    let taskTypes: [DomainTaskType] = [
        .init(domainID: "software", name: "codeGeneration",  displayName: "Code Generation"),
        .init(domainID: "software", name: "refactoring",     displayName: "Refactoring"),
        .init(domainID: "software", name: "explanation",     displayName: "Explanation"),
        .init(domainID: "software", name: "multiFileEdit",   displayName: "Multi-File Edit"),
        .init(domainID: "software", name: "shellCommand",    displayName: "Shell Command"),
        .init(domainID: "software", name: "other",           displayName: "Other"),
    ]

    let highStakesKeywords = ["migration", "auth", "security", "delete", "drop", "permission"]

    var verificationBackend: VerificationBackend { SoftwareVerificationBackend() }
}
```

Verification config per project in `config.toml`:

```toml
[domain.software.verification]
verify_command = "xcodebuild build -scheme Merlin"
check_command  = "xcodebuild test -scheme MerlinTests"
lint_command   = "swiftlint"
# Remote example:
# verify_command = "ssh build-host 'cargo check --manifest-path /srv/project/Cargo.toml'"
```

### Adding a New Domain

To add a domain (e.g. PCB):

1. Build an MCP server that exposes a `merlin://domain/manifest` resource — `MCPDomainAdapter` reads it at connection time and wraps it into a `DomainPlugin` automatically
2. Provide `taskTypes`, `highStakesKeywords`, `verificationCommands`, and any MCP tools in the manifest
3. Set `active_domain = "pcb"` in `config.toml` or switch in Settings
4. No changes to core Merlin required

The tracker, critic, planner, and routing all adapt automatically to whatever the registered domain provides.

| Decision | Domain system |
|---|---|
| Extension mechanism | MCP server exposing `merlin://domain/manifest`; `MCPDomainAdapter` wraps it into `DomainPlugin` |
| Task types | Domain-registered `DomainTaskType` — no hardcoded enum |
| Verification | `VerificationBackend` protocol — domain provides check commands |
| Remote execution | `verify_command` can be any shell string, including SSH |
| Default domain | `SoftwareDomain` — always registered, cannot be removed |
| Multi-domain | One active domain at a time — multi-domain sessions deferred |
| Core changes on new domain | None required |

## Merlin v2.0 — Electronics/KiCad Feature Set

This section is the architecture source of truth for KiCad integration requirements.

KiCad and related electronics workflows are Merlin v2.0 scope. They use the v2 MCP/tool-registry foundation directly and are not deferred to the later generic DomainPlugin milestone.

#### Locked v2.0 decisions

1. Raster/PDF schematic ingestion is in v2.0 scope.
2. Merlin owns the KiCad MCP server (`merlin-kicad-mcp`).
3. Extraction confidence is computed from measurable multi-extractor agreement, not LLM self-report.
4. Ambiguity resolution uses a targeted clarification loop.
5. Footprint assignment order is: existing KiCad field, exact MPN, package constraint, project default, user clarification.
6. First MVP fabrication profile is `jlcpcb_2layer_default`; follow-on profiles are `pcbway_2layer`, `oshpark_2layer`, then `custom`.
7. Requirement-driven Ethernet/control designs may use IoT/component modules to reduce custom high-speed layout risk.
8. Missing SPICE models block completion only when simulation is required and no legal model or acceptable generic substitute is available.
9. Merlin may generate project-local symbols/footprints only when verification gates pass.
10. Distributor integration includes BOM export, pricing/availability lookup, order preparation, and order submission.
11. Board-house profiles are required immediately, not deferred behind generic Gerber checks.
12. Placement and net-class repair are allowed automatically; layer-count and fabrication-profile changes require user approval.
13. Routing uses FreeRouting first, wrapped by `merlin-kicad-mcp` through KiCad DSN/SES interchange.
14. Schematic mutation uses a Merlin-owned `.kicad_sch` S-expression parser/writer with round-trip tests.

#### Product intents

1. `Draw me a pcb from this schematic - <schematic.pdf/png>`
2. `Design me a start/stop circuit with ethernet that monitors front-panel signals`

Merlin must not report success from schematic generation alone. Completion requires deterministic electrical and manufacturing gates.

#### KiCad baseline and integration modes

1. KiCad CLI version requirement: `>= 10.0.0` (lower versions are rejected with `BLOCKED_VERSION`).
2. Hybrid execution strategy from day one:
   - CLI: primary authority for deterministic checks and release gates.
   - MCP: structured mutation/introspection during placement/routing workflows.
   - GUI + vision: fallback and visual QA only, never sole pass authority.
3. No KiCad core fork required for MVP; integration is external via CLI/MCP/automation.

#### KiCad MCP server requirement

Merlin v2.0 owns the KiCad MCP integration layer. The target server is `merlin-kicad-mcp`, an external MCP server process that wraps KiCad CLI and KiCad's supported scripting/API surfaces behind OpenAI-compatible tool contracts.

The architecture does not depend on an unnamed community server. Community MCP servers may be inspected for prior art, but production coverage is provided by Merlin's server.

Required MCP coverage:

1. Project creation and file discovery
2. Schematic parse/read/write operations
3. Symbol, footprint, field, and library introspection
4. Netlist extraction and parity checks
5. Board outline, stackup, design-rule, and net-class mutation
6. Footprint assignment and placement mutation
7. Routing pass orchestration and connectivity inspection
8. ERC, DRC, fabrication export, and report parsing
9. SPICE scenario generation, execution, and result parsing
10. Screenshot/GUI attachment points for visual QA fallback

If the required server or a required tool is unavailable, electronics workflows return `BLOCKED_TOOLING`.

#### Tool contract recommendation

All KiCad tools use OpenAI function-calling schemas and return a common result envelope:

```swift
struct KiCadToolResult: Codable, Sendable {
    var status: KiCadStatus
    var artifacts: [ArtifactRef]
    var violations: [KiCadViolation]
    var metrics: [String: Double]
    var questions: [ClarificationQuestion]
    var nextActions: [String]
}
```

Recommended v2.0 tool set:

| Tool | Required input | Required output |
|---|---|---|
| `kicad_check_version` | `kicad_cli_path`, `required_major` | detected version, capability map, `BLOCKED_VERSION` on failure |
| `kicad_ingest_schematic` | source artifact path, source type, extraction profile | `ExtractionReport`, source-coordinate evidence, clarification questions |
| `kicad_answer_clarification` | extraction/design id, answers/annotations | updated `ExtractionReport`, remaining ambiguity count |
| `kicad_build_intent_model` | extraction report or requirements, board profile, constraints | `DesignIntent`, assumptions, unresolved engineering decisions |
| `kicad_select_components` | design intent, vendor/source policy | component matrix, selected MPNs/modules, rejected alternatives |
| `kicad_prepare_libraries` | selected components, library policy | project-local symbols/footprints/3D refs, library verification report |
| `kicad_assign_footprints` | schematic/design intent, component matrix | footprint assignment report, `unknown_footprints` |
| `kicad_compile_project` | design intent, libraries, board profile | `.kicad_pro`, `.kicad_sch`, `.kicad_pcb`, compile diagnostics |
| `kicad_apply_board_profile` | board profile, outline, stackup | applied constraints, DRC rule summary |
| `kicad_generate_net_classes` | design intent, board profile | `NetClassPlan`, diff-pair/power/control assignments |
| `kicad_place_components` | placement plan, board file | placement diagnostics, congestion/routability metrics |
| `kicad_route_pass` | board file, router profile, iteration state | route report, routed percentage, failing nets |
| `kicad_check_connectivity` | board file | unrouted nets, ratsnest/suspended trace metrics |
| `kicad_run_erc` | schematic/project | structured ERC violations |
| `kicad_run_drc` | board/project | structured DRC violations |
| `kicad_check_parity` | schematic, board | schematic/PCB component and net parity report |
| `kicad_run_spice` | simulation scenarios, model paths | raw traces, measurements, simulator logs |
| `kicad_evaluate_simulation` | measurements, tolerance envelopes | pass/fail deltas, `BLOCKED_SIMULATION` reasons |
| `kicad_visual_inspect` | KiCad window/project, inspection profile | screenshot evidence, overlap/orientation/readability findings |
| `kicad_export_fab` | project, fabricator profile | Gerbers, drills, BOM, PnP, drawings, CAM report |
| `kicad_prepare_vendor_order` | normalized BOM, vendor, quantity | native BOM/cart payload, price/availability report |
| `kicad_submit_vendor_order` | approved vendor cart/order payload | order confirmation or blocked approval/payment state |
| `kicad_package_release` | fab outputs, verification report | signed release package or pending sign-off state |

Routing decision: v2.0 wraps FreeRouting through `merlin-kicad-mcp` as the first autorouting backend using KiCad DSN/SES interchange, while Merlin owns placement, net-class generation, rule setup, route retry policy, and deterministic KiCad verification after every import. A future custom router can be added behind the same `kicad_route_pass` contract.

Schematic mutation decision: v2.0 owns a strict `.kicad_sch` S-expression parser/writer with round-trip tests. GUI automation is fallback only for operations that cannot be safely expressed through file/API mutation.

#### Design data schemas

The KiCad domain persists these canonical schemas so tool calls are resumable and auditable:

```swift
struct DesignIntent: Codable, Sendable {
    var intentID: String
    var sourceArtifacts: [ArtifactRef]
    var requirements: [Requirement]
    var assumptions: [Assumption]
    var components: [ComponentIntent]
    var nets: [NetIntent]
    var boardProfile: BoardProfile
    var safetyProfile: SafetyProfile
}

struct ExtractionReport: Codable, Sendable {
    var sourceArtifact: ArtifactRef
    var components: [ExtractedComponent]
    var nets: [ExtractedNet]
    var unresolvedRegions: [SourceRegion]
    var confidence: ExtractionConfidence
    var ambiguousNets: Int
    var unknownComponents: Int
}

struct NormalizedBOM: Codable, Sendable {
    var lines: [BOMLine]
    var vendorMappings: [VendorBOMMapping]
    var substitutions: [SubstitutionCandidate]
}

struct BoardProfile: Codable, Sendable {
    var id: String
    var fabricator: String
    var layerCount: Int
    var stackup: [StackupLayer]
    var copperWeightOz: Double
    var minTraceMm: Double
    var minClearanceMm: Double
    var minViaDrillMm: Double
    var minViaPadMm: Double
    var copperToEdgeMm: Double
    var impedanceRequirements: [ImpedanceRule]
    var differentialPairRules: [DifferentialPairRule]
}

struct NetClassPlan: Codable, Sendable {
    var classes: [NetClass]
    var assignments: [NetClassAssignment]
    var differentialPairs: [DifferentialPair]
}

struct PlacementPlan: Codable, Sendable {
    var fixedItems: [PlacementConstraint]
    var regions: [PlacementRegion]
    var componentPlacements: [ComponentPlacement]
    var optimizationMetrics: [String: Double]
}

struct SimulationScenario: Codable, Sendable {
    var id: String
    var required: Bool
    var netlistPath: String
    var modelRefs: [ModelRef]
    var stimuli: [SimulationStimulus]
    var measurements: [MeasurementSpec]
    var tolerances: [ToleranceEnvelope]
}

struct FabPackage: Codable, Sendable {
    var fabricatorProfileID: String
    var gerbers: [ArtifactRef]
    var drills: [ArtifactRef]
    var bom: ArtifactRef
    var pickAndPlace: ArtifactRef?
    var drawings: [ArtifactRef]
    var stepModels: [ArtifactRef]
}

struct VerificationReport: Codable, Sendable {
    var gates: [VerificationGateResult]
    var approvals: [ApprovalRecord]
    var assumptions: [Assumption]
    var releaseStatus: KiCadStatus
}
```

#### Hard completion gates (all required)

1. Connectivity gate: `unrouted_nets == 0`
2. ERC gate: zero error-level ERC violations
3. DRC gate: zero error-level DRC violations
4. Parity gate: schematic/PCB net + component parity pass
5. Fabrication gate: Gerber + drill export success and required artifact sanity checks
6. Simulation gate (applicable designs): all required scenarios pass tolerance checks
7. High-stakes sign-off gate: explicit user approval before final fabrication release

If any gate fails, status is not `COMPLETE`.

#### Schematic extraction pipeline

Raster and PDF schematic ingestion is a multi-stage extraction problem, not OCR alone.

Extraction stages:

1. Preprocess input: deskew, de-noise, normalize contrast, split pages/sheets, detect title blocks.
2. Detect primitives: wires, buses, junction dots, no-connect markers, labels, symbol boxes, pins, power symbols, and off-sheet connectors.
3. Recognize symbols: match against known KiCad/library symbols first, then use vision classification for unknowns.
4. OCR text fields: RefDes, values, net labels, pin numbers, sheet names, and annotations.
5. Trace connectivity graph: convert wire geometry, junctions, labels, power symbols, and off-sheet references into a candidate net graph.
6. Infer implicit nets: global labels, power symbols, repeated labels, hierarchical sheet pins, and bus entries.
7. Produce an extraction report: components, pins, nets, confidence evidence, unresolved regions, and source image coordinates.
8. Human clarification loop: ambiguous nets/components are surfaced as targeted questions or annotation tasks before synthesis proceeds.

Confidence is computed from measurable agreement between independent extractors, not from LLM self-report alone.

Confidence model:

1. Per-detection confidence is a weighted score from geometry (`0.30`), OCR/text (`0.20`), library match (`0.25`), net-graph plausibility (`0.15`), and cross-pass agreement (`0.10`).
2. Critical fields use the minimum score across the field, attached symbol, attached pin, and attached net.
3. Contradictions are hard vetoes, not averaged away: conflicting pin counts, incompatible package geometry, impossible junction topology, or ERC-impossible net graphs force ambiguity.
4. Overall extraction confidence is the lower of aggregate component confidence and aggregate net confidence.
5. LLM/vision model output can propose detections, but it cannot certify confidence without supporting geometry/library/net evidence.

Confidence sources:

1. Geometry confidence: line continuity, junction consistency, pin-to-wire attachment, crossing-vs-junction disambiguation.
2. OCR confidence: text engine confidence plus agreement across rotated/cropped passes.
3. Library match confidence: symbol geometry and pin-count agreement with known symbols.
4. Net graph confidence: ERC-like plausibility checks before KiCad project generation.
5. Cross-pass agreement: deterministic extractor, vision model, and KiCad import/export parity where available.

No raster/PDF input proceeds to PCB synthesis until `ambiguous_nets == 0` and `unknown_components == 0`. The path to zero ambiguity is explicit user clarification or replacement input, not silent guessing.

#### Hand-drawn schematic policy

Hand-drawn, whiteboard, and paper sketch schematics are accepted only as conceptual input for requirements capture. They are not accepted as authoritative schematic-to-PCB extraction sources unless they independently meet the same geometry/OCR/library/net confidence thresholds as machine-drawn schematics.

Expected behavior:

1. Hand-drawn inputs usually return `BLOCKED_INPUT_QUALITY` for direct PCB synthesis.
2. Merlin may convert a hand-drawn sketch into a proposed clean schematic intent model, but it must ask for user confirmation before treating it as the source schematic.
3. The user-facing blocked report explains which items failed: unreadable labels, ambiguous junctions, uncertain pin attachments, unrecognized symbols, or insufficient geometry confidence.
4. A cleaned KiCad schematic, vector PDF, or high-resolution machine-drawn image is the preferred replacement input.

#### Input quality and extraction thresholds

1. Minimum raster input quality: `300 DPI`
2. Overall extraction confidence: `>= 0.985`
3. Critical field confidence (RefDes, net labels, connector pins): `>= 0.995`
4. Required pre-synthesis conditions:
   - `ambiguous_nets == 0`
   - `unknown_components == 0`
5. Route loop defaults:
   - `max_route_iterations = 15`
   - early stop after `3` no-improvement iterations

#### Footprint assignment

Every schematic symbol must resolve to a footprint before board synthesis.

Footprint assignment order:

1. Preserve existing KiCad footprint fields when present.
2. Resolve by exact MPN/vendor part metadata when available.
3. Resolve by package constraints from the requirements/BOM (`0603`, `SOIC-8`, `RJ45_MAGJACK`, etc.).
4. Resolve from approved project/library defaults.
5. Ask for user clarification when multiple physically incompatible choices remain.

The assignment report records symbol, selected footprint, source evidence, package dimensions, pin-count match, and unresolved alternatives. `unknown_footprints > 0` blocks PCB synthesis.

#### Component library management

Requirement-driven design must manage symbols, footprints, 3D models, and vendor fields as first-class artifacts.

Library policy:

1. Prefer KiCad standard libraries and project-local approved libraries.
2. Vendor/imported symbols and footprints are copied into a project-local library before use.
3. Generated custom symbols/footprints require pin-count, pin-name, pad-number, and package-dimension checks.
4. Every selected component stores manufacturer, MPN, vendor part numbers, lifecycle status, and substitution policy.
5. Missing libraries return `BLOCKED_LIBRARY` unless the workflow is allowed to generate and verify project-local library entries.

#### Board constraints, stackup, and fabrication profiles

Routing cannot begin until a board profile is selected or fully specified.

Required board inputs:

1. Board outline and mounting constraints
2. Fabricator profile (`jlcpcb_2layer_default`, `pcbway_2layer`, `oshpark_2layer`, or `custom`)
3. Layer count and stackup
4. Copper weight
5. Minimum trace/space
6. Via drill and pad sizes
7. Copper-to-edge clearance
8. Soldermask/silkscreen constraints
9. Impedance-control requirements when present
10. Assembly-side and height constraints when present

If the user omits these, Merlin may propose a default prototype profile, but the chosen profile is written into the design intent model and verification report.

Default profile order:

1. `jlcpcb_2layer_default` for MVP and unspecified prototype jobs.
2. `pcbway_2layer` as the second board-house profile.
3. `oshpark_2layer` as the third board-house profile.
4. `custom` for user-specified stackups, constraints, and board houses.

Layer-count or fabrication-profile changes during recovery require explicit user approval.

#### Net class management

Net classes are generated before routing and verified before DRC.

Required net-class categories:

1. Power rails and high-current paths
2. Ground and plane-connected nets
3. Ethernet MDI differential pairs
4. Clocks, reset, and timing-sensitive signals
5. Low-speed control/status signals
6. Isolation-boundary nets

Ethernet profiles must include differential-pair constraints, length/skew targets where applicable, magnetics/protection placement rules, and keepout/return-path checks.

Default Ethernet differential-pair rules:

1. `ethernet_100base_tx`: intra-pair skew <= `10 mm`, pair-to-pair skew advisory only unless a module/vendor guide specifies tighter limits.
2. `ethernet_1000base_t`: intra-pair skew <= `5 mm`, pair-to-pair skew <= `25 mm` unless vendor/module documentation specifies otherwise.
3. Characteristic impedance target: `100 ohm differential`, tolerance supplied by board profile/fabricator when impedance control is requested.
4. Vendor module or PHY layout guidance overrides defaults when cited in the source corpus.
5. If board stackup cannot support the requested impedance/skew profile, the workflow returns `BLOCKED_ENGINEERING_DECISION` or requests a board-profile change.

For v2.0 requirement-driven Ethernet/control designs, component selection may prefer IoT/component modules with integrated Ethernet PHY/MAC/magnetics or certified module layouts when they satisfy requirements. This reduces custom high-speed layout burden. Custom Ethernet PHY layouts remain allowed only when the selected profile includes the required net-class, placement, simulation/check, and board-house constraints.

#### Auto-placement strategy

Placement is an explicit optimization stage before routing.

Placement order:

1. Fixed mechanical items: connectors, mounting holes, board-edge controls, LEDs, switches.
2. Safety/isolation regions and keepouts.
3. Power entry, protection, regulation, and bulk capacitance.
4. High-speed interfaces: Ethernet PHY/magnetics/RJ45/ESD network.
5. MCU, oscillators, reset/programming headers, local decoupling.
6. I/O expanders, front-panel signal conditioning, pullups, debounce/filter networks.
7. Test points, labels, and assembly affordances.

Optimization criteria include routability, critical-net length, power-loop area, return-path continuity, thermal spacing, connector orientation, silkscreen readability, and DFT access. Poor placement is repaired before route retries consume the full route budget.

#### Simulation policy defaults

SPICE validation is required for analog, power, timing-critical control, and protection circuits.

Default tolerance envelopes:

1. Rails: `±3%`
2. Analog setpoints: `±5%`
3. Timing windows: `±10%`
4. Protection trip thresholds: `±7%`

SPICE workflow requirements:

1. Extract simulation netlists from the KiCad schematic or generated design model.
2. Use KiCad/ngspice-compatible execution for baseline simulation.
3. Resolve manufacturer SPICE models from local cache, vendor libraries, or explicit user-provided model files.
4. Record model provenance and downgrade legally unobtainable required manufacturer models to warnings when an acceptable generic substitute is available.
5. Parse simulator outputs into structured measurements.
6. Compare measurements against declared envelopes and return `BLOCKED_SIMULATION` on failure.

SPICE model acquisition and caching policy:

1. Merlin never redistributes manufacturer SPICE models unless the model license explicitly permits redistribution.
2. Models behind manufacturer logins or click-through licenses are acquired by user-assisted download, authenticated browser/portal automation, or user-provided files.
3. Cached models are stored in a local, non-shared cache with license metadata, source URL, retrieval date, hash, manufacturer, MPN, and permitted-use notes.
4. Project artifacts reference cached models by hash/path but do not embed restricted model text into release packages unless allowed by license.
5. If a required manufacturer model cannot be legally acquired or cached, Merlin emits a simulation warning with the missing model list, acquisition notes, and a suggested generic substitute when available.
6. Generic substitute models may satisfy the simulation gate only when the selected profile permits generic equivalence or the user explicitly approves the downgrade from manufacturer-specific to generic simulation.
7. If no legal manufacturer model or acceptable generic substitute is available for a simulation-required scenario, the workflow returns `BLOCKED_SIMULATION`.

3D model sourcing policy:

1. Prefer KiCad standard-library STEP models when the selected footprint already references a valid model.
2. Use vendor/manufacturer STEP models when available under terms that permit local project use.
3. Generate simple package-envelope STEP models from verified package dimensions when no accurate manufacturer model exists and mechanical clearance checking only needs an envelope.
4. Require user-supplied STEP models for connectors, enclosures, controls, or mechanically critical components when package-envelope generation is insufficient.
5. Omit STEP output for non-critical parts only when the final report lists omitted models and affected components.

#### Visual QA scope

Visual QA is a supplementary inspection layer. It can create repair tasks and block release on presentation/mechanical-readability issues, but it cannot override failed electrical, simulation, parity, or fabrication gates.

Required visual QA checks:

1. Silkscreen overlap with pads, vias, board edge, holes, or other silkscreen text.
2. RefDes presence, legibility, and agreement with schematic/BOM references.
3. Polarity and pin-1 markings for diodes, LEDs, ICs, electrolytic capacitors, connectors, and keyed parts.
4. Connector orientation and board-edge accessibility.
5. Front-panel/control labeling consistency with requirements.
6. Test point labeling and accessibility.
7. Mounting-hole, keepout, and enclosure-clearance visibility.
8. Component orientation anomalies compared with placement rules and common package conventions.
9. Layer/view sanity screenshots for top copper, bottom copper, silkscreen, soldermask, and 3D view when available.

#### Requirement-driven circuit methodology

Intent 2 requires a design-methodology stage before KiCad generation.

Required outputs before schematic synthesis:

1. Functional decomposition: power, controller, Ethernet, signal monitoring, protection, isolation, user interface, programming/debug.
2. Reference topology selection: known-good vendor reference designs, application notes, or approved internal patterns.
3. Component selection matrix: MCU/Ethernet option, IoT/component module, PHY or MAC+PHY module, magnetics, protection, regulator, I/O expansion, isolation, connectors.
4. Constraint capture: supply voltage, monitored signals, generator interface levels, environment, enclosure, EMC/safety assumptions.
5. Design rationale: selected topology, rejected alternatives, and safety assumptions.
6. Verification plan: ERC/DRC, simulation, net-class checks, Ethernet layout checks, and human sign-off requirements.

If no acceptable reference topology or component set can be justified, the workflow returns `BLOCKED_ENGINEERING_DECISION`.

#### Reference-design and source corpus policy

Requirement-driven designs use a curated source hierarchy:

1. Project-local approved reference designs and user-supplied examples.
2. xcalibre-server RAG sources for internal notes, manuals, prior projects, datasheets, and design rules.
3. Vendor application notes, reference designs, evaluation-board schematics, and layout guides from the configured vendor/source list.
4. KiCad official libraries and examples.
5. Distributor/manufacturer metadata from Digi-Key, Mouser, Arrow, Newark/Farnell/element14, LCSC, Parts Express, and future configured vendors.

Every requirement-driven schematic records source provenance for selected topologies, modules, components, and critical layout rules. Uncited LLM-only circuit invention is not sufficient for high-stakes or Ethernet/control designs.

#### User approval workflow

Recommendation: all electronics approvals use a single `ElectronicsApprovalRequest` surface backed by `AppSettings.propose(_:)`, so approvals are auditable and consistent with Merlin's existing settings-change model.

Approval request types:

1. `clarification` — resolves ambiguous extraction regions, nets, components, labels, or footprints.
2. `high_stakes_signoff` — approves release packaging for control, hazardous-energy, military, or mission-critical designs.
3. `profile_change` — approves layer-count, stackup, or fabricator-profile changes.
4. `substitution` — approves vendor/component substitutions.
5. `order_submission` — approves final vendor cart/order submission.
6. `library_generation` — approves generated symbols/footprints when the project policy requires manual review.

Each approval shows the proposed change, source evidence, affected nets/components/files, cost/safety impact when applicable, and available actions: approve, reject, request revision, or provide manual correction.

#### Router failure recovery

Routing failure is not terminal until placement and constraints have been analyzed.

Recovery sequence:

1. Inspect unrouted nets and congestion regions.
2. Reclassify or correct net classes if constraints are wrong.
3. Adjust placement of components involved in blocked routes.
4. Add or move vias, seed routes, or plane connections where allowed.
5. Propose constraint/profile changes only when electrically and manufacturably justified and require user approval for layer-count or fabrication-profile changes.
6. Re-run ERC/DRC/parity/connectivity after every repair.

If route iteration budget is reached, the blocked report includes percentage routed, failing nets, congestion regions, attempted repairs, and required human decisions.

#### Fabrication, assembly, and CAM checks

Fabrication sanity checks are profile-specific.

Required output set:

1. Gerbers
2. Excellon drills
3. drill map/report
4. BOM
5. pick-and-place/centroid file
6. assembly drawing
7. fabrication drawing/notes
8. STEP/3D output when models are available
9. verification report

CAM checks validate required files, layer naming for the target fabricator, board outline, drill units, empty layers, soldermask/paste presence, copper-to-edge clearance, and basic manufacturability constraints. Fabricator profiles define naming and acceptance requirements starting with JLCPCB, PCBWay, OSHPark, and custom board houses.

#### High-stakes boundary (mandatory human sign-off)

Human sign-off is mandatory when any of the following are true:

1. Engine/generator start-stop/shutdown control
2. Hazardous energy context (`>60VDC` or `>30VAC RMS`)
3. Expected current path above `5A`
4. Isolation, interlock, or protection function present
5. Military or mission-critical industrial usage

In high-stakes mode, auto-waivers for ERC/DRC/simulation failures are disallowed.

#### Distributor and BOM architecture requirements

Merlin must support all configured vendors with vendor-native BOM file handling.

Architecture requirements:

1. Canonical internal BOM model (`NormalizedBOM`)
2. Per-vendor native BOM adapters (import + export + column mapping)
3. Per-vendor part match/pricing/availability clients
4. Per-vendor quote/order-preparation/order-submission bridges
5. Fallback path for vendors without public APIs: authenticated portal automation

Initial vendor set includes Digi-Key, Mouser, Arrow, Newark/Farnell/element14, LCSC, and Parts Express, with the same adapter contract for additional distributors.

BOM property linkage:

1. KiCad fields map to canonical fields: RefDes, value, footprint, manufacturer, MPN, vendor SKUs, quantity, DNP, lifecycle, substitutions.
2. Vendor adapters export native BOM formats for import into each vendor portal.
3. Part matching never silently substitutes package, voltage/current rating, tolerance, temperature range, or lifecycle status.
4. Vendor pricing/availability is advisory until the user approves substitutions.
5. Order submission always requires explicit user approval, final vendor/cart review, and recorded order summary.

Vendor order safety recommendation:

1. Default workflow prepares carts/orders but does not submit until the user explicitly approves.
2. API credentials and portal tokens are stored in Keychain.
3. Order submission requires visible vendor, line items, quantities, unit prices, shipping, tax, total, payment method alias, and ship-to summary.
4. Configurable purchase limits block orders above a user-defined threshold.
5. Merlin records an order summary artifact but does not store full payment details.

#### Acceptance test matrix

v2.0 implementation is not complete until deterministic fixtures cover these cases:

1. KiCad version below 10 returns `BLOCKED_VERSION`.
2. Missing `merlin-kicad-mcp` or missing required tool returns `BLOCKED_TOOLING`.
3. Clean native KiCad schematic compiles to project artifacts and passes parity.
4. Low-resolution raster schematic returns `BLOCKED_INPUT_QUALITY`.
5. Ambiguous junction/net in raster extraction creates targeted clarification questions.
6. Missing footprint blocks PCB synthesis with `unknown_footprints > 0`.
7. Generated project-local symbol/footprint fails pin/pad verification and returns `BLOCKED_LIBRARY`.
8. Missing board profile selects `jlcpcb_2layer_default` and records it in the report.
9. Ethernet/control requirement prefers acceptable IoT/module option when it satisfies constraints.
10. Router leaves unrouted nets and prevents `COMPLETE` and fab export.
11. Router recovery changes placement/net classes automatically but requests approval for layer/profile changes.
12. ERC error blocks completion.
13. DRC error blocks completion.
14. Schematic/PCB parity mismatch blocks completion.
15. Legally unobtainable required SPICE model emits a warning and generic-model suggestion when an acceptable substitute is available.
16. Failed SPICE tolerance returns `BLOCKED_SIMULATION`.
17. Gerber/drill/PnP output missing required fabricator file blocks release.
18. Vendor BOM export uses selected vendor-native format.
19. Vendor substitution requires explicit approval.
20. Vendor order submission requires explicit cart/order approval and records summary.
21. High-stakes generator start/stop design cannot package release without human sign-off.
22. Multi-sheet schematic preserves hierarchical labels and sheet pins through extraction/parity.
23. BOM fields round-trip KiCad fields to `NormalizedBOM` and vendor mappings.
24. Visual QA flags silkscreen overlap/orientation issues but cannot override failed electrical gates.

#### Status contract

Terminal statuses:

1. `COMPLETE`
2. `BLOCKED`
3. `BLOCKED_INPUT_QUALITY`
4. `BLOCKED_VERSION`
5. `BLOCKED_SIMULATION`
6. `BLOCKED_TOOLING`
7. `BLOCKED_LIBRARY`
8. `BLOCKED_ENGINEERING_DECISION`
9. `IN_PROGRESS`

`COMPLETE` is legal only when all required gates pass.

---

## V5 — Supervisor-Worker Multi-LLM Architecture

Merlin currently targets software development but the supervisor-worker mechanisms are domain-agnostic — role slots, routing, critic, tracker, and planner operate on whatever the active domain provides. Cheap models execute bulk work; a thinking model plans and verifies.

**Current domain focus:** Software development — Swift/Xcode natively; any language or platform via SSH remote execution or language-specific MCP plugins.

### Role Slots

| Slot | Purpose | Default structural trigger |
|---|---|---|
| `orchestrate` | Decomposes tasks, writes step instructions | Multi-step agentic tasks, planning keywords |
| `reason` | Long CoT, math, deep analysis, verification | Thinking mode active, `@reason` declaration |
| `execute` | Tool calls, summaries, bulk execution | Tool result processing, routine completions |
| `vision` | Image / screenshot analysis | Image present in context |
| `memory` | Background memory generation | Internal only — no user override |

Each slot maps to a configured provider in `AppSettings`. A slot with no distinct assignment falls through according to runtime routing:

- `execute` → active provider
- `reason` → active provider
- `orchestrate` → `reason`, then active provider
- `vision` → active provider unless a dedicated vision-capable provider is assigned

### Routing Priority Stack

```
1. Declarative override  — @role in message, or skill frontmatter `role: <slot>`
2. Structural routing    — engine infers role from task shape (image → vision, etc.)
3. Active provider       — unresolved slot uses the runtime fallback above
```

**Declarative syntax:**

```
@reason explain this     → one-shot override, stripped before sending to model
@reason! explain this    → sticky for rest of session
```

Skill frontmatter:

```yaml
role: reason   # all invocations of this skill use the reason slot
```

### Critic Layer

After the agentic loop produces output, the critic runs in two stages before the result reaches the user.

**Stage 1 — Domain verification (deterministic, free)**

The active domain's `VerificationBackend` provides the verification commands for the current task type. The critic runs all of them via `ShellTool` before any model evaluation:

```
VerificationBackend.verificationCommands(for: taskType, config: domainConfig)
  → [VerificationCommand]   (nil if domain has no deterministic check for this task type)
      ↓
ShellTool executes each command
      ↓
Any failure → definitive critic fail → correction triggered (no remote model call consumed)
All pass    → proceed to Stage 2
```

For the software domain this means compile, test, and lint. For a PCB domain it would be DRC and ERC. For domains with no deterministic check (`NullVerificationBackend`), Stage 1 passes immediately and Stage 2 carries the full verification burden.

Tasks that produce no verifiable artifact (explanations, summaries) return `nil` from `verificationCommands` and skip Stage 1 entirely.

**Stage 2 — Model evaluation (reason slot)**

A silent eval pass runs using the `reason` slot. The prompt is a structured six-criterion checklist — not a generic "does this look right?" question:

```
1. Completeness       — does the output fully address what was asked?
2. Factual consistency — are architectural/technical claims consistent with the context provided?
3. Date accuracy       — if the output contains dates, are they correct?
4. Scope adherence     — no unrequested features added silently?
5. Internal consistency — no contradictions within the output itself?
6. Document integrity  — (document turns only) effort estimates present and honest?
```

The full output is passed to the reason slot — no truncation. When the turn involved `write_file` calls, the written file contents are read from disk and injected into the prompt so the critic can verify the document body directly rather than inferring it from the assistant text.

The verdict is parsed from the **last** PASS/FAIL line in the response, so reasoning models that emit a thinking preamble before their final answer (e.g. Qwen3) are handled correctly.

```
Critic fires when any of:
  classification.complexity == .highStakes
  classifierOverride != nil
  write_file was called during the turn    ← document verification path
```

- **Pass** → result shown to user
- **Fail** → correction injected as system message; worker re-runs (up to `max_critic_retries`)
- **Retries exhausted** → escalate to user or promote to stronger model

The inner loop (both stages) is collapsible in a "reasoning trace" block. The user sees the final output only.

**Two-tier document verification [v9.1]**

For document-generation turns (any turn that calls `write_file`), an optional second agentic verification pass is available via the `/verify-document` skill. This runs in a fork context on the reason slot with full tool access:

```
AgenticEngine critic (automatic, every document-write turn)
  → Stage 1: domain shell commands
  → Stage 2: structured Qwen3 checklist against full output + file contents
       ↓
/verify-document skill (on-demand, invoked by user or post-critic trigger)
  → fork context, reason slot, full tool access
  → greps source files to cross-reference architectural claims
  → produces structured report: VERIFIED / UNVERIFIABLE / CONTRADICTED per claim
```

The skill is at `~/.merlin/skills/verify-document/SKILL.md`. Invoke it with `/verify-document path/to/document.md` after any document generation turn that warrants deeper review.

**Critical constraint:** The reason slot must be assigned to a genuinely stronger model than the execute slot. A weak model cannot reliably catch its own class of errors. For local-only setups, Qwen3-27B (128K context, thinking mode) is the minimum viable reason slot for document verification.

**Graceful degradation when the reason slot is unavailable**

If the provider assigned to the `reason` slot is unreachable (no API key, provider down, network failure), the critic does not block:

```
Reason slot unavailable
  ↓
Stage 1 (execution verification) still runs — deterministic checks proceed regardless
  ↓
Stage 2 skipped — output marked "unverified" with a visible badge in the UI
  ↓
Output delivered to user with degraded-mode indicator
```

The user sees a persistent "reason slot offline — outputs unverified" banner until the slot becomes available again. No silent failure — the degraded state is always visible.

```swift
// AppSettings additions
var criticEnabled: Bool           // default true
var maxCriticRetries: Int         // default 2
var roleAssignments: [String: String]  // slot → providerID
var executionVerificationEnabled: Bool // default true
```

### Model Performance Tracker

Rather than assuming confidence from model metadata or relying on self-reported uncertainty, Merlin builds an empirical performance profile for each model from observed outcomes on the user's actual workload. After 30 samples, the profile drives routing decisions automatically.

#### Outcome Signals (auto-collected, no user action required)

| Signal | Source | Weight |
|---|---|---|
| Stage 1 verification passed / failed | `VerificationBackend` result via ShellTool | High |
| Diff accepted as-is | StagingBuffer accept action | High |
| Diff accepted with edits | Accept+Edit path | Medium |
| Diff rejected | StagingBuffer reject | High |
| Critic passed first attempt | CriticEngine result | Medium |
| Critic failed N times before passing | retry count | Medium |
| Follow-up correction detected | next message correction heuristic | Medium |
| Session completed vs abandoned | new session without completion | Low |

Signals are domain-agnostic — Stage 1 verification covers whatever the active domain's `VerificationBackend` checks (compile+test for software, DRC for PCB, etc.). No user action or tagging is required.

#### Data Model

`TaskType` is not a hardcoded enum — it comes from the active domain via `DomainRegistry`. The tracker records against `DomainTaskType` values, so it automatically handles any domain without code changes:

```swift
struct OutcomeSignals {
    var stage1Passed: Bool?          // nil if Stage 1 was skipped (NullVerificationBackend)
    var stage2Score: Double?         // reason-slot critic score 0.0–1.0; nil if critic was skipped
    var diffAccepted: Bool           // true = accepted as-is or with edits; false = rejected
    var diffEditedOnAccept: Bool     // true = user edited before accepting
    var criticRetryCount: Int        // number of critic feedback loops before pass
    var userCorrectedNextTurn: Bool  // heuristic: follow-up message is a correction
    var sessionCompleted: Bool       // false = new session started without task completion
    var addendumHash: String         // SHA256 of the provider's system_prompt_addendum at call time
}

struct OutcomeRecord: Codable {
    var modelID: String
    var taskType: DomainTaskType   // domain-registered — works for any domain
    var score: Double              // 0.0 (failure) – 1.0 (full success), weighted from signals above
    var addendumHash: String       // tracks which addendum variant produced this outcome
    var timestamp: Date
}

enum Trend: String, Codable {
    case improving
    case stable
    case declining
}

struct ModelPerformanceProfile: Codable {
    var modelID: String
    var taskType: DomainTaskType
    var successRate: Double        // rolling weighted average
    var sampleCount: Int
    var trend: Trend
    var lastUpdated: Date

    var isCalibrated: Bool { sampleCount >= 30 }
}
```

Profiles are persisted at `~/.merlin/performance/<model-id>.json`. Each model × domain × task-type combination maintains its own profile — a model's Swift performance does not affect its PCB schematic profile.

#### actor ModelPerformanceTracker

```swift
actor ModelPerformanceTracker {
    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async
    func successRate(for modelID: String, taskType: DomainTaskType) -> Double?  // nil if uncalibrated
    func profile(for modelID: String) -> [ModelPerformanceProfile]
    func allProfiles() -> [ModelPerformanceProfile]
}
```

`record()` is called by `AgenticEngine` at session end, after all outcome signals are available. It updates the rolling weighted average using an exponential decay window (recent outcomes weighted more than older ones).

`successRate()` returns `nil` until `sampleCount >= 30` — the minimum sample threshold for a calibrated score. Below this the model is treated conservatively (always run critic).

#### How the Score Drives Routing

The empirical success rate replaces static model tier assumptions as the primary confidence input:

```
Uncalibrated (< 30 samples)  → always run critic, show "learning…" in UI
score < 0.60                 → always run critic; flag for possible worker slot upgrade
score 0.60 – 0.85            → standard critic gating; use structural signals to refine
score > 0.85                 → skip critic for routine-tier tasks; run for standard+
```

Logprobs (when the provider exposes them) and structural signals (hedging phrases, repeated tool retries, empty results) remain active as real-time refinements within the `0.60–0.85` band — but they do not override a well-established low score. A model with a 55% success rate does not earn a critic skip because one response had high logprobs.

```toml
[routing]
confidence_skip_threshold    = 0.85
confidence_escalate_threshold = 0.60
logprobs_enabled             = true   # request logprobs if provider supports them
min_calibration_samples      = 30
```

#### Settings — Performance Dashboard

The Settings > Providers panel shows a per-model performance breakdown:

```
Mistral 7B Instruct (local)
  Code generation    ████████░░  74%  (52 tasks)
  Explanation        █████████░  89%  (31 tasks)
  Refactoring        ██████░░░░  61%  (18 tasks)
  ─────────────────────────────────
  Effective routing  standard    (empirical — 116 total tasks)
  Trend              ↑ improving

Llama 3.2 3B (local)
  Code generation    learning…   (12 / 30 tasks)
```

The "effective routing" label is derived from the profile, not manually set. The user can inspect it but the system manages it automatically.

#### Model-Specific Prompt Addenda

Local models respond differently to prompt format. Each provider can declare a `system_prompt_addendum` in `config.toml` — appended to the base system prompt for every call to that provider:

```toml
[providers.mistral-7b]
system_prompt_addendum = "Always produce complete code blocks. Do not truncate."

[providers.deepseek-coder]
system_prompt_addendum = "Think through each step before writing code."
```

Domain plugins contribute their own addendum via `DomainPlugin.systemPromptAddendum`. Both are appended in order: provider addendum first, then domain addendum.

**Tracker-informed addendum tuning:**

`ModelPerformanceTracker` records success rate per model × task-type × addendum hash. When the user changes a provider's addendum, the tracker starts a new profile for that variant and compares performance once calibrated (≥ 30 samples each). The dashboard surfaces the comparison:

```
Mistral 7B Instruct — Code generation
  Addendum v1 (current)   ████████░░  78%  (34 tasks)
  Addendum v2 (previous)  █████░░░░░  54%  (18 tasks)
  ✓ Current addendum is performing better
```

The user always controls the addendum via `config.toml`. The tracker advises; it does not auto-switch.

#### Connection to V6 LoRA Corpus

The performance tracker is the quality filter for the V6 LoRA training pipeline. Sessions with a high outcome score on a given task type are the best training candidates — the `LoRATrainingEngine` (V6) pulls high-scoring sessions directly from the tracker rather than proposing everything to the review queue. Low-scoring sessions are never proposed as training data regardless of other signals. The tracker data structure requires no changes in V6 — it already records everything LoRA needs.

### Planner Layer

**Classification (execute slot)**

Before the planner engages, the execute slot makes a lightweight classification call — a single structured completion that returns a JSON object:

```json
{ "needs_planning": true, "complexity": "standard", "reason": "multi-file refactor" }
```

If `needs_planning` is false, the execute slot handles the task directly and the planner is bypassed entirely. If true, the orchestrate slot takes over for decomposition. This handoff is the only time the execute slot fires before the orchestrate slot in a planned task.

**Planned task loop:**

```
1. Orchestrate slot — decomposes task → steps + per-step success criteria + complexity tag
2. Critic evaluates the PLAN before any execution begins         ← plan evaluation
3. Execute slot     — executes each step
4. Critic evaluates each step OUTPUT (Stage 1 + Stage 2)
5. Loop until all steps pass or retry limit hit
```

**Plan evaluation (step 2)**

Before execution begins, the critic reviews the plan itself:

```
Plan critic prompt: "Given task X, does this plan correctly decompose it into steps
                    that will achieve the goal? Are any steps missing, wrong, or in
                    the wrong order? If so, what specifically needs to change?"
```

- **Pass** → execution proceeds
- **Fail** → corrected plan injected back to orchestrate slot for revision (up to `max_plan_retries`)
- **Retries exhausted** → escalate to user with plan summary

This catches a class of errors that step-level evaluation cannot: a bad decomposition produces steps that each pass individually but fail collectively at the task level. Plan evaluation is always a Stage 2 (model) check — there is no execution artifact to verify at planning time.

```swift
// AppSettings additions
var maxPlanRetries: Int      // default 2 — plan revision loops before escalating to user
var maxLoopIterations: Int   // default 10 — hard ceiling on planner step-execution loop
```

### Task Complexity Routing

The planner classifier tags each task with a complexity tier, which determines slot assignment for that task regardless of global defaults. This allows high-stakes work to automatically use stronger models without the user having to declare it manually.

**Complexity tiers:**

Tiers are domain-agnostic. Examples vary by active domain:

| Tier | Software example | PCB example | Construction example | Worker slot | Critic slot |
|---|---|---|---|---|---|
| `routine` | Summarise, rename, explain | Component search, netlist export | Material list, room label | local execute | skip |
| `standard` | Refactor, write tests, implement feature | Schematic design, footprint assignment | Floor plan, wiring diagram | local execute | reason |
| `high-stakes` | Schema migration, auth, security logic | Power routing, impedance matching, DRC | Load-bearing walls, electrical, plumbing vs. code | reason | reason |

The execute-slot classifier produces a tier label alongside its plan/bypass decision. High-stakes keyword lists are domain-provided via `DomainPlugin.highStakesKeywords` — not hardcoded. Tier assignment can be overridden declaratively:

```
#high-stakes migrate the users table to add TOTP columns
```

The `#` prefix distinguishes tier overrides from slot overrides (`@reason`, `@execute`). Skill frontmatter uses a separate key:

```yaml
complexity: high-stakes   # always routes this skill to the stronger worker slot
```

**Why this matters for cost:** Routine tasks (the majority) never touch remote models at all. Standard tasks pay for one remote critic pass. Only high-stakes tasks pay for full remote execution. In practice this means most sessions are local-only, with targeted remote calls for the work that most benefits from them.

### Implementation Order

1. `DomainRegistry` + `DomainPlugin` protocol + `MCPDomainAdapter` + `SoftwareDomain` built-in
2. `VerificationBackend` protocol + `SoftwareVerificationBackend` + `NullVerificationBackend`
3. Settings UI — role-to-provider assignment panel + active domain selector + degraded-mode indicator
4. Structural routing in `AgenticEngine`
5. `ModelPerformanceTracker` — `DomainTaskType`-keyed profiles, outcome signal collection, addendum tracking, dashboard UI
6. Critic Stage 1 — domain verification via `VerificationBackend`
7. Critic Stage 2 — reason slot, performance-score-gated, graceful degradation
8. Per-provider `system_prompt_addendum` config + domain addendum appending
9. `@role` and `#tier` declaration parsing in `ChatView`
10. Planner layer (execute-slot classifier → orchestrate handoff) + plan evaluation + complexity tier routing
11. Skill frontmatter `role:` and `complexity:` declarations

| Decision | v5 |
|---|---|
| Domain extensibility | New domains added as MCP servers implementing `DomainPlugin` — no core changes |
| Task types | `DomainTaskType` registered by domain — no hardcoded enum |
| Stage 1 verification | `VerificationBackend` protocol — domain-provided commands, runs via ShellTool |
| Remote execution | `verify_command` is any shell string including SSH — domain decides |
| Default domain | `SoftwareDomain` — always registered, cannot be removed |
| Routing default | Structural routing; declarative `@role` slot overrides |
| Tier override syntax | `#high-stakes` prefix — distinct from `@role` slot overrides |
| Critic constraint | Reason slot must be stronger than execute slot — settings UI warning enforced |
| Critic Stage 1 | Domain verification — deterministic, free, no remote cost |
| Critic Stage 2 | Model evaluation via reason slot — only runs after Stage 1 passes |
| Critic timing | Synchronous — safer, simpler to start; async option deferred |
| Correction injection | System message (invisible to user, visible to model) |
| Inner loop UI | Collapsible reasoning trace block, same as tool calls |
| Reason slot unavailable | Stage 1 still runs; Stage 2 skipped; output marked "unverified"; banner shown |
| Confidence source | Empirical success rate from `ModelPerformanceTracker` — not self-reported |
| Calibration threshold | 30 samples per model × domain × task-type before score is trusted |
| Uncalibrated path | Always run critic; show "learning…" in dashboard |
| High-score path (>0.85) | Critic Stage 2 skipped for routine tasks — local only, zero remote cost |
| Low-score path (<0.60) | Always run critic; flag for possible execute slot upgrade |
| Logprobs / structural signals | Active as real-time refinements within 0.60–0.85 band only |
| Self-assessment | Removed — replaced by empirical profile |
| Prompt addenda | Per-provider `system_prompt_addendum` in config.toml; tracker compares addendum versions (≥30 samples each) |
| Plan evaluation | Critic reviews plan before execution; bad plan corrected before any step runs |
| Complexity tiers | `routine` / `standard` / `high-stakes` — classifier assigns, user can override |
| High-stakes keywords | Domain-provided via `DomainPlugin.highStakesKeywords` — not hardcoded |
| Planner bypass | Execute-slot classifier gates the planner — simple queries skip it |
| LoRA corpus quality | V6 — tracker already collects the data; LoRATrainingEngine reads it without tracker changes |
| LoRA training scope | V6 — execute-slot outputs only; reason-slot outputs excluded |
| Skill declarations | `role:` and `complexity:` frontmatter keys in SKILL.md |

---

## V5 — Legacy RAG Memory Extension

> **xcalibre-server Phase 18 is shipped** — migration `0028_memory_chunks.sql`, `POST /api/v1/memory`, `DELETE /api/v1/memory/:id`, and unified `GET /api/v1/search/chunks?source=all` are all live. Merlin-side implementation can proceed.

This was the original Merlin memory design: xcalibre-server acted as the persistent memory store for Merlin. v9 supersedes it with a local SQLite backend, but the historical flow remains documented here for reference. Local LLMs have limited context windows; precision-retrieved prior memory lets a 4k context window punch above its weight.

### Memory Types

| Type | Content | Write trigger | Granularity |
|---|---|---|---|
| Episodic | Session summary — what was worked on, decisions made, outcome | Session end / `MemoryEngine` idle fire | One chunk per session |
| Factual | Discrete extracted facts — "user prefers X", "project uses Y" | Post-session background pass | One chunk per fact |

Excluded from legacy xcalibre memory: recent turns (stay in-context as sliding window), procedural/how-to (already in book content), tool outputs and file contents (too large, too ephemeral).

### Unified Retrieval

At query time, memory and book content are retrieved in parallel and merged:

```
User message
  ├── xcalibre books  → relevant documentation / knowledge chunks
  └── xcalibre memory → relevant episodic summaries + factual chunks
        ↓ merged + reranked by RRF (xcalibre-server side)
        ↓ injected as context prefix
LLM sees: [memory] + [book knowledge] + [recent turns] + [user message]
```

Memory chunks were scoped to `project_path` — a session in project A did not bleed into project B.

### XcalibreClient Changes

```swift
extension XcalibreClient {
    func writeMemoryChunk(
        text: String,
        chunkType: MemoryChunkType,   // .episodic | .factual
        sessionID: String,
        projectPath: String,
        tags: [String] = []
    ) async throws -> String          // returns TEXT UUID chunk ID

    func deleteMemoryChunk(id: String) async throws
}
```

### MemoryEngine

`MemoryEngine` is a background actor that fires on session idle or explicit session end:

```swift
actor MemoryEngine {
    func onSessionEnd(context: [ConversationTurn], projectPath: String) async
    func onIdle(context: [ConversationTurn], projectPath: String) async
}
```

**Episodic write (session end / idle):**
1. Execute slot summarises recent turns into a single episodic chunk (≤400 words)
2. `XcalibreClient.writeMemoryChunk(chunkType: .episodic, …)`

**Fact extraction (background, post-session):**
1. Execute slot extracts discrete facts from the session as a list
2. Each fact written as a separate `.factual` chunk

### RAGTools Integration

`RAGTools.buildEnrichedMessage` already injects retrieved chunks as a context prefix. The only change is passing `source=all` and optionally `project_path` to the existing `searchChunks` call — no restructuring of the injection or ranking logic.

### Token Budget

Memory injection is bounded by a configurable token budget in `AppSettings`:

```toml
[memory]
enabled = true
max_memory_tokens = 1000   # total budget for injected memory chunks
```

Chunks are ranked by RRF score; lowest-scoring chunks are dropped first when the budget is exceeded.

### AppSettings additions (v5 memory)

```toml
[memory]
enabled = true
max_memory_tokens = 1000
idle_fire_minutes = 15      # how long idle before episodic write fires
fact_extraction = true      # async fact extraction post-session
```

| Decision | v5 memory |
|---|---|
| Memory store | xcalibre-server `memory_chunks` table (new in xcalibre Phase 18) |
| Retrieval | Unified — xcalibre `GET /api/v1/search/chunks?source=all` with RRF merge |
| Episodic write trigger | Session end OR `MemoryEngine` idle fire |
| Fact extraction | Execute slot, async background, post-session |
| Project scoping | `project_path` filter on all memory reads and writes |
| Token budget | `max_memory_tokens` — lowest-ranked chunks dropped first |

---

## V6 — LoRA Self-Training Pipeline

> **V6 — not in V5 scope.** Requires Unsloth integration exploration and LM Studio adapter loading investigation before phase files can be written. The `ModelPerformanceTracker` (V5) already collects the training corpus as a byproduct — no tracker changes needed in V6.

Complements RAG memory with weight-level adaptation. RAG handles explicit, retrievable facts; LoRA bakes behavioral patterns, style preferences, and domain vocabulary into the model itself. The user reviews and approves all training data before any fine-tuning occurs.

### Mental Model

| Layer | Captures | Mechanism |
|---|---|---|
| RAG memory | Explicit facts, episodic history | Retrieval at inference time |
| LoRA adapter | Behavioral patterns, style, domain vocabulary | Weight delta baked into model |

Both layers are active simultaneously. RAG answers "what happened in that session"; LoRA answers "how should I respond given this user's preferences."

### Training Signal Types

Two formats, automatically collected from normal use:

**SFT pair** (Supervised Fine-Tuning) — user accepts a response without correction:
```json
{
  "instruction": "Refactor AuthGate to use async/await",
  "response": "…model output…"
}
```

**DPO pair** (Direct Preference Optimization) — user corrects or declines a response:
```json
{
  "prompt": "Refactor AuthGate to use async/await",
  "chosen": "…user-corrected version…",
  "rejected": "…original model output…"
}
```

DPO pairs are higher-value: they explicitly encode what to avoid, not just what to do. The existing correction flow (user edits a model response) is the natural source — Merlin proposes the original + corrected form as a DPO pair automatically.

### Review Queue

Follows the same UX pattern as `~/.merlin/memories/pending/` — AI-generated items wait for explicit user approval before entering the training corpus.

Each item in the queue shows:

```
Task:     "Refactor AuthGate to use async/await"
Response: [first 200 chars of model output…]
Type:     SFT pair
Signals:  ✓ session completed  ✓ no tool errors  ✓ no follow-up correction

[Accept]  [Accept + Edit]  [Decline]
```

- **Accept** — adds as-is to corpus
- **Accept + Edit** — user trims or corrects the response before committing; edited version is what trains on. Produces a DPO pair if the edit is substantial.
- **Decline** — discarded; optionally prompts "provide a correction?" to convert to a DPO pair

**Queue stored at:** `~/.merlin/lora/pending/<uuid>.json`
**Accepted corpus:** `~/.merlin/lora/corpus/<model-id>/`

### Auto-Filtering (what gets proposed)

Not every response generates a queue item. Merlin scores sessions post-completion:

**Auto-reject (never proposed):**
- Session aborted by user
- One or more tool errors occurred
- Response was immediately followed by a correction request

**Always propose:**
- Correction pairs — highest-signal regardless of session length
- Explicit user upvote action

**Propose if high-signal:**
- Long successful session (high effort, no corrections)
- Repeated task pattern — one clean generalised example per pattern type

In normal use this yields ~10–20 proposed items per week — reviewable in a few minutes.

### Training Trigger

Training is always user-initiated, never automatic.

```toml
[lora]
enabled = true
min_examples_to_prompt = 50   # notify user when accepted corpus reaches this size
adapter_per_model = true      # separate adapter per base model checkpoint
training_backend = "unsloth"  # "unsloth" | "axolotl" (future)
```

When the corpus crosses `min_examples_to_prompt`, Merlin surfaces a notification:

```
50 training examples ready. Train now?   [Train]  [Later]
```

Training runs as a background shell process via `ShellTool`. A progress indicator appears in the toolbar. On completion, the new adapter is registered and loads on the next model initialisation.

### Adapter Management

Each base model checkpoint gets its own adapter. The corpus (text pairs) is model-agnostic and reusable, but training must be re-run when the user switches base models.

```
~/.merlin/lora/
  pending/                        — proposed items awaiting review
  corpus/
    <model-id>/                   — accepted training pairs for this model
      sft/
        <uuid>.json
      dpo/
        <uuid>.json
  adapters/
    <model-id>/
      adapter_config.json
      adapter_model.safetensors
      training_log.txt
```

`model-id` is derived from the model's file hash or LM Studio model identifier — not the display name, which can change.

### LoRATrainingEngine

```swift
actor LoRATrainingEngine {
    func proposeItem(_ item: TrainingItem) async
    func acceptItem(id: UUID, editedResponse: String?) async
    func declineItem(id: UUID, correction: String?) async
    func pendingCount(for modelID: String) -> Int
    func trainAdapter(for modelID: String, progressHandler: @escaping (Double) -> Void) async throws -> URL
    func loadAdapter(at url: URL, for modelID: String) async throws
}
```

`proposeItem` is called by `MemoryEngine` at session end after quality scoring. `trainAdapter` shells out to Unsloth, streams progress, returns the adapter path on success.

### AppSettings additions (v6 LoRA)

```toml
[lora]
enabled = false                 # opt-in — off by default
min_examples_to_prompt = 50
adapter_per_model = true
training_backend = "unsloth"
max_sft_examples = 500         # cap corpus size; oldest examples rotate out
max_dpo_examples = 200
```

### Implementation Order

1. `TrainingItem` model + `~/.merlin/lora/` directory layout
2. `LoRATrainingEngine` actor — propose, accept, decline
3. Auto-filtering quality scorer (post-session)
4. Review queue UI — pending list with Accept / Accept+Edit / Decline actions
5. Training trigger notification + progress indicator
6. Unsloth shell integration (`trainAdapter`)
7. Adapter registration + LM Studio hot-swap

| Decision | v6 LoRA |
|---|---|
| User control | All training data reviewed before corpus entry — no automatic ingestion |
| Training trigger | User-initiated only; notification when corpus threshold reached |
| Training formats | SFT (accept) and DPO (decline + correction) — both collected from day one |
| Adapter scope | One adapter per base model checkpoint; corpus is model-agnostic |
| Training backend | Unsloth via ShellTool (MPS on Apple Silicon; CUDA on NVIDIA) |
| Queue UX pattern | Same as `memories/pending/` — generated by AI, reviewed by user |

---

## V1.5 — Session History & Archive

### Motivation

Live sessions in Merlin are ephemeral: closing a session discards it. `SessionStore` already persists each session's messages to disk after every turn, but those records are never surfaced back to the user. V1.5 makes the full session history visible in the sidebar, adds an archive/recall workflow, and scopes session storage per project.

### Goals

- Show all past sessions for the current project in the sidebar, not just live ones
- Let users archive sessions they're done with (hide without deleting)
- Let users recall an archived session back to active status
- Persist session records scoped per project, not in a shared global directory

### Data Model Changes

**`Session` struct** — one new field:

```swift
struct Session: Codable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var providerDefault: String
    var messages: [Message]
    var authPatternsUsed: [String]
    var archived: Bool = false        // NEW — default false; backward-compatible via Codable
}
```

**`SessionStore` — project-scoped path**

Previously all sessions were written to a single flat directory:

```
~/Library/Application Support/Merlin/sessions/<uuid>.json
```

V1.5 scopes storage per project using the `ProjectRef.id` hash:

```
~/Library/Application Support/Merlin/sessions/<project-id>/<uuid>.json
```

`SessionStore` is initialised with the project path; it derives the scoped subdirectory automatically. Migration: on first launch after upgrade, existing sessions in the flat directory are moved to a `__legacy__/` subdirectory — not deleted, not automatically assigned to a project.

**New `SessionStore` methods:**

```swift
func archive(_ id: UUID) throws          // sets archived = true, saves to disk
func unarchive(_ id: UUID) throws        // sets archived = false, saves to disk
var activeSessions: [Session]            // sessions where archived == false, sorted by updatedAt desc
var archivedSessions: [Session]          // sessions where archived == true, sorted by updatedAt desc
```

### Session Manager Changes

`SessionManager` gains a `restore(session:)` path for loading a past session back into an active `LiveSession`:

```swift
@discardableResult
func restore(session: Session) async -> LiveSession
```

Behaviour:
1. Create a new `LiveSession` for the project.
2. Inject `session.messages` into the live session's `ContextManager`.
3. Call `compactIfNeededBeforeRun(isContinuation: false)` — if the restored history exceeds 10 000 estimated tokens, auto-compact before the user's next prompt.
4. Set `liveSession.title` to the restored session's title.
5. Set `activeSessionID` to the new live session's id.
6. The restored `Session` record on disk is left unchanged (its id is not reused — the live session gets a new UUID so history is never overwritten by the resumed conversation until the user sends a new message, at which point a new session record is created).

The prior session transcript is shown in the chat view as read-only history — visually identical to a normal conversation. No "prior context" greying is applied in V1.5; that is a V1.6 polish item.

### Sidebar Changes

`SessionSidebar` gains two sections:

```
┌─────────────────────────┐
│ ● xcalibre-server       │
├─────────────────────────┤
│ Sessions                │
│  ▸ Refactor parser   2h │  ← active LiveSession (existing)
│  ▸ Fix OPDS feed     4h │
│  ▸ New Session          │  ← placeholder if title not yet set
├─────────────────────────┤
│ Prior Sessions          │
│  ▸ Add CHM support   3d │  ← disk-only Session (not live)
│  ▸ Stage 6 cleanup   1w │
│    Show archived…       │  ← collapsed by default
├─────────────────────────┤
│ + New Session           │
└─────────────────────────┘
```

**"Prior Sessions"** lists disk sessions that are not currently live (`activeSessions` minus any whose `id` matches a live session). Clicking one calls `sessionManager.restore(session:)`.

**Context menu on a prior session row:**
- **Resume** — same as clicking (calls `restore`)
- **Archive** — calls `sessionStore.archive(_:)`, moves row to archived section
- **Delete** — destructive, calls `sessionStore.delete(_:)` after confirmation

**Context menu on an archived session row (shown when "Show archived" is expanded):**
- **Recall** — calls `sessionStore.unarchive(_:)`, moves row back to prior sessions
- **Delete** — destructive, same as above

**Timestamps** — both sections show relative timestamps (`2h`, `3d`, `1w`) based on `session.updatedAt`. Live sessions show a purple activity dot when running (existing behaviour).

### File Layout

No new files. Changes are confined to:

| File | Change |
|---|---|
| `Sessions/Session.swift` | Add `archived: Bool = false` |
| `Sessions/SessionStore.swift` | Project-scoped path, `archive()`, `unarchive()`, `activeSessions`, `archivedSessions`, migration |
| `Sessions/SessionManager.swift` | Add `restore(session:)` |
| `Views/SessionSidebar.swift` | Prior Sessions section, archived section, timestamps, context menus |
| `App/AppState.swift` | Pass project path to `SessionStore` init |
| `Sessions/LiveSession.swift` | Accept optional initial messages for restore path |

### AppSettings Additions (v1.5)

None — no new user-configurable settings. Archive/recall is purely structural.

### Implementation Order

| Phase | Description |
|---|---|
| 181a/b | `Session.archived` field + `SessionStore` project-scoped path + `archive`/`unarchive`/`activeSessions`/`archivedSessions` |
| 182a/b | `SessionManager.restore(session:)` + message injection into `ContextManager` |
| 183a/b | `SessionSidebar` Prior Sessions section + archived section + timestamps + context menus |
| 184 | Supporting changes: `RelativeTimestampFormatter`, `ContextManager.load(_:)`, version bump to 1.5.0 |

---

## V1.6 — Multi-Project Workspace

### Motivation

V1.5 added session history per project, but each project still lived in its own window. V1.6 collapses all open projects into a single workspace window, matching Codex's UX: a left sidebar lists all open projects, sessions stack under each project header, and a single content area shows the active session.

### Goals

- Multiple projects visible simultaneously in one sidebar, each with their sessions listed below
- Clicking a project's name label opens a popover with a "New Session" option (and "Close Project")
- The bottom button replaced with "+ New Project Workspace" — opens the project picker as a sheet and adds the selected project to the sidebar
- ⌘N opens the project picker sheet (same as clicking "+ New Project Workspace")
- Sessions across all open projects share one content area; clicking any session makes it active
- Single-window only — `WindowGroup(for: ProjectRef.self)` removed; one `WindowGroup("Merlin", id: "workspace")` contains everything
- Open projects and active session persisted to `~/.merlin/workspace.json` — workspace is fully restored on relaunch
- Terminal and SideChat panes follow the active project's working directory

### WorkspaceCoordinator

A new `WorkspaceCoordinator` replaces the single `SessionManager` in `WorkspaceView`. It owns the list of open project managers, tracks the globally active session, and persists workspace state:

```swift
@MainActor
final class WorkspaceCoordinator: ObservableObject {
    @Published private(set) var projectManagers: [SessionManager]
    @Published private(set) var activeSession: LiveSession?
    @Published var showingProjectPicker: Bool = false

    // Designated init — workspaceURL is testable (tests point at a tmp file)
    init(workspaceURL: URL)
    convenience init()   // uses ~/.merlin/workspace.json

    func addProject(_ ref: ProjectRef) async    // no-op if already open; persists
    func removeProject(_ ref: ProjectRef)       // drops SessionManager; updates activeSession; persists
    func setActiveSession(_ session: LiveSession)

    // Derived — finds the SessionManager that owns coordinator.activeSession
    var activeProjectManager: SessionManager? { get }
}
```

On `init`, persisted project refs are loaded from `workspaceURL` and their `SessionManager` instances reconstructed. Live sessions are not automatically resumed — users see Prior Sessions in the sidebar and can resume selectively. If no projects are persisted (first launch or empty workspace), `showingProjectPicker` is set to `true` automatically.

`WorkspaceCoordinator` is exposed as a `@FocusedObject` so `MerlinCommands` can drive `showingProjectPicker = true` from ⌘N.

### Workspace persistence

`~/.merlin/workspace.json` stores the ordered list of open `ProjectRef` values:

```json
[
  { "path": "/Users/jon/Documents/localProject/xcalibre-server", "displayName": "xcalibre-server" },
  { "path": "/Users/jon/Documents/localProject/merlin", "displayName": "merlin" }
]
```

`persistOpenProjects()` is called after every `addProject` / `removeProject`. `loadPersistedProjects(from:)` is called in `init` — it reads the file, creates a `SessionManager` per ref, and calls `coordinator.addProject` for each.

### Single-window enforcement

`MerlinApp.swift` uses a single entry point:

```swift
WindowGroup("Merlin", id: "workspace") {
    WorkspaceView()
}
```

The previous `WindowGroup(for: ProjectRef.self)` (per-project windows) and `WindowGroup("Merlin", id: "picker")` (standalone picker) are removed. `AppDelegate` handles `applicationShouldHandleReopen` to bring the workspace window to front when the Dock icon is clicked.

### WorkspaceView

`WorkspaceView` owns `@StateObject private var coordinator = WorkspaceCoordinator()` (no-args convenience init). The content area renders `coordinator.activeSession` or a placeholder. All panes receive `coordinator.activeProjectManager?.projectRef.path ?? ""` for the active project:

```
WorkspaceView
  ├── coordinator: WorkspaceCoordinator
  ├── SessionSidebar()                        (environmentObject: coordinator)
  │   └── SlotStatusPanel()                   (v2.3; explicit slot assignments only)
  ├── ContentView()                           (focusedObject: coordinator)
  ├── TerminalPane(workingDirectory: coordinator.activeProjectManager?.projectRef.path ?? "")
  ├── SideChatPane(isVisible:, projectPath: coordinator.activeProjectManager?.projectRef.path ?? "")
  └── .sheet(isPresented: $coordinator.showingProjectPicker) {
          ProjectPickerView(onSelect: { ref in Task { await coordinator.addProject(ref) } })
      }
```

### Sidebar layout

```
┌──────────────────────────────┐
│ ● xcalibre-server      [···] │  ← tappable label → popover
│                              │
│  Sessions                    │
│   ▸ Refactor parser    2h    │
│   ▸ New Session              │
│                              │
│  Prior Sessions              │
│   ▸ Add CHM support    3d    │
│   ▸ Stage 6 cleanup    1w    │
│   Show archived…             │
├──────────────────────────────┤
│  Slots                       │  ← v2.3 collapsed routing summary
│   Execute      DeepSeek V4…  │
│   Reason       Not configured│
│   Orchestrate  Not configured│
│   Vision       Not configured│
├──────────────────────────────┤
│ ● merlin               [···] │  ← second project
│                              │
│  Sessions                    │
│   ▸ Fix circuit breaker 19h  │
├──────────────────────────────┤
│ + New Project Workspace      │  ← replaced bottom button
└──────────────────────────────┘
```

**Project header popover** (shown when project label is tapped):
```
┌──────────────────┐
│ ＋ New Session   │
│ ✕ Close Project  │
└──────────────────┘
```

### SideChatPane changes

`SideChatPane` gains a `projectPath: String` parameter. It constructs its own `AppState(projectPath: projectPath)` and `SkillsRegistry(projectPath: projectPath)` so it operates in the active project's context rather than an empty root.

### Session auto-titling

After the first turn completes, the engine generates a title from the first 50 characters of the first user message and fires a callback if the session still holds the default "New Session" title. This matches Claude app and Codex behaviour.

`AgenticEngine`:

```swift
var onTitleUpdate: ((String) -> Void)?

func applyTitleUpdateIfNeeded(to session: inout Session) {
    guard session.title == "New Session" || session.title.isEmpty else { return }
    let generated = Session.generateTitle(from: session.messages)
    guard generated != "New Session" else { return }
    session.title = generated
    onTitleUpdate?(generated)
}
```

Called inside the save block after every turn. `LiveSession` wires `onTitleUpdate` to update `self.title` on the main actor, which triggers an immediate sidebar refresh via `@Published`.

### RelativeTimestampFormatter

A pure stateless helper used by the sidebar to display session ages:

```swift
enum RelativeTimestampFormatter {
    static func string(from date: Date, now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        switch interval {
        case ..<60:     return "now"
        case ..<3600:   return "\(Int(interval / 60))m"
        case ..<86400:  return "\(Int(interval / 3600))h"
        case ..<604800: return "\(Int(interval / 86400))d"
        default:        return "\(Int(interval / 604800))w"
        }
    }
}
```

### ProjectPickerView changes

`ProjectPickerView` gains an optional `onSelect: ((ProjectRef) -> Void)?` parameter. When provided (sheet mode), selecting a project calls `onSelect` instead of `openWindow`. The standalone window mode (no `onSelect`) is removed — the picker is always presented as a sheet from `WorkspaceView`.

### MerlinCommands changes

`@FocusedObject var sessionManager: SessionManager?` is replaced with `@FocusedObject var coordinator: WorkspaceCoordinator?`. The "New Session" `CommandGroup` becomes:

```swift
CommandGroup(replacing: .newItem) {
    Button("New Project Workspace") {
        coordinator?.showingProjectPicker = true
    }
    .keyboardShortcut("n", modifiers: .command)
    .disabled(coordinator == nil)
}
```

### File Layout

| File | Change |
|---|---|
| `Sessions/WorkspaceCoordinator.swift` | New — multi-project state manager, workspace persistence |
| `App/MerlinApp.swift` | Single `WindowGroup("Merlin", id: "workspace")`; removed per-project and picker windows |
| `Views/WorkspaceView.swift` | Replace `SessionManager` with `WorkspaceCoordinator`; no-args init; picker sheet; active-project pane wiring |
| `Views/SessionSidebar.swift` | Rewrite — iterate `coordinator.projectManagers`; project header popover; replace bottom button |
| `Views/SideChatPane.swift` | Add `projectPath: String` parameter; own AppState scoped to active project |
| `Views/ProjectPickerView.swift` | `onSelect: ((ProjectRef) -> Void)?` parameter; sheet-mode only |
| `App/MerlinCommands.swift` | `@FocusedObject WorkspaceCoordinator`; ⌘N → picker sheet |
| `Support/RelativeTimestampFormatter.swift` | New — pure relative-date helper |
| `Engine/AgenticEngine.swift` | `onTitleUpdate` callback + `applyTitleUpdateIfNeeded` |
| `Sessions/LiveSession.swift` | Wire `onTitleUpdate` → `self.title` on main actor |
| `TestHelpers/EngineFactory.swift` | `make(sessionStore:)` overload |

### Implementation Order (completed)

| Phase | Description |
|---|---|
| 185a/b | `WorkspaceCoordinator` — multi-project state, persistence, `activeProjectManager`, testable init |
| 186b | `WorkspaceView`, `SessionSidebar`, `SideChatPane`, `MerlinCommands`, `MerlinApp` — single-window, coordinator-driven UI, picker sheet, pane wiring |
| 186b addendum | `ChatView` `@FocusedObject SessionManager?`; `WorkspaceView` exposes `activeProjectManager` as `.focusedObject()` — crash fix for v1.6.0 |
| 187a/b | Session auto-titling — `AgenticEngine.onTitleUpdate`, `applyTitleUpdateIfNeeded`, `LiveSession` wiring |
| 188 | Version bump to 1.6.0 (build 5), DMG `dist/Merlin-2026-05-08-v1.6.0.dmg` |
| 189 | Crash fix: `ChatView` `EnvironmentObject.error()` — version bump to 1.6.1 (build 6), DMG `dist/Merlin-2026-05-08-v1.6.1.dmg` |

---

## V2.1 — Budget-Aware Execution

### Motivation

Merlin v2.0 has a working agentic loop, but it treats LLM context as an unbounded resource and
recovers from overflow reactively. Two failure modes resulted in practice:

1. **Recursive recovery loops.** When a provider returned a context-overrun 400, the engine
   compacted and called `runLoop` again from inside the catch block. If the compacted context
   still overflowed, the recursive call could repeat indefinitely. The retry counter
   (`contextLengthRetryCount`) was supposed to bound this but did not in all observed cases.
2. **Provider-coupled behaviour.** The engine assumed the active provider's context window
   without enforcing it. A 65 K-input DeepSeek request and a 32 K-input local-model request
   went through the same code path with no per-provider sizing.

V2.1 reframes execution as **budget-aware by construction**. Every LLM call honours an
explicit per-provider budget; overflows are decomposed into smaller substeps; cross-provider
escalation is the last-resort fallback. The recursive recovery path is deleted. The infinite-
loop bug class becomes structurally impossible.

The design principle: **prevention by construction, bounded recovery, never recurse.**

### Architecture overview

```
User message
  │
  ▼
RAG retrieval ──► RAGSelector (budget-derived chunk count)
  │
  ▼
PlannerEngine.classify ──► [optional] PlannerEngine.decompose → [PlanStep]
  │
  ▼
For each PlanStep:
  │
  ▼
WorkingSetBudget.derive(from: ProviderBudget) ──► ContextManager.applyWorkingSetCaps(...)
  │
  ▼
TokenEstimator.estimate(request) ──► preflightCheck(...)
  │                                       │
  │                                       ├── .ok → provider.complete(...)
  │                                       │
  │                                       └── .wouldOverflow → compactWithSummaryIfNeeded
  │                                                              │
  │                                                              ├── fits → provider.complete(...)
  │                                                              │
  │                                                              └── still over → throw
  │                                                                                EngineError.preflightOverflow
  ▼
provider.complete(...) ──► CriticPolicyResolver.resolve(...)
                              │
                              ├── .skip → done
                              │
                              ├── .deterministicOnly → CriterionChecker.check(each StepCriterion)
                              │                          │
                              │                          ├── all pass → done (Stage 2 skipped)
                              │                          │
                              │                          └── any fail → CriticEngine.evaluate(...)
                              │
                              └── .run → CriticEngine.evaluate(...)

EngineError.preflightOverflow OR iteration ceiling reached
  │
  ▼
EscalationHandler.escalateOrStop(reason:)
  │
  ├── PlannerEngine.refineStep(reason: .budget OR .iterationCap)
  │     │
  │     ├── .decomposed([substep, ...]) → continueWith(replacementSteps)
  │     │
  │     └── .cannotDecompose(reason) → try cross-provider routing
  │           │
  │           ├── ProviderRegistry.providersOrderedByBudget() ─► .routeToProvider(...)
  │           │
  │           └── no provider fits → .stop(message:)
  │
  └── never recurse, never re-enter runLoop
```

### ProviderBudget

Each provider/model entry advertises its input window as configuration data, not assumption.

```swift
struct ProviderBudget: Sendable, Equatable, Codable {
    let maxInputTokens: Int
    let reservedOutputTokens: Int
    var usableInputTokens: Int { maxInputTokens - reservedOutputTokens }
}
```

Stored on `ProviderConfig.budget: ProviderBudget?`. Missing budget falls back to a conservative
default of `(maxInputTokens: 32_000, reservedOutputTokens: 4_096)` so legacy configs continue
to work.

Built-in provider seeds:

| Provider | maxInputTokens | reservedOutputTokens |
|---|---|---|
| DeepSeek V4 | 65 536 | 8 192 |
| Anthropic Sonnet/Opus 4.7 | 200 000 | 16 384 |
| Anthropic Haiku 4.5 | 200 000 | 8 192 |
| OpenAI gpt-4-class | 128 000 | 8 192 |
| LM Studio local | from `LocalModelManager.currentContextLength` − reservedOutputTokens |
| (fallback) | 32 000 | 4 096 |

Local-model budgets adapt to the currently-loaded context length. When `ensureContextLength`
grows the local window, the budget grows with it.

### TokenEstimator

Pure function that estimates a `CompletionRequest`'s prompt size without sending it.

```swift
enum TokenEstimator {
    static func estimate(request: CompletionRequest, baseURL: URL, modelID: String) -> Int
    static func estimateText(_ text: String) -> Int
}
```

Implementation: encodes the request via the same `encodeRequest` path the engine uses for the
actual HTTP call, computes `body_bytes / 4 * 1.2 + 512`. The 1.2x factor and 512-token floor
are intentional over-estimates — a wasted compaction is cheap; a 400 is expensive.

`estimateText` is the companion used by `RAGSelector` and other per-component sizers.

### Pre-flight gate

Every `provider.complete(...)` call is preceded by `preflightCheck`.

```swift
enum PreflightOutcome: Sendable {
    case ok
    case wouldOverflow(estimated: Int, budget: Int)
}

enum EngineError: Error, Sendable {
    case preflightOverflow(estimated: Int, budget: Int)
}

func preflightCheck(
    request: CompletionRequest,
    provider: any LLMProvider
) async throws -> PreflightOutcome
```

Behaviour:

1. Compute `estimated = TokenEstimator.estimate(request:, ...)`.
2. Resolve `budget = provider.budget ?? defaultBudget`.
3. If `estimated ≤ budget.usableInputTokens` → emit `engine.preflight.ok`, return `.ok`.
4. Else → emit `engine.preflight.overflow`, apply working-set caps + summary compaction.
5. Re-estimate. If now under → emit `engine.preflight.compacted`, return `.ok`.
6. If still over → throw `EngineError.preflightOverflow(estimated:budget:)`.

`EngineError.preflightOverflow` is the trigger for the escalation path. It is the *only* way
context-overrun handling enters the system in v2.1.

### Lowered compaction thresholds

V2.0 thresholds were calibrated assuming a 32 K-ish context. V2.1 lowers them so compaction
fires well before the cliff:

| Threshold | V2.0 | V2.1 |
|---|---|---|
| `preRunCompactionThreshold` | 10 000 tokens | 6 000 tokens |
| `midLoopCompactionThreshold` | 40 000 tokens | 20 000 tokens |

Both remain `var` for test override. The change moves compaction from "fire when bloated" to
"fire when growing."

### Working-set caps

The prompt context is decomposed into four components, each with its own ceiling derived from
the active `ProviderBudget`.

```swift
struct WorkingSetBudget: Sendable {
    let systemPromptCap: Int     // ~10% of usableInputTokens
    let ragInjectionCap: Int     // ~25%
    let recentTurnsCap: Int      // ~50%
    let toolBurstCap: Int        // ~15%
    var total: Int { systemPromptCap + ragInjectionCap + recentTurnsCap + toolBurstCap }
    static func derive(from budget: ProviderBudget) -> WorkingSetBudget
}
```

`total ≤ budget.usableInputTokens` always. Components carry a 256-token floor; when the budget
is too small to satisfy all floors, the system emits `engine.workingset.budget_too_small` and
falls back to proportional floors.

`ContextManager.applyWorkingSetCaps(_:)` truncates each component to its cap, in this order
when over:

1. Compact tool exchanges via existing summary path.
2. Drop oldest recent turns.
3. Trim RAG chunks by count, then by length.
4. Last resort: truncate system prompt with `[truncated for budget]` marker.

`ContextManager.compactAfterToolBurst()` fires at the end of each tool-dispatch round when
the tool-burst component is over its cap. This replaces the prior global `compactWithSummaryIfNeeded`
invocation at the tool-dispatch site — compaction is now per-component, not per-turn.

### Adaptive RAG

V2.0 retrieved a static number of RAG chunks (`min(max(ragChunkLimit, 1), 20)`). V2.1 makes
the count adaptive.

```swift
enum RAGSelector {
    static func selectChunks(
        candidates: [RAGChunk],
        budget: Int,
        userCeiling: Int
    ) -> [RAGChunk]
}
```

Greedy-by-token selection in retrieval order. Includes chunks until adding the next would
exceed `budget`. Never exceeds `userCeiling`. `userCeiling` is the existing `ragChunkLimit`
setting — now an upper bound, not the active value.

Effect: a 200 K-context provider sees richer grounding; a 32 K provider sees minimal grounding;
a 4 K toy model sees almost none. User setting unchanged across providers.

Emits `engine.rag.selected` with `{candidate_count, selected_count, tokens_used, budget_cap}`.

### Enriched PlanStep + structured success criteria

`PlanStep` grows from a description+complexity record into a self-describing executable unit.

```swift
enum StepCriterion: Sendable, Equatable, Codable {
    case prose(String)
    case buildSucceeds
    case testsPass(scheme: String?)
    case fileExists(path: String)
    case regexMatch(pattern: String, in: RegexTarget)
    case shellExitZero(command: String)
    enum RegexTarget: String, Codable, Sendable { case stdout, file }
}

enum CriticMode: String, Codable, Sendable {
    case required, optional, skip
}

struct PlanStep: Sendable {
    var description: String
    var successCriteria: [StepCriterion]   // structured, not prose
    var complexity: ComplexityTier
    var parallelSafe: Bool = false
    var tokenBudget: Int                   // expected size for this step's requests
    var requiresCritic: CriticMode = .optional
    var minContextRequired: Int            // floor on usableInputTokens for this step
}
```

Backwards-compat: a legacy decode where `successCriteria` is a single string wraps it in
`[.prose(s)]`. Missing `tokenBudget` defaults to `usableInputTokens / 4`. Missing
`minContextRequired` defaults to `tokenBudget * 2`.

Structured criteria enable the **deterministic short-circuit** in the critic (next subsection):
when every criterion is non-`prose` and `CriterionChecker.check` returns true for all of them,
the LLM critic is skipped entirely.

### PlannerEngine.refineStep — single decomposition entry point

V2.1 introduces one method the planner exposes for *all* mid-execution decomposition:

```swift
enum RefineReason: Sendable {
    case iterationCap(loopCount: Int, lastObservation: String)
    case budget(estimated: Int, budget: Int)
    case explicit(String)
}

enum RefineOutcome: Sendable {
    case decomposed([PlanStep])
    case cannotDecompose(reason: String)
}

extension PlannerEngine {
    func refineStep(
        _ step: PlanStep,
        reason: RefineReason,
        context: [Message]
    ) async -> RefineOutcome
}
```

`refineStep` is called from two trigger sites:

- **ReAct iteration ceiling.** When `loopCount` reaches `nearCeilingThreshold` *and* the
  loop made no observable progress (no new tool calls, no new text, no new written files) in
  the last 3 iterations, the engine calls `refineStep(reason: .iterationCap)`.
- **Pre-flight budget overflow.** When `preflightCheck` throws
  `EngineError.preflightOverflow`, the engine calls `refineStep(reason: .budget)`.

The `reason` lets the planner bias decomposition. `.budget` asks for smaller-context substeps
even at the cost of more steps. `.iterationCap` asks for more concretely-scoped substeps
because the agent was thrashing on ambiguity.

The planner returns `.cannotDecompose` when the step is genuinely atomic — a single oversized
artifact (a 180 K-token file the user pasted, a huge stack trace, an intrinsically-large
output target). This is the *only* case where cross-provider escalation is the correct
response.

### EscalationHandler — the single retry/escalation policy

V2.0 had several independent retry counters (`contextLengthRetryCount`,
`maxContextOverrunRecoveryAttempts`, `criticRetryCount`, the iteration-ceiling
`[CONTINUATION]` mechanism). V2.1 consolidates them behind one bounded helper.

```swift
enum EscalationReason: Sendable {
    case iterationCap(loopCount: Int, lastObservation: String)
    case preflightOverflow(estimated: Int, budget: Int)
}

enum EscalationDecision: Sendable {
    case continueWith(replacementSteps: [PlanStep])
    case routeToProvider(providerID: String, reason: String)
    case stop(message: String)
}

actor EscalationHandler {
    init(planner: PlannerEngine, registry: ProviderRegistry, maxRefinementsPerTurn: Int = 2)

    func escalateOrStop(
        currentStep: PlanStep,
        reason: EscalationReason,
        context: [Message]
    ) async -> EscalationDecision
}
```

Behaviour ladder:

1. Call `planner.refineStep(currentStep, reason: …, context: …)`.
2. On `.decomposed(substeps)` → return `.continueWith(replacementSteps: substeps)`.
3. On `.cannotDecompose(reason)`:
   - Query `registry.providersOrderedByBudget()`.
   - Find the smallest-budget provider whose `usableInputTokens ≥ step.minContextRequired`.
   - If found → return `.routeToProvider(providerID:, reason:)`.
   - If none → return `.stop(message: "...")`.
4. Once `maxRefinementsPerTurn` is exceeded in a single user turn → return
   `.stop(message: "refinement budget exhausted")` immediately, no further refinement
   attempts.

**Decompose-first, escalate as last resort.** Most overflows resolve via decomposition.
Cross-provider routing fires only for genuinely atomic work. Graceful stop happens only when
no configured provider supports the required context. The user never sees an infinite loop
because no code path inside `escalateOrStop` recurses.

### The no-recursion invariant

V2.1 deletes the recursive `runLoop` self-call at the old `AgenticEngine.swift:1076`
location. The catch block for `ProviderError.isContextLengthExceeded` is reduced to:

1. Emit telemetry (with redacted error body — see Budget Telemetry).
2. Attempt one summary compaction via `ContextManager.compactWithSummaryIfNeeded`.
3. Re-estimate. If now fits → resume the current loop iteration.
4. If still over → call `EscalationHandler.escalateOrStop(reason: .preflightOverflow)`.
5. Act on the decision in-place. Never re-enter `runLoop`.

Properties removed in v2.1:

- `contextLengthRetryCount`
- `maxContextOverrunRecoveryAttempts`
- `contextOverrunRecoveryDirective(attempt:maxAttempts:userMessage:)`

These were all internal members with no external consumers. A regression-guard test
(`RetryCounterDeletionTests`) string-searches `AgenticEngine.swift` to assert the deleted
symbols stay deleted.

### Critic gating

V2.0's critic invocation was a hard-coded heuristic at the dispatch site. V2.1 routes
through one policy resolver consulting three inputs.

```swift
enum CriticDecision: Sendable {
    case run, skip, deterministicOnly
}

enum CriticPolicyResolver {
    static func resolve(
        skill: SkillFrontmatter?,
        step: PlanStep?,
        heuristic: (writtenFiles: Bool, substantial: Bool, complexity: ComplexityTier),
        classifierOverride: Bool
    ) -> CriticDecision
}
```

Precedence (high → low):

1. Skill frontmatter `critic: skip` → `.skip`.
2. Skill frontmatter `critic: required` → `.run`.
3. `PlanStep.requiresCritic == .skip` → `.skip`.
4. `PlanStep.requiresCritic == .required` → `.run`.
5. If `step` has only non-`prose` criteria → `.deterministicOnly`.
6. Heuristic (heavy diff / complexity tier / classifier override) → `.run` if any flag is true.
7. Otherwise → `.skip`.

`SkillFrontmatter` gains a `critic: CriticMode?` field, parsed from YAML `critic:`. Unknown
values emit `skill.frontmatter.warning` telemetry and store `nil`.

### CriterionChecker — deterministic verification

When `CriticPolicyResolver` returns `.deterministicOnly`, the executor runs
`CriterionChecker.check` for each `StepCriterion` on the step. If all pass, the LLM critic
(Stage 2) is skipped entirely. If any fail, the engine falls through to
`CriticEngine.evaluate(...)` with the failing criterion as the seed reason.

```swift
actor CriterionChecker {
    init(shellRunner: any ShellRunning)
    func check(_ criterion: StepCriterion) async -> Bool
}
```

Mapping:

| Criterion | Check |
|---|---|
| `buildSucceeds` | Existing `xcodebuild` invocation, exit code 0 |
| `testsPass(scheme:)` | `xcodebuild test` for the given scheme, exit code 0 |
| `fileExists(path:)` | `FileManager.fileExists(atPath:)` |
| `regexMatch(pattern:, in: .stdout)` | Re-run a captured shell command; match output |
| `regexMatch(pattern:, in: .file)` | Read file content; match |
| `shellExitZero(command:)` | `ShellRunning.run`, exit code 0 |
| `prose(_)` | Always returns false — falls through to LLM critic |

This is the recursive application of the article's framework (article: *Choosing the Right
Agentic Design Pattern*) at the verification layer: when a check is mechanically verifiable,
no reasoning is needed; when it's prose, LLM reasoning is.

### Budget telemetry

V2.1 adds a comprehensive observability surface so threshold tuning, drift diagnosis, and
overrun forensics are data-driven rather than guesswork.

Events emitted from the engine:

| Event | Payload |
|---|---|
| `engine.preflight.estimate` | `{estimated_tokens, provider_id, slot}` per turn |
| `engine.preflight.ok` | `{estimated_tokens, budget}` |
| `engine.preflight.overflow` | `{estimated_tokens, budget}` |
| `engine.preflight.compacted` | `{before, after, provider_id}` |
| `engine.workingset.budget_too_small` | `{usable, floors_total}` |
| `engine.rag.selected` | `{candidate_count, selected_count, tokens_used, budget_cap}` |
| `engine.escalation.start` | `{reason, step_description_prefix}` |
| `engine.escalation.refined` | `{substep_count}` |
| `engine.escalation.route_to_provider` | `{from, to, min_context_required}` |
| `engine.escalation.stop` | `{message}` |
| `engine.turn.error` | `{error_domain, error_code, error_status, error_body}` (body redacted) |
| `critic.stage1.short_circuit` | `{criteria_passed}` |
| `critic.skipped.policy` | `{decision_source: skill | step | heuristic}` |
| `planner.classify` | (existing — unchanged) |
| `planner.decompose.*` | (existing — unchanged) |
| `planner.step.executing` | `{step_index, total_steps, complexity, description_prefix}` |
| `planner.refine.start` | `{reason}` |
| `planner.refine.success` | `{substep_count}` |
| `planner.refine.cannot_decompose` | `{reason}` |
| `skill.frontmatter.warning` | `{skill_id, key, value}` |

`error_body` is redacted via `RedactedString.redacted(_:)` — strips `sk-…`, `pk-…`,
`Bearer …` substrings, trims to 500 chars. The redaction is applied before the payload
reaches `TelemetryEmitter`.

### Migration notes

What v2.1 changes that callers should know:

- `PlanStep.successCriteria` changes type from `String` to `[StepCriterion]`. Decoder accepts
  the legacy single-string form via `[.prose(s)]` wrapping. Existing serialized plans load
  unchanged.
- `AgenticEngine` removes `contextLengthRetryCount`, `maxContextOverrunRecoveryAttempts`,
  `contextOverrunRecoveryDirective`. Internal-only — no external consumers.
- `AgentEvent` gains `.cleanStop(reason: String, summary: String)`. UI consumers fall through
  to `.systemNote` rendering until a distinct UI affordance ships in a later phase.
- `SkillFrontmatter` gains `critic: CriticMode?`. Absent value preserves heuristic behaviour;
  no skill needs updating to keep working.
- `AppSettings.ragChunkLimit` semantics shift from "the number to retrieve" to "the maximum
  allowed if budget permits." User-visible doc-comment is updated.
- Compaction thresholds drop (10 K → 6 K pre-run, 40 K → 20 K mid-loop). More-frequent
  compaction is the explicit goal.

No user data migration required.

### Implementation order

Eight phase pairs plus a release phase, in dependency order:

| Phases | Concern |
|---|---|
| 232a / 232b | Budget telemetry (observability only) |
| 233a / 233b | `ProviderBudget` + `TokenEstimator` + pre-flight gate + lowered thresholds |
| 234a / 234b | Working-set caps |
| 235a / 235b | Adaptive RAG |
| 236a / 236b | Enriched `PlanStep` + `PlannerEngine.refineStep` |
| 237a / 237b | `EscalationHandler` + delete recursive recovery |
| 238a / 238b | Critic gating |
| 239a / 239b | Decompose-on-overflow + cross-provider fallback |
| 240a / 240b | v2.1.0 release (project.yml bump, `RELEASE-v2.1.0.md`, tag, GitHub release) |

Dependency graph:

```
232 ──► 233 ──► 234 ──► 235
                  │
                  └──► 236 ──┬──► 237 ──┬──► 238
                             │          │
                             │          └──► 239
                             │
                             └──► 240 (release)
```

Phases 235 and 238 are leaves and can defer if needed. Phases 232, 233, 234, 236, 237, 239
are the critical path to budget-aware execution. 240 is the milestone release.

### Honest trade-offs

- **Conservative estimation wastes some context.** A 1.2× safety margin means a 65 K window
  effectively becomes ~50 K usable. Worth it — a wasted compaction is cheap, a 400 is
  expensive.
- **Small-context providers lose features.** A 4 K-context local model cannot do RAG-heavy
  tasks. The system *routes around* this (working-set caps shrink RAG share; cross-provider
  escalation hands oversized steps to bigger models), but for users with only a tiny local
  model configured, some operations will gracefully stop.
- **Per-step pre-flight adds latency.** One `TokenEstimator.estimate` call per step is
  inexpensive (microseconds) but non-zero. Net effect is positive because avoided 400s save
  much more than the estimator costs.
- **Planner becomes load-bearing.** `refineStep` runs every time decomposition fires. A
  planner outage or slow planner provider can stall escalation. Mitigation: the `maxRefinementsPerTurn`
  cap (default 2) prevents unbounded planner calls; the planner uses the orchestrate slot
  which can be assigned a fast model.

---

## V2.2 — Project Discipline Subsystem

### Motivation

Merlin v2.0/v2.1 give the user an agentic loop strong enough to drive software construction.
But construction discipline — TDD phase pairs, version bumps at the right moment, documentation
that stays comprehensive, code comments where warranted, prose readability — is still enforced
by *the user remembering to do it*. Memory is the wrong substrate for non-negotiables. The
2026-05-13 article *Choosing the Right Agentic Design Pattern* names the equivalent failure
mode in agents: *"Discipline that depends on remembering doesn't survive contact with a tired
Friday afternoon."*

V2.2 builds the discipline directly into Merlin. Skills handle *creation* (init a project,
build a phase, propose a release). Hooks and a new `DisciplineEngine` handle *enforcement*
(scan for drift, block bad commits, surface pending attention at session start). The user
invokes the creation skills when they choose to; the enforcement layer runs whether the user
remembers it or not.

The two design principles:

1. **Default-trust, trigger-detect, require-on-trigger.** Most code, most docs, most commits
   are fine and no prompt fires. The system watches for *specific triggers* (a new public
   symbol without a doc comment, a new user-facing surface without a manual section, a
   substantive change without a doc touch) and only then demands action. The default position
   is silence.
2. **No recursion, no unbounded retry.** Every enforcement path is bounded and auditable, just
   like v2.1's `EscalationHandler`. Overriding is allowed; overriding silently is not.

### Architecture overview

Three layers, only one of which the user invokes.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Layer 1 — Creation skills (manual invocation)                            │
│   /project:init     — scaffold a new project                             │
│   /project:phase    — build a TDD phase pair                             │
│   /project:revise   — fix detected drift                                 │
│   /project:release  — bump version, regenerate api.md, tag, publish      │
│   /project:adopt    — apply discipline to an existing project            │
└──────────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ used occasionally, by the user
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ Layer 2 — DisciplineEngine + Merlin hooks (soft surfacing, automatic)    │
│   Stop hook         — after each turn: run scanners, update queue        │
│   SessionStart hook — on session open: surface pending findings          │
│   UserPromptSubmit  — flag mismatches before work starts                 │
└──────────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ runs whether the user remembers or not
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ Layer 3 — Git hooks (hard enforcement, blocks bad commits)               │
│   pre-commit        — block on uncommented WHY-triggers, missing docs,   │
│                       missing manual coverage, TODO without reference    │
│   pre-push          — block tag/version mismatch                         │
└──────────────────────────────────────────────────────────────────────────┘
```

The user invokes Layer 1 when they want to *do* something. Layers 2 and 3 invoke themselves.
`/project:init` (or `/project:adopt`) installs Layers 2 and 3 once, after which the project
self-polices.

### DisciplineEngine

A new `Merlin/Engine/DisciplineEngine.swift` actor, peer to `AgenticEngine`, `MemoryEngine`,
`PlannerEngine`. Coordinates the scanners, owns the pending-attention queue, integrates with
the hook engine.

```swift
actor DisciplineEngine {
    init(
        adapter: ProjectAdapter,
        phaseScanner: PhaseScanner,
        manualCoverageScanner: ManualCoverageScanner,
        docReferenceGraph: DocReferenceGraph,
        whyCommentScanner: WhyCommentScanner,
        proseReadabilityChecker: ProseReadabilityChecker
    )

    func scan(projectPath: String) async -> ScanReport
    func pendingAttention(projectPath: String) async -> [Finding]
    func dismiss(findingID: UUID, rationale: String) async
}
```

Invoked from the existing `hookEngine.runStop()` path after every user turn. Writes findings
to `.merlin/pending.json`. Read by the new `SessionStart` hook on subsequent session open.

Has its own circuit breaker (mirroring v2.1's `EscalationHandler` invariant): if scanning
fails three times in a row, the engine disables itself for the session and emits
`discipline.disabled` rather than blocking the user's work.

### Adapter system

Per-language/per-toolchain config that every component consumes. Single source of truth for
project-specific commands and conventions.

```toml
# ~/.merlin/adapters/swift-xcode.toml
language = "swift"
swift_version = "5.10"
versioning_file = "project.yml"
versioning_field = "MARKETING_VERSION"
build_version_field = "CURRENT_PROJECT_VERSION"
build_command = "xcodebuild -scheme {scheme} build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/build"
test_command = "xcodebuild -scheme {scheme} test -destination 'platform=macOS' -derivedDataPath /tmp/build"
strict_mode = "SWIFT_STRICT_CONCURRENCY=complete"
build_success_marker = "BUILD SUCCEEDED"
build_failure_marker = "BUILD FAILED"
release_command = "gh release create v{version} --notes-file RELEASE-v{version}.md --latest"
api_doc_generator = "docc"
doc_target_grade = { user_manual = 9, developer_guide = 9, architecture = 11 }

[why_comment_triggers]
# Patterns that demand a nearby explanatory comment
patterns = [
    { regex = "Task\\.sleep\\(", reason = "duration is judgment" },
    { regex = "try\\?", reason = "discarded error needs rationale" },
    { regex = "catch \\{ \\}", reason = "silenced error needs rationale" },
    { regex = "nonisolated\\(unsafe\\)", reason = "concurrency assertion" },
    { regex = "@unchecked Sendable", reason = "concurrency assertion" },
    { regex = "if .+\\.id == \"", reason = "special-case ID compare" },
]

[manual_coverage]
surface_patterns = [
    { type = "menu_item", regex = "CommandGroup|CommandMenu" },
    { type = "shortcut", regex = "\\.keyboardShortcut\\(" },
    { type = "settings_field", regex = "AppSettings\\.[a-z][A-Za-z0-9]+" },
    { type = "slash_command", regex = "SkillRegistry\\.register" },
    { type = "hook_event", regex = "HookEvent\\.[a-z][A-Za-z0-9]+" },
]
```

```toml
# ~/.merlin/adapters/rust-cargo.toml
language = "rust"
edition = "2024"
versioning_file = "Cargo.toml"
versioning_field = "version"
build_command = "cargo build --workspace"
test_command = "cargo test --workspace"
lint_command = "cargo clippy --all-targets -- -D warnings"
format_command = "cargo fmt -- --check"
strict_mode = "clippy_pedantic"
build_success_marker = "Finished"
build_failure_marker = "error\\["
release_command = "cargo publish"
api_doc_generator = "rustdoc"
doc_target_grade = { user_manual = 9, developer_guide = 9, architecture = 11 }
default_targets = [
    "x86_64-apple-darwin",
    "aarch64-apple-darwin",
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
]

[why_comment_triggers]
patterns = [
    { regex = "unsafe \\{", reason = "Rust convention requires // Safety:" },
    { regex = "\\.unwrap\\(\\)", reason = "panic point needs justification" },
    { regex = "\\.expect\\(", reason = "panic point needs justification" },
    { regex = "transmute\\(", reason = "always needs justification" },
    { regex = "#\\[allow\\(", reason = "lint suppression needs rationale" },
    { regex = "todo!\\(\\)", reason = "must reference issue/phase" },
    { regex = "Duration::from_millis\\(", reason = "duration is judgment" },
]
```

Adapter selection per project lives in `.merlin/project.toml`:

```toml
adapter = "swift-xcode"
adapter_version = "1.0"
discipline_layers = ["soft_prompt", "pre_commit"]
manual_coverage_baseline = 0    # set by project:adopt; decays toward zero
```

Personal defaults live in `~/.merlin/conventions.toml`. Per-project overrides take precedence.

Adapters carry a `version` field. `DisciplineEngine` warns when a project's adapter is older
than the installed adapter; the user runs `/project:revise --update-adapter` to migrate.

### Storage layout

```
~/.merlin/
  conventions.toml              — personal defaults
  adapters/                     — per-language adapter library
    swift-xcode.toml
    rust-cargo.toml
    typescript-node.toml        — later
    python-pytest.toml          — later
  skills/
    project-init/SKILL.md
    project-phase/SKILL.md
    project-revise/SKILL.md
    project-release/SKILL.md
    project-adopt/SKILL.md
  templates/
    docs/
      README.md.template
      architecture.md.template
      api.md.template
      developer-guide.md.template
      user-manual.md.template
      FEATURES.md.template
      CHANGELOG.md.template
    manual-sections/
      toggle-setting.md.template
      command.md.template
      slash-command.md.template
      major-feature.md.template
    phase/
      NNa-skeleton.md.template
      NNb-skeleton.md.template
    vale/
      Merlin/                   — Vale style files for prose readability

<project>/
  .merlin/
    project.toml                — adapter selection + per-project overrides
    pending.json                — DisciplineEngine queue
    override-log.jsonl          — audit trail of dismissed prompts
    manual-coverage-baseline.json
    drift-snapshot.json         — last full scan, for diff display
  .git/hooks/
    pre-commit                  — installed by /project:init
    pre-push                    — installed by /project:init
  phases/                       — Merlin's existing convention; not changed
  docs/                         — optional alternative location for the doc set
```

### PhaseScanner

Reads `phases/` directory, extracts declared surfaces from each NNb file, cross-checks against
the current codebase. Builds a drift report classified into four colours.

```swift
enum DriftSeverity: Sendable {
    case green       // surface present, shape unchanged
    case yellow      // surface present, signature changed (likely refactor)
    case red         // surface absent from code (deletion without addendum)
    case orange      // code surface not declared in any phase (undocumented)
}

struct DriftFinding: Sendable, Identifiable {
    let id: UUID
    let phaseID: String?
    let surface: String
    let severity: DriftSeverity
    let evidence: String
    let suggestedAction: String
}

actor PhaseScanner {
    func scan(projectPath: String) async -> [DriftFinding]
}
```

The scanner parses each NNb's "New surface introduced in phase NNb:" block (the convention
already used throughout `phases/`). It greps for each named symbol against the current source
tree. Yellow/red findings produce a proposed patch (either updating the phase to match current
code, or creating a `phase-NNc-supersedes-NNb.md` addendum per the existing CLAUDE.md
convention).

The scanner is the load-bearing component of v2.2 — it validates that the phase methodology
remains rebuildable from its phase files, which CLAUDE.md already declares as the source of
truth.

### ManualCoverageScanner

The hard constraint: every user-facing surface must be covered by a `user-manual.md` section.

```swift
struct ManualCoverageGap: Sendable {
    let surface: String              // e.g., "AppSettings.activeProviderID"
    let surfaceType: String          // "settings_field", "menu_item", etc.
    let firstSeen: Date
    let suggestedSection: String?    // generated from template
}

actor ManualCoverageScanner {
    func scan(projectPath: String, adapter: ProjectAdapter) async -> [ManualCoverageGap]
}
```

Surface enumeration uses the regex patterns declared in the adapter
(`[manual_coverage] surface_patterns`). For Merlin, the v1 enumeration covers menu items,
shortcuts, settings fields, slash commands, hook events. Each surface is normalized to a
stable identifier (e.g., `AppSettings.activeProviderID`).

Coverage declaration lives in manual sections via HTML comments:

```markdown
## How to set your active provider

<!-- covers:
     - AppSettings.activeProviderID
     - SettingsView.ProviderPanel
     - command:set-provider
-->

To pick the model Merlin uses, open Settings → Providers...
```

The scanner reads every `<!-- covers: ... -->` block, builds the coverage map, and flags:

| Finding | Action |
|---|---|
| Surface exists, no section covers it | Gap — pending-attention; release blocked if not addressed |
| Section covers a surface that no longer exists | Stale reference — pending-attention; release blocked |
| Section covers a surface whose shape changed | Soft prompt — section may need rewrite |

**Not-user-facing escape.** Some code-detected surfaces aren't actually user-facing (internal
hook events, debug commands, telemetry channels). These declare an explicit marker:

```swift
// manual: not-user-facing — internal telemetry channel, no UI binding
static let merlinTelemetryFlushed = Notification.Name("merlin.telemetry.flushed")
```

The marker:

- Suppresses the coverage requirement for that surface.
- Logs to `.merlin/override-log.jsonl` with the rationale string.
- Periodic review (a Layer 2 weekly check) surfaces "N surfaces marked not-user-facing in the
  last release — should any be exposed and documented?"

### Comprehensive manual: enforcement layers

The user manual is a hard constraint — not just synced, **comprehensive**. Four layers
together make a release with uncovered surfaces structurally impossible.

1. **Phase template extension.** Every NNb that adds user-facing surface includes a
   `## Manual updates` section listing the manual sections to add or modify. Worker writes
   both code and manual section in the same commit.
2. **Critic Stage 2 check.** After NNb implementation, the critic prompt extension asks:
   *"List user-facing surfaces added or changed in this diff. For each, name the manual
   section that covers it."* Uncovered surfaces produce a critic `.fail`; worker rewrites.
3. **Pre-commit hook.** `ManualCoverageScanner` runs against the diff. Block commit if any
   new user-facing surface lacks coverage. Override allowed only with explicit
   `// manual: not-user-facing` marker plus rationale.
4. **Release gate.** `/project:release` runs the scanner across the entire codebase. Any
   uncovered surface blocks the release.

### Decaying coverage baseline

When `/project:adopt` installs the discipline into an existing project, the scanner will find
many uncovered surfaces. Three handling strategies were evaluated:

| Strategy | Verdict |
|---|---|
| Block from day one | Halts forward work for weeks — rejected |
| Snapshot and grandfather forever | Existing gaps never close — rejected |
| **Snapshot baseline, decaying** | Forward path realistic, closes the gap over time — adopted |

The adopted strategy: `/project:adopt` records the current uncovered-surface count as
`manual_coverage_baseline` in `.merlin/project.toml`. From then on the release gate requires
both:

1. No *new* uncovered surfaces in the current release diff.
2. The baseline reduces by at least `N` (default 10) each release until it reaches zero.

Within ~30 releases the manual becomes comprehensive. Forward work proceeds in parallel.

Override audit surfaces "you've shipped 5 releases at the same baseline — discipline is dead;
restore it or relax it explicitly."

### DocReferenceGraph

Builds a map from doc files to the code symbols they reference, enabling cross-file drift
detection.

```swift
struct DocReference: Sendable {
    let docFile: String
    let docSection: String?
    let codeSymbol: String
    let sourceFile: String?
}

actor DocReferenceGraph {
    func build(projectPath: String) async -> [DocReference]
    func staleReferences(against changedSymbols: [String]) async -> [DocReference]
}
```

Two construction modes:

- **Automatic** (default for v1) — greps doc files for symbol-shaped strings (camelCase,
  PascalCase, snake_case), cross-checks against the code's symbol index. Heuristic but cheap.
  False-positive rate is acceptable because findings are *soft prompts*, not hard blocks.
- **Explicit** (later) — doc files include front-matter declaring covered symbols. More
  robust; available when the automatic mode produces too much noise on a given project.

When a code surface is renamed or removed, the graph flags every doc that mentions the old
name. Goes to pending-attention.

### WhyCommentScanner

Enforces the conditional rule: *"Default to writing no comments. When a WHY-comment is
warranted, it must be present."* No comment-density metric — just trigger detection.

```swift
struct WhyCommentTrigger: Sendable {
    let pattern: String              // regex from adapter
    let reason: String               // human-readable
    let file: String
    let line: Int
    let context: String              // ±2 lines
    let hasNearbyComment: Bool
}

actor WhyCommentScanner {
    func scan(projectPath: String, adapter: ProjectAdapter) async -> [WhyCommentTrigger]
}
```

For each match in the trigger list (adapter-defined; see Swift and Rust examples in the
*Adapter system* subsection), the scanner checks for an explanatory comment within
`N` lines (default 3) above or below. Missing comment → finding.

Four enforcement layers, same shape as manual coverage:

| Layer | What | Mode |
|---|---|---|
| Pattern scanner at pre-commit | Block on uncommented trigger | **Hard block** |
| Critic Stage 2 prompt | "List code segments where WHY is non-obvious; suggest comments" | Soft prompt |
| Override annotation | `// rationale-not-needed: <one-line reason>` suppresses | Logged |
| Override audit | Periodic review surfaces high override rate | Logged |

The mechanical layer (pattern scanner + pre-commit) carries the "non-negotiable" guarantee.
The critic layer raises quality but isn't load-bearing.

### ProseReadabilityChecker

Enforces target-grade readability for the doc set.

```swift
struct ReadabilityFinding: Sendable {
    let docFile: String
    let measuredGrade: Double
    let targetGrade: Double
    let suggestions: [String]        // from Vale lint output
}

actor ProseReadabilityChecker {
    func check(docFile: String, targetGrade: Double) async -> ReadabilityFinding
}
```

Implementation calls `vale` (installed as a dev tool, not vendored) with a Merlin-specific
style folder. The style folder contains:

- `Merlin/readability.yml` — sets `Vale.Readability` rule, grade level per file pattern
- `Merlin/accept.txt` — vocabulary that should not be flagged as jargon ("Merlin", "DeepSeek",
  "API", "RAG", "tokenizer", etc.)
- `Merlin/passive-voice.yml` — warns above 10% passive sentences
- `Merlin/weasel.yml` — flags hedging words ("might", "perhaps", "possibly" overuse)

Per-file grade targets from adapter `doc_target_grade`:

| File | Target |
|---|---|
| `user-manual.md` | 9 |
| `developer-guide.md` | 9 |
| `README.md` (top section) | 9 |
| `FEATURES.md` | 9 |
| `RELEASE-vX.Y.Z.md` summary | 9 |
| `architecture.md` | 11 |
| `api.md` (intro prose) | 10 |
| `CLAUDE.md`, `AGENTS.md`, phase files | no constraint |

Two enforcement points:

- **Critic during writing** — after a worker generates or edits a doc, critic Stage 2 runs
  Vale on the changed file. Worker rewrites if grade exceeds target.
- **Pre-commit gate** — Vale runs against changed `.md` files. Hard block if any exceeds its
  declared grade.

The constraint is for the *prose itself*, not the subject matter. Technical concepts (planner
architecture, budget-aware execution) can be discussed in 8th-grade prose; the system enforces
*how* you write, not *what* you write about.

### Project skills

Five conversational skills, namespaced under `project:`.

#### project:init

Scaffold a new project. Asks:

- Project name + one-line description
- Language (selects adapter)
- Target architectures (adapter-specific defaults)
- License
- Doc-set choice (full / minimal)
- Discipline layer opt-in (Layer 2 default yes; Layer 3 default yes)

Produces:

- Language-native scaffold (calls `cargo new` / equivalent under the hood; does not reinvent it)
- `CLAUDE.md` from template, customised for chosen language and adapter
- Doc set from templates (`README.md`, `architecture.md`, `api.md`, `developer-guide.md`,
  `user-manual.md`, `FEATURES.md`, `CHANGELOG.md`)
- `phases/` directory with `phase-00-scaffold.md` documenting the initial state
- `.merlin/project.toml` with adapter selection
- `.git/hooks/pre-commit` and `.git/hooks/pre-push`
- `.claude/settings.json` with Stop, SessionStart, UserPromptSubmit hooks pointing at
  `DisciplineEngine`
- `.vale.ini` + Merlin style folder copy
- Initial git commit

#### project:phase

Build an NNa/NNb phase pair. Asks structuring questions rather than auto-decomposing:

- What is the one abstraction this phase introduces?
- What prior phase state does it depend on?
- What surfaces does NNb introduce?
- What deletions does NNb perform? (regression-guard tests added automatically if any)
- Is this version-bump-eligible? (no for substantive phases; yes only for release milestones)

Calls `PlannerEngine.refineStep` internally to validate the decomposition (depends on v2.1).
Critic Stage 2 verifies the resulting phase shape (single concern, tests precede impl,
deletions guarded, manual sections planned for any user-facing surface).

Writes both phase files plus a `PASTE-LIST.md` update plus an orchestrator-prompt snippet.

#### project:revise

Run `DisciplineEngine.scan`, present findings, propose patches. For each finding the user
selects:

- Accept proposed patch (skill applies it)
- Modify (skill opens editor; user revises; skill validates and applies)
- Dismiss with rationale (logged to override audit)
- Defer (left in `pending.json` for later)

Outputs a single commit per accepted batch, with structured commit message referencing each
addressed finding.

#### project:release

The consolidated release gate. Runs:

```
□ All phase 232a–239b tests pass (or equivalent for the current milestone)
□ api.md regenerated and committed (autogen from doc comments)
□ developer-guide.md mechanical sections regenerated
□ user-manual.md: zero new uncovered surfaces; baseline reduced by ≥ N
□ DocReferenceGraph: no red findings (stale references)
□ WhyCommentScanner: zero violations or all overridden with rationale
□ ProseReadabilityChecker: all doc files at or under target grade
□ RELEASE-vX.Y.Z.md present, references the changes
□ CHANGELOG.md updated
□ PhaseScanner reports clean (no red/orange drift)
□ project.yml / Cargo.toml / equivalent version bumped per adapter
□ Build version field incremented
```

Any failure blocks the release. Pass produces:

- The version-bump commit
- The git tag
- A push to `origin` and `--tags`
- `gh release create` (Swift) or `cargo publish` (Rust) or equivalent
- An archive of the release-time pending-attention snapshot

#### project:adopt

Apply discipline to an existing project. Different from `init` because the project already
exists with its own conventions. Adopt:

1. Detects language + chooses adapter (or asks).
2. Reads existing `CLAUDE.md` / `AGENTS.md` / `architecture.md` — preserves them, adds a
   "Project Discipline" section if absent.
3. Scans the codebase for current state: existing surfaces, existing doc coverage gaps,
   existing phase files (if any).
4. Writes `.merlin/project.toml` with `manual_coverage_baseline` set to the current uncovered
   count.
5. Installs hooks (with confirmation per layer).
6. Produces a one-page report: *"Adopted. Baseline coverage gap: 314 surfaces. Default
   decay: 10 per release → comprehensive in 32 releases. WHY-comment violations found: 47.
   Prose readability fails in 6 docs. Phase drift: green except 3 yellow."*

The user then runs `/project:revise` to start working through the backlog.

### Hook integration

The existing Merlin hook engine (`hookEngine.runStop`, `hookEngine.runUserPromptSubmit`)
gains a `SessionStart` event and three new event types:

| Event | Trigger | Default action |
|---|---|---|
| `SessionStart` | Session opens with a project loaded | Read `.merlin/pending.json`; inject top-N findings as system reminder |
| `Stop` | After every Claude turn | Run `DisciplineEngine.scan(diff:)` against the turn's file changes |
| `UserPromptSubmit` | Before user message processed | If prompt looks like a feature request, check that an appropriate phase file exists |
| `PostCommit` (new) | After `git commit` succeeds | Run `PhaseScanner` if the commit touched source files |
| `PrePush` (new) | Before `git push` | Verify version-tag consistency |

Hooks can be overridden in `.merlin/config.toml` per project. Default config installed by
`/project:init` is conservative.

### PendingAttention queue

A persisted queue of findings the user hasn't addressed yet.

```swift
struct Finding: Sendable, Identifiable, Codable {
    let id: UUID
    let category: FindingCategory
    let severity: Severity
    let summary: String                  // 1 line
    let detail: String                   // full evidence
    let suggestedAction: String?
    let createdAt: Date
    let lastSeenAt: Date
}

enum FindingCategory: String, Codable, Sendable {
    case phaseDrift
    case manualCoverageGap
    case docStaleReference
    case whyCommentMissing
    case proseReadabilityFail
    case overrideAuditAccumulation
    case ungatedTarget
    case stubbedImplementation
    case unwiredComponent
}

enum Severity: String, Codable, Sendable {
    case block          // hard gate; commit/release refused
    case nudge          // surfaced at session start
    case silent         // logged only, available on request
}
```

Persisted as `.merlin/pending.json`. Findings have an idempotency key so re-running the scanner
doesn't duplicate them. The `SessionStart` hook surfaces the top 3 by severity (then by
recency); a `"N more dismissed"` link lets the user pull the full list when they want it.

### Override audit log

Every override is appended to `.merlin/override-log.jsonl`:

```json
{
  "timestamp": "2026-05-14T12:00:00Z",
  "category": "why_comment_missing",
  "file": "Merlin/Engine/AgenticEngine.swift",
  "line": 137,
  "rationale": "5-second sleep is the documented test fixture wait",
  "user_dismissed": false,
  "via_annotation": true,
  "annotation_text": "// rationale-not-needed: test fixture"
}
```

Periodic review fires weekly: `discipline.override-audit` event with counts per category.
High counts trigger a `pending.json` finding: *"You've used `rationale-not-needed` 9 times
this week. Is the trigger list too aggressive, or are you cutting corners?"*

This is the *meta-discipline* — the system watches its own escape valves and surfaces erosion
before it becomes routine bypass.

### Critic Stage 2 extensions

The existing `CriticEngine.runStage2` (v2.1) gains four new check categories. Each is a
critic prompt extension, gated by the type of change in the diff:

| Trigger | Stage 2 prompt extension |
|---|---|
| Diff contains added/changed source code | *"List code segments where the WHY is non-obvious from names alone. For each, suggest the comment to add."* |
| Diff adds user-facing surface | *"For each new user-facing surface in this diff, name the manual section that covers it. Flag any without coverage."* |
| Diff modifies code referenced in a doc file | *"List doc sections whose accuracy may be affected by this diff."* |
| Diff modifies a doc file | *"Check this prose against the target reading grade. List sentences over 25 words or with passive voice."* |

Each produces a `.fail` with structured reasons; the worker addresses and re-submits. The
existing `criticRetryCount` bounds the loop.

### Telemetry events

V2.2 adds:

| Event | Payload |
|---|---|
| `discipline.scan.start` | `{trigger: stop_hook | session_start | manual}` |
| `discipline.scan.complete` | `{findings_count, duration_ms}` |
| `discipline.scan.error` | `{error}` (circuit breaker counter) |
| `discipline.disabled` | `{consecutive_failures}` |
| `discipline.finding.added` | `{category, severity, file}` |
| `discipline.finding.dismissed` | `{category, rationale}` |
| `discipline.finding.resolved` | `{category, finding_id}` |
| `discipline.override.recorded` | `{category, file, line, rationale}` |
| `discipline.override-audit` | `{category, count, threshold}` (weekly) |
| `discipline.release-gate.start` | `{version}` |
| `discipline.release-gate.fail` | `{version, checks_failed: [string]}` |
| `discipline.release-gate.pass` | `{version}` |
| `discipline.manual-coverage.baseline` | `{baseline, delta_since_last_release}` |

Tied into the existing `TelemetryEmitter` infrastructure from v2.1.

### Portability to Claude Code

Most of v2.2's content is *delivery-mechanism agnostic* by design. The Merlin-specific glue
is the `DisciplineEngine` actor and the UI surfacing. The methodology (skills, adapters,
templates, hook scripts) is portable.

| Component | Merlin | Claude Code |
|---|---|---|
| Adapter `.toml` files | `~/.merlin/adapters/` | `~/.claude/adapters/` — identical format |
| Skill SKILL.md files | `~/.merlin/skills/project-*/` | `~/.claude/skills/project-*/` — identical format |
| Doc templates | `~/.merlin/templates/docs/` | `~/.claude/templates/docs/` — identical content |
| `PhaseScanner` | Swift actor inside `DisciplineEngine` | `scan.sh` bash script |
| `ManualCoverageScanner` | Swift actor | `manual-scan.sh` |
| `WhyCommentScanner` | Swift actor | `why-comment.sh` |
| Pending-attention surfacing | `.systemNote` at session start | `<system-reminder>` injection |
| UI chip / panel | Native SwiftUI | Not applicable |
| Pre-commit hook | Bash script (calls scanner CLI) | Same bash script |

A separate `~/.claude/skills/project-init-claude/SKILL.md` can install the bash-script
equivalent of `DisciplineEngine` into any project. Same methodology, lighter delivery.

### Implementation order (v2.2.0)

Approximately 24 phase pairs plus a release phase. Numbers are placeholders pending v2.1.0
completion (phases 241+).

| Phases | Concern |
|---|---|
| 241a/b | `AdapterRegistry` + adapter format + Swift+Rust seed adapters |
| 242a/b | `.merlin/project.toml` schema + per-project config loader |
| 243a/b | `PhaseScanner` + drift report (validate against Merlin's existing 230+ phases) |
| 244a/b | `PendingAttention` queue persistence + dedupe |
| 245a/b | `DisciplineEngine` actor + hook engine integration |
| 246a/b | `SessionStart` hook event + system-reminder injection |
| 247a/b | `UserPromptSubmit` hook check for unscoped feature requests |
| 248a/b | `PostCommit` / `PrePush` git-hook installer + uninstaller |
| 249a/b | `ManualCoverageScanner` + coverage-comment format |
| 250a/b | Manual section templates + decaying baseline implementation |
| 251a/b | `DocReferenceGraph` automatic mode |
| 252a/b | `APIDocGenerator` (DocC for Swift, rustdoc for Rust) |
| 253a/b | Developer-guide mechanical-section generator |
| 254a/b | `WhyCommentScanner` + trigger lists per adapter |
| 255a/b | WHY-comment pre-commit hook + override annotation parser |
| 256a/b | `ProseReadabilityChecker` + Vale style folder |
| 257a/b | Vale pre-commit gate + critic Stage 2 prose check |
| 258a/b | Override audit log + weekly review event |
| 259a/b | `project:init` skill |
| 260a/b | `project:phase` skill |
| 261a/b | `project:revise` skill |
| 262a/b | `project:release` consolidated gate skill |
| 263a/b | `project:adopt` skill — first target is Merlin itself |
| 264a/b | UI: pending-attention chip + panel in chat view |
| 265a/b | v2.2.0 release (project.yml bump, `RELEASE-v2.2.0.md`, tag, GitHub release) |

Dependency graph:

```
241 ──► 242 ──► 243 ──► 244 ──► 245 ──┬──► 246
                                       ├──► 247
                                       └──► 248
245 ──► 249 ──► 250
245 ──► 251 ──► 252 ──► 253
245 ──► 254 ──► 255
245 ──► 256 ──► 257
245 ──► 258
246+247+248+249+250+251+252+253 ──► 259 (init)
259+243 ──► 260 (phase)
259+243+249+251+254+256+258 ──► 261 (revise)
260+250+252+253+255+257 ──► 262 (release)
259+all-scanners ──► 263 (adopt)
245 ──► 264 (UI)
all ──► 265 (release)
```

Phases 241–248 are the engine + storage foundation. 249–258 are the individual scanners and
checkers. 259–263 are the user-facing skills. 264 is UI. 265 is the milestone release.

Phases that can defer if scope pressure builds: 248 (git-hook installer can use a pre-existing
hook framework), 264 (UI chip; system-reminder injection from 246 is enough for v1), 263 (adopt
can be a follow-up since init covers greenfield).

### Honest trade-offs

- **Implementation surface is significant** (~24 phase pairs). Mitigation: each pair is small
  and well-scoped; the order is incremental; nothing depends on everything.
- **Methodology lock-in.** The discipline encodes specific opinions about software construction
  (TDD, NNa/NNb, comprehensive manuals, version-bump policy). Anyone using Merlin v2.2 inherits
  them. This is intentional and acceptable for the primary user (the codebase author); a
  problem if Merlin acquires external contributors. Soft mitigation: every check is tunable
  via `~/.merlin/conventions.toml`.
- **False positives.** Heuristic scanners (`DocReferenceGraph` automatic mode,
  `WhyCommentScanner` trigger patterns, `ProseReadabilityChecker` jargon detection) will
  occasionally flag things that don't matter. Mitigation: every block has an override
  annotation; every override is logged; periodic audit catches over-triggering before it
  becomes bypass culture.
- **Adapter rot.** Per-language conventions shift (Rust editions, Swift strict concurrency
  flags, ESLint rules). Adapters need upkeep. Mitigation: adapter `version` field; staleness
  warning at scan time; central upgrade via `/project:revise --update-adapter`.
- **Bootstrap cost.** First `/project:adopt` run on Merlin will produce hundreds of findings.
  Working through them is a real cost. Mitigation: decaying baseline strategy means forward
  work proceeds in parallel; the baseline closes at a sustainable rate.
- **Scanner outage breaks discipline.** If `DisciplineEngine` itself bugs, every session
  opens with wrong nags. Mitigation: circuit breaker (three consecutive scan failures →
  disable for session, emit `discipline.disabled`); never recurse; fail silent rather than
  fail loud.

### The pattern across non-negotiables

V2.2 makes seven kinds of construction discipline mechanical:

| Discipline | Trigger | Required action | Hard gate |
|---|---|---|---|
| Phase files stay in sync with code | Source changed | Phase updated or addendum written | Pre-commit on red drift |
| Tests precede implementation | NNb commit | NNa exists, was committed first | Pre-commit on missing NNa |
| Public API has doc comments | Public symbol added | Doc comment present | Lint at pre-commit |
| Public API is documented | Public symbol added | api.md regenerated | Release gate |
| WHY-comments where warranted | Trigger pattern matched | Nearby comment present or annotation | Pre-commit |
| User-facing surface is documented | Surface added | Manual section covers it | Pre-commit + release gate |
| Prose at target readability | Doc file modified | Grade ≤ target | Pre-commit + release gate |

The architecture absorbs each new non-negotiable as one more entry in the catalog, not as
fundamental redesign. New constraints (license headers, dependency audit, accessibility
labels, …) plug into the same three-layer pattern: trigger → required action → bounded
override with audit.

This is the test for whether the abstraction is right: *new disciplines slot in without
moving the load-bearing structure.* V2.2 builds the structure. Future milestones add entries
to it.

---

## Versioning Policy

### Two version fields

`project.yml` carries two independent version identifiers:

| Field | Key | Example | Audience |
|---|---|---|---|
| Marketing version | `MARKETING_VERSION` | `1.2.0` | Users — shown in About Merlin, release notes |
| Build number | `CURRENT_PROJECT_VERSION` | `2` | Tooling — Xcode, notarization, archive comparison |

`MARKETING_VERSION` maps to `CFBundleShortVersionString`; `CURRENT_PROJECT_VERSION` maps to
`CFBundleVersion`. The build number must be a strictly-increasing integer and must never
decrease between releases.

### When to bump

| Change type | `MARKETING_VERSION` | `CURRENT_PROJECT_VERSION` |
|---|---|---|
| Patch — bug fix, test fix, doc fix, no new user-visible surface | `1.0.x → 1.0.x+1` | +1 |
| Minor — new feature, new phase milestone, behaviour change | `1.x.0 → 1.(x+1).0` | +1 |
| Major — breaking API change, architectural overhaul | `x.0.0 → (x+1).0.0` | +1 |
| Internal build — no user-visible change, not tagged | no change | +1 |

### How to release a new version

1. Edit `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Run `xcodegen generate`.
3. Build and confirm "About Merlin" shows the new version.
4. Commit: `git commit -m "Bump version to X.Y.Z"`.
5. Tag: `git tag vX.Y.Z` — tag must exactly match `MARKETING_VERSION` with a `v` prefix.
6. Push: `git push && git push --tags`.
7. Create a GitHub release for the new tag:
```bash
gh release create vX.Y.Z \
    --repo j-zuilkowski/merlin \
    --title "vX.Y.Z — <Short description>" \
    --notes "<Release notes>" \
    --latest
```
Use `--latest` on the newest release. Omit it for older patch releases created retroactively.

**Never** hardcode a version string anywhere except `project.yml`.
**Never** tag a release without first bumping `MARKETING_VERSION` in `project.yml` — the tag
and the in-app string must agree.
**Never** reuse or move a tag that has already been pushed to a remote.
**Always** create a GitHub release immediately after pushing a tag — tags alone do not update the "Latest" release shown on GitHub.

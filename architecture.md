# Merlin — Architecture Document

## Overview

Merlin is a personal, non-distributed agentic development assistant for macOS. It connects to multiple LLM providers — remote (DeepSeek, OpenAI, Anthropic, Qwen, OpenRouter) and local (Ollama, LM Studio, Jan.ai, LocalAI, Mistral.rs, vLLM) — exposes a rich tool registry covering file system, shell, Xcode, and GUI automation, and presents a SwiftUI chat interface.

**[v1]** Single serial session, direct file writes, fixed layout.
**[v2]** Multiple windows (one per project), parallel sessions in Git worktrees, staged diff/review layer, draggable pane workspace, skills, MCP, scheduling, PR monitoring, external connectors.
**[v3]** Agent intelligence + UX completeness: unified settings window, config system, AI-generated memories, hooks, thread automations, web search, reasoning effort, toolbar actions, notifications, personalization, context usage indicator, floating pop-out window, voice dictation.
**[v4]** Subagents (Explorer + Worker), WorktreeManager, SubagentEngine, SubagentStreamUI, full settings surface (all 12 sections), WorkspaceLayoutManager, wired panes (FilePane, TerminalPane, PreviewPane, SideChat), DisabledSkillNames enforcement, keep-awake (IOPMAssertion), AgentRegistry, HookEngine wiring, tool registry launch.
**[v5]** Supervisor-worker multi-LLM: DomainRegistry, DomainPlugin, SoftwareDomain, AgentSlot routing (execute/reason/orchestrate/vision), ModelPerformanceTracker, CriticEngine, PlannerEngine; RAG memory extension: RAGSourcesView, MemoryBrowserView, xcalibre memory write gated on critic verdict; V5 settings UI: RoleSlotSettingsView, PerformanceDashboardView; skill frontmatter role/complexity; OutcomeRecord persistence; StagingBuffer accept/reject counters wired into OutcomeSignals.
**[v6]** LoRA self-training: LoRATrainer (exportJSONL + mlx_lm.lora), LoRACoordinator (threshold-gated auto-train, isTraining guard), LoRA provider routing (execute slot → mlx_lm.server when adapter loaded), LoRASettingsSection; OutcomeRecord prompt/response fields; exportTrainingData filters empty-text records; AppSettings [lora] TOML section.
**[v7]** Inference parameter expansion + local model management: CompletionRequest extended with 8 sampling params (topP, topK, minP, repeatPenalty, frequencyPenalty, presencePenalty, seed, stop); AppSettings [inference] TOML section with applyInferenceDefaults(); ModelParameterAdvisor (finishReason truncation, score variance, trigram repetition, context overflow); LocalModelManagerProtocol with 6 provider implementations + NullModelManager; ModelControlView (per-provider load param editor + RestartInstructionsSheet); accepted memories dual-path to xcalibre RAG.
**[v8]** Cross-provider model calibration: `CalibrationSuite` (18-prompt battery across reasoning, coding, instruction-following, summarization), `CalibrationRunner` (parallel local + reference provider dispatch with critic scoring), `CalibrationAdvisor` (maps score gaps to ParameterAdvisory — context length, temperature, max tokens, repeat penalty), `CalibrationCoordinator` + `/calibrate` skill (provider picker → live progress → report with per-category breakdown and one-tap apply-all via existing applyAdvisory() pipeline).

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
  tracker.exportTrainingData(minScore: 0.7)
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
    │     └── supportedLoadParams: Set<LoadParam>
    ├── loadedModels() → [LoadedModelInfo]
    ├── reload(modelID:config:) async throws   — ModelManagerError.requiresRestart if unsupported
    └── restartInstructions(modelID:config:)   — shell command + config snippet

  Provider implementations:
    LMStudioModelManager   — REST API /api/v1/unload + /api/v1/load; lms CLI fallback
                             canReloadAtRuntime = true
                             supportedLoadParams: contextLength, gpuLayers, cpuThreads,
                                                  flashAttention, cacheTypeK/V, ropeFrequencyBase, batchSize

    OllamaModelManager     — Modelfile generation + POST /api/create; force-unload via keep_alive:0
                             canReloadAtRuntime = true
                             supportedLoadParams: contextLength, gpuLayers, cpuThreads,
                                                  ropeFrequencyBase, batchSize, useMmap, useMlock

    JanModelManager        — POST /v1/models/stop → edit model.json → POST /v1/models/start
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

    VLLMModelManager       — python -m vllm.entrypoints.openai.api_server CLI (restart only)
                             canReloadAtRuntime = false
                             supportedLoadParams: contextLength, gpuLayers, ropeFrequencyBase,
                                                  batchSize, cacheTypeK

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

### Capability Matrix

| Provider | Runtime Reload | Context Length | GPU Layers | Flash Attn | KV Cache Type | Rope Base | mmap/mlock |
|---|---|---|---|---|---|---|---|
| LM Studio | ✅ REST + CLI | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Ollama | ✅ Modelfile | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| Jan.ai | ✅ model.json | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| LocalAI | ❌ restart | ✅ | ✅ | ⚠️ | ⚠️ | ✅ | ✅ |
| Mistral.rs | ❌ restart | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| vLLM | ❌ restart | ✅ | ✅ | N/A | ✅ kv-cache-dtype | ✅ | N/A |

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
  NullModelManager.swift

Merlin/Views/Settings/
  ModelControlView.swift            — ModelControlView + ModelControlSectionView + RestartInstructionsSheet
```

---

## Cross-Provider Calibration [v8]

### Design Decision: Closures over Protocol Coupling

`CalibrationRunner` takes `(String) async throws -> String` closures for local and reference
providers rather than `any LLMProvider` directly. This keeps the calibration engine decoupled
from the provider abstraction layer and makes it trivially testable with stubs.

### Calibration Flow

```
User types /calibrate
        │
        ▼
CalibrationCoordinator.begin()
  → CalibrationSheet.pickProvider([remoteProviderIDs])
        │
        ▼  user selects reference + taps Start
CalibrationCoordinator.start(referenceProviderID:)
  → builds localClosure    from appState.provider(for: localProviderID)
  → builds referenceClosure from appState.provider(for: referenceProviderID)
  → builds scorerClosure    from appState.criticEngine.score(prompt:response:)
        │
        ▼
CalibrationRunner.run(suite: .default)           ← TaskGroup: all 18 prompts in parallel
  for each prompt:
    async let local     = localClosure(prompt)
    async let reference = referenceClosure(prompt)
    async let localScore     = scorer(prompt, local)
    async let referenceScore = scorer(prompt, reference)
  → [CalibrationResponse]  (sorted by prompt.id)
        │
        ▼
CalibrationAdvisor.analyze(responses:localModelID:localProviderID:)
  checks:
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
      advisory list with suggested values
      "Apply All Suggestions" → applyAdvisory() for each advisory
                                (runtime reload or restart instructions — same path as v7)
```

### Prompt Battery [v8]

| ID | Category | Signal targeted |
|---|---|---|
| r1–r5 | Reasoning | variance detection, context gap |
| c1–c5 | Coding | instruction compliance, length |
| i1–i4 | Instruction Following | format compliance, truncation |
| s1–s4 | Summarization | repetition, coherence |

### File Layout

```
Merlin/Calibration/
  CalibrationTypes.swift       — CalibrationCategory, CalibrationPrompt, CalibrationResponse, CalibrationReport
  CalibrationSuite.swift       — CalibrationSuite + default 18-prompt battery
  CalibrationRunner.swift      — actor; parallel dispatch via TaskGroup
  CalibrationAdvisor.swift     — CalibrationAdvisor + CategoryScores; maps gaps to ParameterAdvisory
  CalibrationCoordinator.swift — @MainActor ObservableObject; CalibrationSheet enum; registerSkill()

Merlin/Views/Calibration/
  CalibrationProviderPickerView.swift — step 1: choose reference provider
  CalibrationProgressView.swift       — step 2: live progress bar
  CalibrationReportView.swift         — step 3: scores, breakdown, apply-all
```

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

**`OpenAICompatibleProvider`** [v1] — single class covering all OpenAI-compatible endpoints. Parameterised by `baseURL`, `apiKey` (nil = no auth header for local providers), and `model`. Handles SSE via `SSEParser`. Used for: DeepSeek, OpenAI, Qwen, OpenRouter, Ollama, Jan.ai, LocalAI, Mistral.rs, vLLM, LM Studio.

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
    var baseURL: String          // user-configurable; local providers default to localhost
    var model: String            // model ID sent in requests
    var isEnabled: Bool
    var isLocal: Bool            // skip key requirement; probe for availability at launch
    var supportsThinking: Bool   // guards ThinkingConfig injection
    var supportsVision: Bool     // used by vision routing in AgenticEngine
    var kind: ProviderKind
}
```

### ProviderRegistry [v1]

`ProviderRegistry` is a `@MainActor ObservableObject` that owns all provider configuration. Config persists to `~/Library/Application Support/Merlin/providers.json`. API keys are in Keychain, one item per provider (`com.merlin.provider.<id> / api-key`).

```swift
@MainActor
final class ProviderRegistry: ObservableObject {
    @Published var providers: [ProviderConfig]        // all nine + LM Studio
    @Published var activeProviderID: String
    @Published var availabilityByID: [String: Bool]   // live probe results for local providers

    func setAPIKey(_ key: String, for id: String) throws
    func readAPIKey(for id: String) -> String?
    func makeLLMProvider(for config: ProviderConfig) -> any LLMProvider
    func probeLocalProviders() async                  // fires at app launch
    var primaryProvider: any LLMProvider              // active provider as LLMProvider
    var visionProvider: any LLMProvider               // first local vision-capable provider
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
| Jan.ai | OAI-compat | `localhost:1337/v1` | Yes | No | No | No |
| LocalAI | OAI-compat | `localhost:8080/v1` | Yes | No | No | No |
| Mistral.rs | OAI-compat | `localhost:1234/v1` | Yes | No | No | No |
| vLLM | OAI-compat | `localhost:8000/v1` | Yes | No | No | No |

All base URLs are user-configurable in `ProviderSettingsView`. LM Studio and Mistral.rs share the same default port — enable at most one at a time unless the port is overridden.

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
├── GUI screenshot task?   → registry.visionProvider (first local vision-capable)
└── All other tasks        → registry.primaryProvider (user-selected active provider)
```

The pro/execute split is retired. One active provider per session. A skill's `model` frontmatter field overrides the active provider for that skill's turn. [v2]

---

## Session Manager [v2]

### Multi-Window Model

Each app window is scoped to exactly one project root. Windows are independent — they do not share session state, `SessionManager` instances, or layout. Opening a second project opens a second window.

```
File > Open Project…  (or drag a folder onto the Dock icon)
→  openWindow(value: ProjectRef(path: "/Users/jon/Projects/foo"))
→  new NSWindow with its own SessionManager + WorkspaceView
```

The entry point uses `WindowGroup(for: ProjectRef.self)` so macOS handles window restoration automatically. `ProjectRef` is a `Codable`, `Hashable` struct wrapping a resolved absolute path.

```swift
struct ProjectRef: Codable, Hashable, Transferable {
    var path: String          // absolute, resolved
    var displayName: String   // last path component
}
```

On launch with no existing windows, a `ProjectPickerView` is shown (recent projects list + Open button). Once a project is chosen, the workspace window opens and the picker closes.

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

Persisted to `~/Library/Application Support/Merlin/auth.json`.

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

`SchedulerEngine` uses `BackgroundTasks` framework to fire recurring sessions. Config at `~/Library/Application Support/Merlin/schedules.json`.

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

On fire: opens a background session, runs the prompt to completion, posts a macOS notification with a summary. Scheduled sessions run in Plan mode by default.

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

**[v2] ChatView additions** — stop button (visible while `isSending`), `@` autocomplete file picker, attachment button, permission mode badge, model picker dropdown, scroll-lock: manual upward scroll pauses auto-scroll-to-bottom while streaming continues off-screen; auto-scroll resumes when user scrolls back within 40pt of the bottom.

**[v1] ToolLogView** — live stdout/stderr stream from running tools. Colour-coded by source.

**[v1] ScreenPreviewView** — last screenshot from `ui_screenshot`. On-demand only.

**[v1] AuthPopupView** — modal, non-dismissable via background click.

**[v1] ProviderHUD** — toolbar indicator showing active provider and thinking/tool state.

**[v1] FirstLaunchSetupView** — Keychain setup on first run. Calls `appState.reloadProviders(apiKey:)` after saving.

**[v2] ProjectPickerView** — shown at launch when no windows are open. Recent projects list (resolved paths, last-opened timestamp), Open button (triggers folder panel), clear-recents option. Selecting a project calls `openWindow(value: projectRef)` and dismisses the picker.

**[v2] SessionSidebar** — lists open sessions with title, model badge, activity indicator, permission mode badge. New session button.

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
│   ├── ProviderHUD.swift
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
| `WebKit` | WKWebView for preview pane | v2 |
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
    var id: String { get }                          // e.g. "software", "pcb", "construction"
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

The built-in `SoftwareDomain` conforms directly to `DomainPlugin` in Swift. All external domains (PCB, construction, etc.) arrive via `MCPDomainAdapter`.

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

Each slot maps to a configured provider in `AppSettings`. A slot with no distinct assignment falls through to the next available provider.

### Routing Priority Stack

```
1. Declarative override  — @role in message, or skill frontmatter `role: <slot>`
2. Structural routing    — engine infers role from task shape (image → vision, etc.)
3. Active provider       — unresolved slot uses the globally active provider
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

A silent eval pass runs using the `reason` slot:

```
Critic prompt: "Given task X and output Y, does the output satisfy the intent?
                If not, what specifically is wrong?"
```

- **Pass** → result shown to user (optional "verified by [model]" badge)
- **Fail** → correction injected as system message; worker re-runs (up to `max_critic_retries`)
- **Retries exhausted** → escalate to user or promote to stronger model

The inner loop (both stages) is collapsible in a "reasoning trace" block. The user sees the final output only.

**Critical constraint:** The reason slot must be assigned to a genuinely stronger model than the execute slot — typically a remote thinking model (Claude, Sonnet, etc.). A weak model cannot reliably catch its own class of errors. The settings UI must surface this constraint clearly.

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

## V5 — RAG Memory Extension

> **xcalibre-server Phase 18 is shipped** — migration `0028_memory_chunks.sql`, `POST /api/v1/memory`, `DELETE /api/v1/memory/:id`, and unified `GET /api/v1/search/chunks?source=all` are all live. Merlin-side implementation can proceed.

Extends xcalibre-server as a persistent memory store for Merlin. Local LLMs have limited context windows; precision-retrieved prior memory lets a 4k context window punch above its weight.

### Memory Types

| Type | Content | Write trigger | Granularity |
|---|---|---|---|
| Episodic | Session summary — what was worked on, decisions made, outcome | Session end / `MemoryEngine` idle fire | One chunk per session |
| Factual | Discrete extracted facts — "user prefers X", "project uses Y" | Post-session background pass | One chunk per fact |

Excluded from xcalibre memory: recent turns (stay in-context as sliding window), procedural/how-to (already in book content), tool outputs and file contents (too large, too ephemeral).

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

Memory chunks are scoped to `project_path` — a session in project A does not bleed into project B.

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
| Bad data prevention | Auto-filtering rejects aborted/error sessions; Accept+Edit lets user clean partial errors; Decline+correction converts errors to DPO signal |

# Merlin — Developer Manual

**Version 2.2.5**

This manual covers the complete architecture, development workflow, and code organisation of Merlin. It is intended for contributors working on the codebase. Code references use the format `File.swift:ClassName.method()` matching the comments embedded throughout the source.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Repository Layout](#repository-layout)
3. [Build System](#build-system)
4. [Development Workflow — TDD Tasks](#development-workflow--tdd- tasks)
5. [Task Sheet Format](#task-sheet-format)
6. [Core Architecture](#core-architecture)
7. [Engine — The Agentic Loop](#engine--the-agentic-loop)
8. [Supervisor-Worker Engine](#supervisor-worker-engine)
9. [LoRA Training Pipeline](#lora-training-pipeline)
10. [DisciplineEngine (v2.2)](#disciplineengine-v22)
11. [Tool System](#tool-system)
12. [Provider System](#provider-system)
13. [Auth & Permission System](#auth--permission-system)
14. [Session & State Management](#session--state-management)
15. [Hook System](#hook-system)
16. [Skill System](#skill-system)
17. [Memory System](#memory-system)
18. [MCP Integration](#mcp-integration)
19. [Subagent System](#subagent-system)
20. [UI Architecture](#ui-architecture)
21. [Configuration System](#configuration-system)
22. [Connectors](#connectors)
23. [Testing Strategy](#testing-strategy)
24. [Code Map](#code-map)
25. [Adding a New Tool](#adding-a-new-tool)
26. [Adding a New Provider](#adding-a-new-provider)
27. [Writing a Skill](#writing-a-skill)
28. [Non-Negotiable Rules](#non-negotiable-rules)

---

## Project Overview

Merlin is a **non-sandboxed macOS SwiftUI application** (macOS 14+, Swift 5.10) that wraps multiple LLM providers behind an agentic loop with a full tool registry. It is a developer-facing tool — not a general consumer product.

Key design axioms:

- **Local-first.** All state, keys, and memories live on the user's machine.
- **No third-party Swift packages** in production targets. All functionality is hand-written.
- **OpenAI function-calling wire format** for all tool schemas. The only translation layer is inside `AnthropicProvider.swift`.
- **`SWIFT_STRICT_CONCURRENCY=complete`.** Zero data-race warnings at all times.
- **TDD always.** Implementation never precedes a failing test commit.

---

## Repository Layout

```
merlin/
├── Merlin/                   # Main application target
│   ├── Agents/               # Subagent definitions, registry, engines
│   ├── App/                  # Entry point, AppState, Commands, FocusedValues
│   ├── Auth/                 # AuthGate, AuthMemory, PatternMatcher
│   ├── Automations/          # Legacy/internal ThreadAutomation types
│   ├── Config/               # AppSettings, TOMLParser, HookConfig, AppearanceSettings
│   ├── Connectors/           # GitHub, Linear, Slack connectors; PRMonitor
│   ├── Docs/                 # Bundled UserGuide.md and DeveloperManual.md (this file)
│   ├── Engine/               # AgenticEngine, ContextManager, ToolRouter, DiffEngine, etc.
│   ├── Hooks/                # HookEngine, HookDecision
│   ├── Keychain/             # KeychainManager
│   ├── MCP/                  # MCPBridge, MCPConfig, MCPToolDefinition
│   ├── Memories/             # MemoryEngine, MemoryEntry
│   ├── Notifications/        # NotificationEngine
│   ├── Providers/            # LLMProvider protocol + all provider implementations
│   ├── RAG/                  # XcalibreClient, RAGTools
│   ├── Scheduler/            # ScheduledTask, SchedulerEngine
│   ├── Sessions/             # LiveSession, Session, SessionManager, SessionStore
│   ├── Skills/               # Skill, SkillFrontmatter, SkillsRegistry
│   │   └── Builtin/          # Built-in .skill.md files (excluded from Xcode source)
│   ├── System/               # KeepAwakeManager
│   ├── Toolbar/              # ToolbarAction, ToolbarActionStore
│   ├── Tools/                # All tool implementations + ToolDefinitions + ToolRegistry
│   │   └── WebSearch/        # BraveSearchClient, WebSearchTool
│   ├── UI/                   # Non-View components: SubagentBlock, MemoryReview, Settings, Sidebar
│   ├── Views/                # All SwiftUI Views
│   ├── Voice/                # VoiceDictationEngine
│   └── Windows/             # FloatingWindowManager, WorkspaceLayoutManager, HelpWindowView
├── MerlinTests/              # Unit and integration tests
│   └── Unit/
├── MerlinLiveTests/          # Real-provider API tests (manual scheme)
├── MerlinE2ETests/           # Full agentic loop + UI tests (manual scheme)
├── TestHelpers/              # MockProvider, NullAuthPresenter, EngineFactory (shared)
│   └── SemanticFaults/       # Fault injection doubles: stale retrieval, truncation, empty tools, context drop
├── TestTargetApp/            # Minimal target app for AX/UI tests
├── tasks/                   # Task sheet Markdown files
├── spec.md           # High-level design document
├── llm.md                    # Provider wire format details
├── project.yml               # XcodeGen project definition
└── constitution.md                 # Session instructions for AI coding assistants
```

---

## Build System

The project file (`Merlin.xcodeproj`) is **generated** from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen). Never edit the `.xcodeproj` directly.

After modifying `project.yml`:
```bash
xcodegen generate
```

### Build Verification Commands

```bash
# Build for testing (unit tests, no network)
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Run unit tests
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Build the app (not for testing)
xcodebuild -scheme Merlin build \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

### Running the App

```bash
open ~/Documents/localProject/merlin/build/Debug/Merlin.app

# Kill and relaunch:
pkill -x Merlin 2>/dev/null; sleep 1
open ~/Documents/localProject/merlin/build/Debug/Merlin.app
```

The app requires **macOS 14+** and runs **non-sandboxed** (entitlement `com.apple.security.app-sandbox = false`).

---

## Development Workflow — TDD Tasks

Every feature is built in two committed  tasks:

### Task NNa — Tests (failing)

1. Read `tasks/PASTE-LIST.md` to find the next unused task number
2. Write the `tasks/task-NNa-<name>-tests.md` sheet (see format below)
3. Write the test file(s) — **implementation classes must not exist yet**
4. Run `xcodebuild` and confirm `BUILD FAILED` with errors naming the missing symbols
5. Commit: `Task NNa — <TestNames> (failing)`

### Task NNb — Implementation

1. Write the `tasks/task-NNb-<name>.md` sheet
2. Implement the production code
3. Run `xcodebuild` and confirm `BUILD SUCCEEDED` with all NNa tests passing
4. Commit: `Task NNb — <FeatureName>`

**Commits are mandatory after every task.** Never batch  tasks into one commit. Never amend a task commit.

### Git Commit Protocol

```bash
git add <specific files — never git add -A>
git commit -m "Task NNx — <Description>"
```

---

## Task Sheet Format

### NNa sheet (`tasks/task-NNa-<name>-tests.md`)

```markdown
# Task NNa — <Feature> Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed.
SWIFT_STRICT_CONCURRENCY=complete. Working dir: ~/Documents/localProject/merlin
Task (N-1)b complete: <what was last implemented>.

New surface introduced in task NNb:
  - TypeName.methodName() — short description

TDD coverage:
  File 1 — TestFileName: what it tests

---

## Write to: MerlinTests/Unit/TestFile.swift
<full file content>

---

## Verify
xcodebuild -scheme MerlinTests build-for-testing ...
# Expected: BUILD FAILED (missing symbols)

## Commit
git add MerlinTests/Unit/TestFile.swift
git commit -m "Task NNa — TestName (failing)"
```

### NNb sheet (`tasks/task-NNb-<name>.md`)

```markdown
# Task NNb — <Feature> Implementation

## Context
<same as NNa, updated>
Task NNa complete: failing tests in place.

---

## Write to / Edit: SourceFile.swift
<full file content or diff>

---

## Verify
xcodebuild -scheme MerlinTests test ...
# Expected: BUILD SUCCEEDED, all NNa tests pass

## Commit
git add <source files>
git commit -m "Task NNb — FeatureName"
```

---

## Core Architecture

### Data Flow Overview

```
User input
    │
    ▼
ChatView (SwiftUI)
    │  sends via AppState
    ▼
AgenticEngine.send()          ← [AgenticEngine.swift]
    │  builds request
    ▼
LLMProvider.complete()        ← [Providers/*.swift]
    │  streams chunks
    ▼
AgenticEngine.runLoop()       ← parse tool calls
    │
    ├─→ HookEngine.runPreToolUse()   ← [HookEngine.swift]
    │         ↓ allow/deny
    ├─→ ToolRouter.dispatch()        ← [ToolRouter.swift]
    │         ↓ auth check + execute
    │         ↓ result
    └─→ ContextManager.append()     ← [ContextManager.swift]
            ↓ maintains message history
        AgenticEngine (next turn)
```

### Concurrency Model

- All `ObservableObject` subclasses and SwiftUI views are `@MainActor`
- Pure computation and I/O actors are `actor` (e.g. `StagingBuffer`, `HookEngine`, `ToolRegistry`, `MCPBridge`)
- Parallel tool calls use `async let` / `TaskGroup`
- `SWIFT_STRICT_CONCURRENCY=complete` — the compiler enforces data-race safety at all times

---

## Engine — The Agentic Loop

**File:** `Merlin/Engine/AgenticEngine.swift`

`AgenticEngine` is the central orchestrator. It is `@MainActor` and owns:

- `proProvider` — the primary LLM (high-capability, used for reasoning)
- `flashProvider` — the fast LLM (used for quick tasks and subagents)
- `visionProvider` — the vision-capable LLM
- `contextManager: ContextManager` — message history
- `toolRouter: ToolRouter` — tool dispatch

### Entry Points

| Method | Purpose |
|---|---|
| `send(userMessage:)` | Standard user turn. Returns `AsyncStream<AgentEvent>`. |
| `invokeSkill(_:arguments:)` | Invokes a skill. Fork-context skills run without modifying main history. |
| `submitDiffComments(changeIDs:)` | Sends inline diff comments back as a new user turn. |
| `cancel()` | Cancels the running turn immediately. |

### The Run Loop (`runLoop`)

`runLoop` is the recursive core. At each depth:

1. Builds a `CompletionRequest` from context, system prompt (constitution.md + memories), tools, and optional vision attachment
2. Calls `proProvider.complete()` and streams events
3. On `toolCallStarted` — fires `HookEngine.runPreToolUse()`, then dispatches via `ToolRouter`
4. On `toolCallResult` — optionally runs `HookEngine.runPostToolUse()` to let hooks rewrite results
5. After all tool results are appended to context — checks `HookEngine.runStop()` to determine whether to continue
6. Recurses at `depth + 1` (max depth prevents infinite loops)

### AgentEvent

All outputs are yielded as `AgentEvent` values:

```swift
enum AgentEvent {
    case text(String)                   // streamed text delta
    case thinking(String)               // extended thinking block
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case subagentStarted(id:agentName:)
    case subagentUpdate(id:event:)
    case ragSources([RAGChunk])         // emitted after RAG search; shown in Sources footer
    case groundingReport(GroundingReport) // emitted after RAG search every turn (v9)
    case systemNote(String)
    case error(Error)
}
```

### ContextManager

**File:** `Merlin/Engine/ContextManager.swift`

Manages the `[Message]` array sent to the provider on each turn.

- Token estimation: `utf8.count / 3.5` — cheap heuristic, no tokeniser dependency
- Compaction threshold: 800,000 estimated tokens. When exceeded, old tool result messages are collapsed to a summary line to keep the context window from overflowing
- After compaction, recently-invoked skill bodies are re-injected so the model retains them
- `forceCompaction()` is exposed for test use

---

## Supervisor-Worker Engine

**Files:** `Merlin/Engine/AgenticEngine.swift`, `Merlin/Engine/CriticEngine.swift`, `Merlin/Engine/PlannerEngine.swift`, `Merlin/Engine/ModelPerformanceTracker.swift`, `Merlin/Engine/AgentSlot.swift`, `Merlin/MCP/DomainRegistry.swift`, `Merlin/MCP/DomainPlugin.swift`, `Merlin/MCP/SoftwareDomain.swift`

### AgentSlot

**File:** `Merlin/Engine/AgentSlot.swift`

Four routing destinations:

```swift
enum AgentSlot: String, CaseIterable, Codable, Sendable {
    case execute, reason, orchestrate, vision
}
```

`AgenticEngine.provider(for:)` resolves the LLM provider for a slot. The runtime fallback layers are:

- `execute` → `loraProvider` when loaded, otherwise the active provider assignment
- `reason` → active provider when not explicitly assigned
- `orchestrate` → `reason`, then active provider
- `vision` → active provider unless a dedicated vision-capable provider is assigned

### DomainRegistry / DomainPlugin

**Files:** `Merlin/MCP/DomainRegistry.swift`, `Merlin/MCP/DomainPlugin.swift`, `Merlin/MCP/SoftwareDomain.swift`

`DomainRegistry.shared.activeDomain()` returns the active `DomainPlugin` instance — preferring the first non-software domain when one is registered. Domains supply:
- `verificationBackend` — used by `CriticEngine` stage 1 (e.g. `xcodebuild` in `SoftwareDomain`)
- `systemPromptAddendum` — injected per-slot into the system prompt
- `taskTypes: [DomainTaskType]` — performance tracking buckets

`taskTypes()` mirrors this preference: when a non-software domain is active it returns only that domain's task types. Software task types are returned only when software is the sole active domain. Use the stateless helpers `activeDomain(ids:)` and `taskTypes(ids:)` when resolving task types for a specific session rather than querying the shared registry's mutable state.

The `addendumHash` (8-char SHA256 prefix of the addendum string) is stored on every `OutcomeRecord` to attribute performance to the specific addendum variant that produced it.

### CriticEngine

**File:** `Merlin/Engine/CriticEngine.swift`

Evaluates model output after a turn completes without tool calls. Two stages:

1. **Stage 1** — domain verification backend. Runs the domain's verification command (e.g. `xcodebuild test`) and returns pass/fail.
2. **Stage 2** — reason-slot LLM scoring. Sends the output to the reason provider with a scoring rubric and returns a `stage2Score` in 0.0–1.0.

Returns `CriticResult`: `.pass`, `.fail(reason:)`, or `.skipped`.

`AgenticEngine.lastCriticVerdict` stores the most recent verdict. It is reset to `nil` at the start of every `runLoop` invocation. When the verdict is `.fail`, the episodic memory write at the end of the turn is suppressed.

### PlannerEngine

**File:** `Merlin/Engine/PlannerEngine.swift`

Classifies incoming messages into `ComplexityTier` (.routine / .standard / .high-stakes) and optionally decomposes high-complexity tasks into a step list.

`ClassifierResult` carries:
- `needsPlanning: Bool` — whether to run the planning pass
- `complexity: ComplexityTier` — which slot handles the work
- `reason: String` — diagnostic string for logging

`AgenticEngine` accepts a `classifierOverride: (any PlannerEngineProtocol)?` for test injection.

### ModelPerformanceTracker

**File:** `Merlin/Engine/ModelPerformanceTracker.swift`

`actor` that accumulates `OutcomeRecord` values and updates `ModelPerformanceProfile` entries with exponential-decay scoring (factor 0.9). Calibrated at 30 samples — `successRate(for:taskType:)` returns `nil` until then.

`record(modelID:taskType:signals:prompt:response:)` is the primary write path. `AgenticEngine` passes `userMessage` and `lastResponseText` (the full assistant text from the last response that had no tool calls). The legacy 3-argument overload marks records with `legacyTrainingRecord: true`.

`exportTrainingData(minScore:)` returns records where `score >= minScore` AND (`legacyTrainingRecord == true` OR both `prompt` and `response` are non-empty). This ensures only records with actual training text are exported to the LoRA pipeline.

Profile files: `~/.merlin/performance/<model-id>.json`  
Training data: `~/.merlin/performance/records-<model-id>.json`

---

## LoRA Training Pipeline

**Files:** `Merlin/Engine/LoRATrainer.swift`, `Merlin/Engine/LoRACoordinator.swift`

### LoRATrainer

**File:** `Merlin/Engine/LoRATrainer.swift`

`actor` responsible for exporting training data and invoking `mlx_lm.lora`.

`exportJSONL(_ records: [OutcomeRecord], to url: URL)` writes one JSON line per record in MLX-LM chat format:
```json
{"messages":[{"role":"user","content":"..."},{"role":"assistant","content":"..."}]}
```
Records with empty `prompt` or `response` are silently skipped. The method is `nonisolated` — safe to call from tests without actor isolation.

`train(records:baseModel:adapterOutputPath:iterations:)` exports a temp JSONL, ensures the adapter directory exists, assembles the `python -m mlx_lm.lora --train` command string, and delegates execution to `ShellRunnerProtocol`. Returns `LoRATrainingResult`.

### ShellRunnerProtocol

**File:** `Merlin/Engine/LoRATrainer.swift`

```swift
protocol ShellRunnerProtocol: Sendable {
    func run(command: String) async -> ShellRunResult
}
```

`ProcessShellRunner` is the production implementation — runs via `/bin/zsh -c`. Tests inject a stub runner (e.g. `CapturingShellRunner`) to avoid executing real shell commands. This is the standard test-injection pattern used across the project.

### LoRACoordinator

**File:** `Merlin/Engine/LoRACoordinator.swift`

`actor` that sits between `AgenticEngine` and `LoRATrainer`. Responsibilities:
- Threshold gate: only fires training when `exportTrainingData(minScore: 0.8)` returns `>= minSamples` records
- Concurrency guard: `isTraining` prevents overlapping training runs
- Result storage: `lastResult: LoRATrainingResult?` for display in `LoRASettingsSection`

Called from `AgenticEngine.runLoop()` after `performanceTracker.record()` when both `loraEnabled` and `loraAutoTrain` are true.

### loraProvider routing

`AgenticEngine.loraProvider: (any LLMProvider)?` holds an `OpenAICompatibleProvider` pointing at `AppSettings.loraServerURL`. When set, `provider(for: .execute)` returns `loraProvider` instead of `proProvider`. The reason slot, critic slot, and orchestrate slot are never affected by the LoRA provider — they always use the unmodified base provider assignment.

`AppState` wires `loraProvider` via Combine: subscribes to changes in `loraEnabled`, `loraAutoLoad`, `loraAdapterPath`, and `loraServerURL`. When all conditions are met (enabled + autoLoad + adapter file exists), it constructs the `loraProvider` and assigns it to `engine.loraProvider`.

### LoRASettingsSection

**File:** `Merlin/Views/Settings/LoRASettingsSection.swift`

Settings UI with: master toggle (`loraEnabled`), sub-group for auto-train options (hidden when master is off), base model field, adapter path field with Browse button, auto-load toggle, server URL field, status row showing `loraCoordinator.isTraining` and `loraCoordinator.lastResult`.

---

## DisciplineEngine (v2.2)

**Files:** `Merlin/Engine/DisciplineEngine.swift` and associated scanner actors in `Merlin/Engine/`.

### Overview

`DisciplineEngine` is a top-level `actor`, peer to `AgenticEngine`, `MemoryEngine`, and `PlannerEngine`. It coordinates five scanners - the task scanner, manual-coverage scanner, doc-reference graph, why-comment scanner, and prose-readability checker - owns the pending-attention queue, and integrates with the hook engine. It runs after every turn (`Stop` hook) and injects findings at session start (`SessionStart` hook).

```swift
actor DisciplineEngine {
    init(
        adapter: ProjectAdapter,
        taskScanner: TaskScanner,
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

Circuit breaker: three consecutive scan failures disable the engine for the session and emit `discipline.disabled` rather than blocking the user.

### Adapter system

Per-language config consumed by all scanners. Declared in `~/.merlin/adapters/<name>.toml`. Key fields: `build_command`, `test_command`, `versioning_file`, `versioning_field`, `[why_comment_triggers]` patterns, `[manual_coverage] surface_patterns`. Seed adapters: `swift-xcode.toml`, `rust-cargo.toml`.

Per-project config lives in `<project>/.merlin/project.toml`: adapter selection, active discipline layers, `manual_coverage_baseline`, and optional task-scan baseline settings.

### Scanners

**`TaskScanner`** — reads `tasks/` NNb files, extracts declared surfaces from the "New surface introduced in task NNb:" block, greps against the source tree. Four drift severities: `green` (present, unchanged), `yellow` (present, signature changed), `red` (absent — deleted without addendum), `orange` (code surface with no task declaration). Projects with historical task archives can set `task_scan_min_number` to scan only the active baseline forward, and `task_scan_public_undeclared = false` to avoid retroactive orange findings for public symbols that predate the baseline.

**`ManualCoverageScanner`** — enumerates user-facing surfaces via adapter regex patterns, cross-checks against `<!-- covers: ... -->` markers in doc files. Gaps and stale references become findings. Surfaces escape the requirement via `// manual: not-user-facing — <rationale>` (logged to override audit).

**`DocReferenceGraph`** — greps doc files for symbol-shaped strings (camelCase, PascalCase, snake_case), cross-checks against the code symbol index. Renamed or removed symbols trigger findings on every doc that still references the old name.

**`WhyCommentScanner`** — for each adapter-declared trigger pattern (e.g. `try?`, `@unchecked Sendable`, `.unwrap()`), checks for an explanatory comment within 3 lines. Missing → finding. Override: `// rationale-not-needed: <reason>` (logged).

**`ProseReadabilityChecker`** — calls `vale` with the Merlin style folder. Per-file grade targets from the adapter `doc_target_grade` table. Default targets: `user-manual.md` grade 9, `developer-guide.md` grade 9, `spec.md` grade 11.

### PendingAttention queue

Persisted at `<project>/.merlin/pending.json`. Idempotency key prevents duplicates on re-scan.

```swift
struct Finding: Sendable, Identifiable, Codable {
    let id: UUID
    let category: FindingCategory   // taskDrift | manualCoverageGap | docStaleReference
                                    // | whyCommentMissing | proseReadabilityFail
                                    // | overrideAuditAccumulation
    let severity: Severity          // block | nudge | silent
    let summary: String
    let detail: String
    let suggestedAction: String?
    let createdAt: Date
    let lastSeenAt: Date
}
```

`SessionStart` hook injects the top 3 findings by severity as a system reminder.

### Override audit

Every override appended to `<project>/.merlin/override-log.jsonl`. Weekly review fires `discipline.override-audit` telemetry with per-category counts. High counts surface a nudge finding — the engine watches its own escape valves for erosion.

### Hook integration

| Hook | Trigger | Action |
|---|---|---|
| `SessionStart` | Session opens | Inject top-N findings from `pending.json` as system reminder |
| `Stop` | After every Claude turn | `DisciplineEngine.scan(diff:)` against changed files |
| `UserPromptSubmit` | Before user message | Flag if prompt looks like a feature request without a task file |
| `PostCommit` | After git commit | Run `TaskScanner` if commit touched source files |
| `PrePush` | Before git push | Verify version-tag consistency |

### Project skills

Five `~/.merlin/skills/project-*/SKILL.md` files implement the user-facing layer.

| Skill | Tasks | Concern |
|---|---|---|
| `project:init` | 259a/b | Scaffold new project; install hooks |
| `project:task` | 260a/b | Build NNa/NNb task pair |
| `project:revise` | 261a/b | Interactive finding review |
| `project:release` | 262a/b | Consolidated release gate |
| `project:adopt` | 263a/b | Adopt existing project; record baseline |

Task documents are also part of the SDD contract. `project:task` writes `## Traceability`
and `## Behavior` blocks into both the test and implementation task sheets. The
traceability block links to `vision.md` and `spec.md`; the behavior block uses EARS
statements. `SDDTraceabilityScanner` runs inside `DisciplineEngine.scan` and emits
`.sddTraceability` findings for missing blocks, missing `SHALL` behavior, or dangling
vision/spec links.

### Decaying coverage baseline

`/project:adopt` records the gap count at adoption as `manual_coverage_baseline`. The release gate then requires: (a) no new uncovered surfaces in the current release diff, and (b) the baseline decreases by at least N (default 10) per release. The gap closes within approximately `baseline / 10` releases while forward work continues in parallel.

### Telemetry events

`discipline.scan.start`, `discipline.scan.complete`, `discipline.scan.error`, `discipline.disabled`, `discipline.finding.added`, `discipline.finding.dismissed`, `discipline.finding.resolved`, `discipline.override.recorded`, `discipline.override-audit`, `discipline.release-gate.start`, `discipline.release-gate.fail`, `discipline.release-gate.pass`, `discipline.manual-coverage.baseline`. All go through the existing `TelemetryEmitter`.

---

## Tool System

### ToolRouter

**File:** `Merlin/Engine/ToolRouter.swift`

`ToolRouter` dispatches tool calls from the engine to registered handlers. It is `@MainActor`.

**Dispatch pipeline for each call:**

1. Check `shouldStage()` — if `stagingBuffer` is set and the tool is a file-write and permission mode is Ask or Plan → stage instead of executing
2. Extract the primary argument (path/command) for auth checking
3. Skip auth for file-write tools in `autoAccept` mode
4. Call `authGate.check()` — may suspend to present the auth popup
5. Look up the handler (local registry first, then MCP)
6. Execute. On failure, retry once after a 1-second delay
7. Return `ToolResult`

All tool calls in a single LLM response are dispatched in **parallel** via `TaskGroup`.

### ToolRegistry

**File:** `Merlin/Tools/ToolRegistry.swift`

A runtime actor holding `ToolDefinition` schemas. Queried by the engine to build the tools array sent to the provider. Built-in tools register via `ToolRegistry.shared.registerBuiltins()` at app launch. MCP tools and any future conditional tools register/unregister at runtime.

**Do not query `ToolDefinitions.all` directly** — always use `ToolRegistry.shared`.

### Tool Definitions

**File:** `Merlin/Tools/ToolDefinitions.swift`

Static JSON-schema definitions for all built-in tools in OpenAI function-calling format. Each definition has `name`, `description`, and a `parameters` JSON Schema object.

### ToolRegistration

**File:** `Merlin/App/ToolRegistration.swift`

Called once at `AppState.init()`. Connects each tool name to its Swift handler function.

### Built-in Tool Implementations

| File | Tools |
|---|---|
| `FileSystemTools.swift` | read_file, write_file, create_file, delete_file, list_directory, move_file, search_files |
| `ShellTool.swift` | run_shell (streaming via `AsyncThrowingStream`) |
| `XcodeTools.swift` | xcode_build, xcode_test, xcode_clean, xcode_open_simulator |
| `AppControlTools.swift` | launch_app, quit_app, focus_app, list_running_apps |
| `AXInspectorTool.swift` | ax_inspect |
| `CGEventTool.swift` | cg_event |
| `ScreenCaptureTool.swift` | capture_screen |
| `VisionQueryTool.swift` | vision_query |
| `WebSearch/WebSearchTool.swift` | web_search |
| `RAG/RAGTools.swift` | rag_search, rag_list_books |
| `Agents/SpawnAgentTool.swift` | spawn_agent |

### Staging Buffer

**File:** `Merlin/Engine/StagingBuffer.swift`

When `ToolRouter.shouldStage()` returns true, file-mutating calls are captured as `StagedChange` structs instead of being applied to disk. The `DiffPane` view renders pending changes and lets the user accept or reject each one.

```swift
// Operations
actor StagingBuffer {
    func stage(_ change: StagedChange)      // capture a proposed file change
    func accept(_ id: UUID) async throws    // apply to disk
    func reject(_ id: UUID)                 // discard
    func acceptAll() async throws
    func rejectAll()
    func commentsAsAgentMessage(_ ids:) -> String  // format inline comments for re-submission
}
```

---

## Provider System

**Files:** `Merlin/Providers/`

### LLMProvider Protocol

```swift
protocol LLMProvider: AnyObject, Sendable {
    var id: String { get }
    func complete(_ request: CompletionRequest) -> AsyncThrowingStream<ProviderEvent, Error>
}
```

All providers stream `ProviderEvent` values. The engine collects these into `AgentEvent` for the UI.

### Request / Response Types

Defined in `LLMProvider.swift`:

- `Message` — role + content (text or [ContentPart])
- `ContentPart` — `.text(String)` or `.imageURL(String)` (base64 data URL for vision)
- `CompletionRequest` — messages, tools, system prompt, max tokens, thinking enabled flag
- `ToolCall` — id + function (name + arguments JSON string)
- `ToolResult` — toolCallId + content + isError flag

### Provider Implementations

| File | Notes |
|---|---|
| `OpenAICompatibleProvider.swift` | Handles all OpenAI-compatible endpoints (OpenAI, DeepSeek, Qwen, Ollama, LM Studio, etc.) |
| `AnthropicProvider.swift` | Translates to Anthropic's native format. SSE parsing in `AnthropicSSEParser.swift`. |
| `DeepSeekProvider.swift` | Thin wrapper over OpenAICompatibleProvider with reasoning effort headers. |
| `LocalModelManager/*.swift` | Per-backend local manager layer for model discovery/reload/restart guidance (includes `LlamaCppModelManager`). |

### ProviderRegistry

**File:** `Merlin/Providers/ProviderConfig.swift`

`@MainActor ObservableObject` that holds the list of `ProviderConfig` structs, the `activeProviderID`, and keychain API-key accessors. Persists to `~/Library/Application Support/Merlin/providers.json`.

`makeLLMProvider(for:)` is the factory that converts a `ProviderConfig` to a concrete `LLMProvider` instance.

Current default inventory is 12 providers, including the disabled-by-default `llamacpp` entry:

- `id: "llamacpp"`
- `displayName: "llama.cpp"`
- `baseURL: "http://localhost:8081/v1"`
- `localModelManagerID: "llamacpp"`

Virtual provider IDs (`backendID:modelID`) are first-class for slot assignment and runtime routing. For example, selecting `llamacpp:qwen3-coder` creates an OpenAI-compatible runtime provider that keeps the backend URL and targets that exact model ID.

`LlamaCppModelManager` adds router-mode local manager behavior:

- Router catalog discovery: `GET /models` with fallback `GET /v1/models`
- Runtime operations: `POST /models/load` and `POST /models/unload`
- The engine preflights local router-capable requests with `ensureModelLoaded(modelID:)`
  before dispatching the OpenAI-compatible completion request.
- Single-model fallback: when router endpoints are unavailable, runtime swap paths return restart instructions for one router-mode `llama-server` process on `127.0.0.1:8081` using the installed llama.cpp `--models-dir` and `--models-preset` flags.
- Supported load parameters are advertised for context length, GPU layers, CPU
  threads, flash attention, KV cache types, RoPE frequency base, batch size,
  mmap, and mlock.

---

## CAG (Cache-Augmented Generation)

Merlin ships CAG as a request policy for cache-stable prefixes.

### Core surfaces

- `CAGCachePolicy` (`Merlin/CAG/CachePolicy.swift`) controls request caching mode (`disabled` or `ephemeral`).
- `CAGToolOrdering` (`Merlin/CAG/CachePolicy.swift`) sorts tool schemas by name and deduplicates duplicate names while keeping the first original definition.
- `CAGCacheUsage` (`Merlin/CAG/CacheMetrics.swift`) stores read/create/uncached token usage and computes hit rate.
- `CAGCacheMetricsStore` (`Merlin/CAG/CacheMetrics.swift`) aggregates usage by provider ID.
- `CompletionRequest.cachePolicy` carries the policy from engine wiring to provider adapters.
- `CompletionRequest.systemPromptSegments` carries split cacheable/hot system blocks for providers that support block-level cache markers.
- `buildStablePrefix()` honors `[cag] pin_constitution` and includes files listed in `pinned_task_docs` when CAG is enabled.
- `buildCAGSystemPromptSegments()` keeps constitution.md in the hot system block when `pin_constitution = false`; the content remains in the request but outside Anthropic's cache-marked block.

### Provider behavior

- `AnthropicProvider` emits explicit prompt-cache markers (`cache_control`) and `anthropic-beta: prompt-caching-2024-07-31` for cacheable requests.
- `AnthropicProvider` emits a cache-marked system block for stable content and a separate unmarked block for hot system content.
- `AnthropicSSEParser` reads cache token usage fields from `usage` payloads and surfaces them as `CompletionChunk.cacheUsage`.
- OpenAI-compatible, DeepSeek, and local providers do not emit Anthropic-specific fields; CAG relies on stable prefix bytes and backend automatic cache/KV reuse when available.
- `ProviderSettingsView` displays read/create/uncached token counters and hit rate from `CAGCacheMetricsStore`.
- `CAGMetricsPane` provides the workspace panel for per-provider totals, refresh, and reset.

### Invariant

RAG/KAG enrichment remains hot suffix content and must stay outside the cacheable stable prefix.
Pinned CAG docs are bounded to regular files inside the current project, eight files total, 64 KiB per file.

---

## Auth & Permission System

### Provider Credential Storage

Provider keys are written through `KeychainManager`. Debug/dev-loop builds use
`~/.merlin/api-keys.json` with owner-only file permissions; Release builds use
macOS Keychain. `LocalOnlyFileGate` blocks tracked `api-keys.json`, `.env*`,
`secrets.json`, and `.merlin/api-keys.json` files during pre-push/release checks,
and CI repeats the same guard.

### AuthGate

**File:** `Merlin/Auth/AuthGate.swift`

Called by `ToolRouter` before every tool execution. Logic:

1. Check `AuthMemory` for an existing allow/deny pattern matching `(tool, argument)`
2. If no pattern found — call `AuthPresenter.requestDecision()` to surface the popup
3. Record the user's decision if they chose "Always"

### AuthMemory

**File:** `Merlin/Auth/AuthMemory.swift`

Stores `(tool, pattern, decision)` triples. Persists to a JSON file (path configured per-session to avoid test cross-contamination). The file is written atomically and immediately `chmod 0600` via `FileManager.setAttributes([.posixPermissions: 0o600])` — readable only by the owning user. Pattern matching is delegated to `PatternMatcher`.

### PatternMatcher

**File:** `Merlin/Auth/PatternMatcher.swift`

Converts glob patterns to `NSRegularExpression`. Supported wildcards:

- `*` — matches any string except `/`
- `**` — matches any string including `/`
- `~` — expands to `$HOME`

### PermissionMode

**File:** `Merlin/Engine/PermissionMode.swift`

Enum with three values: `.ask`, `.autoAccept`, `.plan`. Stored on both `AgenticEngine` and `ToolRouter`. When set on `LiveSession`, the `didSet` propagates to both.

---

## Session & State Management

### AppState

**File:** `Merlin/App/AppState.swift`

The top-level `@MainActor ObservableObject` for a single project session. Owns:

- `engine: AgenticEngine` — the agentic loop
- `registry: ProviderRegistry` — provider config and keys
- `authMemory: AuthMemory` — tool permission patterns
- `prMonitor: PRMonitor` — GitHub PR status watching
- `toolLogLines` — live tool call log
- `lastScreenshot` — most recent screen capture
- `contextUsage` — token usage tracker

`activeProviderID.didSet` keeps `registry.activeProviderID` in sync and calls `syncEngineProviders()` to rebuild the engine's provider instances.

### LiveSession

**File:** `Merlin/Sessions/LiveSession.swift`

Wraps an `AppState` with all the per-session subsystems that don't belong on `AppState` directly:

- `SkillsRegistry` — file-watched skill loader
- `MCPBridge` — MCP server connections
- `StagingBuffer` — pending file changes
- `MemoryEngine` — idle-triggered memory generation
- `SchedulerEngine` — persisted background scheduled-task runner (the supported automation path)

**Lifecycle** — `init` launches three background tasks collected in `lifecycleTasks: [Task<Void, Never>]`:

1. `MCPBridge.start(config:toolRouter:)` — merges global + project MCP configs, launches servers
2. Inject-file polling — watches `~/.merlin/inject.txt` every 2 s, posts `merlinInjectMessage`
3. `MemoryEngine.startIdleTimer(timeout:)` — idle-triggered memory generation

`close() async` is guarded by `isClosed: Bool` to prevent double-teardown. It cancels all `lifecycleTasks`, then calls `appState.stopEngine()`, `mcpBridge.stop()`, and `memoryEngine.stopIdleTimer()`. A `deinit` fallback cancels tasks in case `close()` was not called (e.g. the session was force-deallocated).

**Domain scoping** — `activeDomainIDs: [String]` is carried per `LiveSession` and applied directly to `appState.engine.activeDomainIDs`. `DomainRegistry` is queried via stateless helpers; no global mutable state changes when switching sessions.

### SessionManager

**File:** `Merlin/Sessions/SessionManager.swift`

`@MainActor ObservableObject` holding the array of `LiveSession` objects for one workspace window. Tracks `activeSession` and handles session creation and teardown.

### SessionStore

**File:** `Merlin/Sessions/SessionStore.swift`

Persists `Session` (the serialisable snapshot of a session, distinct from `LiveSession`) to `~/Library/Application Support/Merlin/sessions/`. Used to restore history on relaunch.

---

## Hook System

**Files:** `Merlin/Hooks/HookEngine.swift`, `Merlin/Hooks/HookDecision.swift`

`HookEngine` is an `actor` that runs shell scripts at lifecycle events. It is recreated from `AppSettings.shared.hooks` on each engine turn (settings changes take effect immediately).

### Hook Events

| Event constant | Fires when | Input (stdin) | Expected output |
|---|---|---|---|
| `"PreToolUse"` | Before tool execution | `{"tool":"<name>","input":{...}}` | `{"decision":"allow"}` or `{"decision":"deny","reason":"..."}` |
| `"PostToolUse"` | After tool execution | `{"tool":"<name>","result":"..."}` | Modified result string (replaces original) |
| `"UserPromptSubmit"` | User sends a message | Prompt text | Modified prompt text |
| `"Stop"` | Agent finishes a turn | `""` | `{"proceed":true}` to keep looping |

A non-zero exit code from the hook script is treated as a failure:
- `PreToolUse` failure → deny
- `PostToolUse` failure → result unchanged
- `Stop` failure → do not proceed

---

## Skill System

**Files:** `Merlin/Skills/`

### Skill File Format

Skills are `.skill.md` files (or any `.md` file in a skills directory):

```markdown
---
name: skill-name
description: One-line description shown in the picker
argument_hint: Optional placeholder text
model: flash          # "flash" | "pro" | unset
context: fork         # "fork" = run without modifying main history
invocation: manual    # "manual" = only via /skill, never auto-invoked
allowed_tools: [read_file, run_shell]
---

Body of the skill. Use {{args}} for the user's argument.
```

### SkillsRegistry

**File:** `Merlin/Skills/SkillsRegistry.swift`

`@MainActor ObservableObject`. Watches two directories with `DispatchSource.makeFileSystemObjectSource`:

- `~/.merlin/skills/` — personal skills
- `<project>/.merlin/skills/` — project-scoped skills

On change, reloads all skill files. `render(skill:arguments:)` substitutes `{{args}}` with the user's argument.

### Skill Invocation in the Engine

When the user types `/skill-name arg`, `ChatView` matches the skill name, retrieves the `Skill` from `SkillsRegistry`, and calls `AppState.engine.invokeSkill(_:arguments:)`. If the skill's `context` is `"fork"`, it calls `runFork()` which creates an isolated message history for the turn and discards it afterwards.

---

## Memory System

**Files:** `Merlin/Memories/MemoryEngine.swift`, `Merlin/Memories/MemoryEntry.swift`, `Merlin/Memories/MemoryBackendPlugin.swift`, `Merlin/Memories/LocalVectorPlugin.swift`, `Merlin/Memories/EmbeddingProvider.swift`

### MemoryEngine

`MemoryEngine` is an `actor`. It starts an idle timer when `startIdleTimer(timeout:)` is called. When the timer fires without being reset by conversation activity:

1. Takes a snapshot of the current `ContextManager.messages`
2. Sends them to the flash provider with a summarisation prompt
3. Writes the result as a Markdown file to `~/.merlin/memories/pending/<timestamp>.md`
4. Posts a `UNUserNotification` prompting the user to review
5. Writes the summary as an `episodic` chunk to `MemoryBackendPlugin` (v9)

`ConstitutionLoader.defaultMemoriesBlock()` reads all approved memory files from `~/.merlin/memories/` at session init and injects them into the system prompt.

### Local Vector Store (v9)

**Files:** `Merlin/Memories/MemoryBackendPlugin.swift`, `Merlin/Memories/LocalVectorPlugin.swift`, `Merlin/Memories/EmbeddingProvider.swift`

Session memory is stored locally in SQLite, replacing xcalibre-server as the memory backend. xcalibre-server is retained for book-content RAG only.

| Symbol | Role |
|---|---|
| `MemoryBackendPlugin` | Actor protocol: `write(chunk:)`, `search(query:topK:)`, `search(query:topK:projectPath:)`, `delete(id:)` |
| `MemoryBackendRegistry` | `@MainActor` registry owned by `AppState`; keyed by backend ID |
| `NullMemoryPlugin` | Default no-op backend — use for ephemeral sessions |
| `LocalVectorPlugin` | Production backend: SQLite + `NLContextualEmbedding` (512-dim, mean-pooled, on-device) |
| `EmbeddingProviderProtocol` | Testable abstraction over the embedding model |
| `NLContextualEmbeddingProvider` | Apple neural embeddings (macOS 14+, no network, no dependencies) |

`MemoryBackendPlugin` has two `search` signatures. The project-scoped form adds a `WHERE project_path = ?` parameterised clause in `LocalVectorPlugin` so retrieval is confined to memories for the active project. Backends that do not implement the three-argument form inherit a default-extension post-filter. `AgenticEngine` always calls the project-scoped overload using `currentProjectPath`.

**Write paths:**
- Approved user memories → written as `factual` chunks by `MemoryEngine.approve()`
- Session summaries → written as `episodic` chunks by `MemoryEngine` on idle fire; suppressed when the critic returned `.fail` for that turn

**Read path:** `AgenticEngine.runLoop()` calls `memoryBackend.search(query:topK:5)` at the start of each turn. Results are merged with any xcalibre book-content chunks, converted to `RAGChunk`, and injected as context via `RAGTools.buildEnrichedMessage`.

**Test doubles:** `TestHelpers/MockEmbeddingProvider.swift` and `TestHelpers/CapturingMemoryBackend.swift` replace the production implementations in unit tests. Semantic fault injection doubles live in `TestHelpers/SemanticFaults/`.

### Behavioral Reliability Framework (v9)

Designed against the failure taxonomy in ["Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems"](https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems) (S. Patil, VentureBeat, 2025).

| Failure pattern | Merlin mitigation |
|---|---|
| **Context degradation** — model reasons confidently over stale/thin retrieval | `GroundingReport` (task 141): per-turn chunk count, average cosine score, staleness flag, `isWellGrounded` |
| **Orchestration drift** — multi-step runs diverge under load | `CriticEngine` evaluates every turn; `ModelParameterAdvisor` tracks score trends |
| **Silent partial failure** — subsystem degrades before fully breaking | `consecutiveCriticFailures` + circuit breaker (task 140): halt or warn after N failures |
| **Automation blast radius** — a bad step propagates into later decisions | `AuthGate` blocks unauthorised calls; critic failure suppresses backend memory writes |

**`GroundingReport`** (`Merlin/Engine/GroundingReport.swift`) — emitted as `AgentEvent.groundingReport(_:)` after every RAG search step, even when no chunks were found. Fields: `totalChunks`, `memoryChunks`, `bookChunks`, `averageScore`, `oldestMemoryAgeDays`, `hasStaleMemory`, `isWellGrounded`. `hasStaleMemory` uses `AppSettings.ragFreshnessThresholdDays` (default 90). `isWellGrounded` is `totalChunks > 0 && averageScore >= AppSettings.ragMinGroundingScore` (default 0.30). Staleness does not affect `isWellGrounded`.

**Circuit breaker** (`AgenticEngine`) — `consecutiveCriticFailures: Int` increments on every `.fail` verdict, resets on `.pass`/`.skipped` and on new session (`Notification.Name.merlinNewSession`). When it reaches `AppSettings.agentCircuitBreakerThreshold` (default 3): `halt` mode cancels the next turn and emits `AgentEvent.systemNote`; `warn` mode emits a warning and proceeds. Configure via `agent_circuit_breaker_threshold` / `agent_circuit_breaker_mode` in `config.toml`.

**Semantic fault injection** (`TestHelpers/SemanticFaults/`) — four test doubles for simulating reliability failures without live infrastructure:

| Double | Simulates |
|---|---|
| `StalenessInjectingMemoryBackend` | Returns chunks with artificially old `createdAt` dates |
| `TruncatingMockProvider` | Returns responses truncated mid-sentence with `finishReason: "length"` |
| `EmptyToolResultRouter` | Returns empty strings for all tool calls |
| `DroppingContextManager` | Silently drops messages above a configurable count |

---

## Electronics / KiCad Domain (v2.0)

**Files:** `Merlin/Electronics/`

The KiCad domain is Merlin's first non-software domain plugin. It adds a full PCB design workflow on top of the existing MCP and domain-plugin infrastructure.

### Architecture

The domain does not contain any KiCad logic itself. It defines the policy and contract layer; execution is delegated to `merlin-kicad-mcp`, an external MCP server process (not part of this repo) that wraps KiCad CLI and Python scripting.

```
AgenticEngine
    │  calls tools via ToolRouter
    ▼
MCPBridge ──→ merlin-kicad-mcp (external process, stdio JSON-RPC)
                    │
                    ▼
              KiCad CLI / Python API
```

### Tool Contract

22 tools across 7 workflow stages. All use OpenAI function-calling wire format:

| Stage | Tools |
|---|---|
| Ingestion | `kicad_ingest_schematic` |
| Project generation | `kicad_create_project`, `kicad_write_schematic`, `kicad_assign_footprints` |
| Board setup | `kicad_set_board_constraints`, `kicad_set_netclasses` |
| Placement & routing | `kicad_place_components`, `kicad_route_pass`, `kicad_run_freerouting` |
| Verification | `kicad_run_erc`, `kicad_run_drc`, `kicad_check_parity`, `kicad_run_spice` |
| Visual QA | `kicad_capture_schematic_png`, `kicad_capture_pcb_png` |
| Output | `kicad_export_bom`, `kicad_query_vendor`, `kicad_export_fab`, `kicad_run_cam_checks`, `kicad_submit_order_approval`, `kicad_release_approval` |

### Hard Gates

Seven verification results block forward progress until they return `PASS` or the operator explicitly overrides:

1. `ERC_PASS` — no schematic errors
2. `DRC_PASS` — no layout rule violations
3. `PARITY_PASS` — netlist matches between schematic and layout
4. `SPICE_PASS` — simulation converges with expected results
5. `CAM_PASS` — Gerber/drill files are structurally valid
6. `VENDOR_CONFIRMED` — BOM priced and in-stock from at least one vendor
7. `RELEASE_APPROVED` — operator signoff before any manufacturing action

### Domain Plugin Registration

`ElectronicsDomain` is built in and registered at app launch:

```swift
DomainRegistry.shared.register(SoftwareDomain())
DomainRegistry.shared.register(ElectronicsDomain())
```

External MCP domain manifests can also register into `DomainRegistry` through `MCPDomainAdapter`. KiCad/PCB manifests are canonicalised to the product-facing `electronics` domain. Electronics sessions carry `activeDomainIDs = ["software", "electronics"]` so the software domain's tools remain available alongside the electronics tools.

### Key Schema Types

All defined in `Merlin/Electronics/`:

- `DesignIntent` — top-level requirements (function, power, connectivity, constraints)
- `BoardProfile` — fabricator rules, stackup, copper weight, finish
- `NetClassPolicy` — net categories and routing constraints
- `PlacementCriteria` — component grouping and keep-out rules
- `SchematicExtractionResult` — output of schematic ingestion
- `BOMEntry` — component with MPN, quantity, vendor data
- `FabricationOutput` — Gerber/drill file set with CAM validation result

---

## MCP Integration

**Files:** `Merlin/MCP/`

The Model Context Protocol allows external servers to expose tools to the engine.

### MCPConfig

**File:** `Merlin/MCP/MCPConfig.swift`

Parsed from two locations (merged, project overrides global):

- `~/.merlin/config.toml` — global MCP servers
- `<project>/.claude/mcp.json` — project-specific servers

Each server entry:
```toml
[mcp.servers.my-server]
command = "npx"
args = ["-y", "@some/mcp-server"]
env = { API_KEY = "${MY_ENV_VAR}" }
```

Environment variable placeholders (`${VAR}`) are expanded from the process environment at launch.

### MCPBridge

**File:** `Merlin/MCP/MCPBridge.swift`

`actor` that:
1. Launches each configured MCP server as a child process
2. Uses JSON-RPC over stdio to call `tools/list` and retrieves tool schemas
3. Optionally reads `merlin://domain/manifest` and registers any manifest-backed domain through `MCPDomainAdapter`
4. Registers each tool with `ToolRouter.registerMCPTool()`, wrapping the JSON-RPC call as a handler
5. Unregisters all tools and manifest-backed domains on `stop()`

---

## Subagent System

**Files:** `Merlin/Agents/`

### SubagentEngine

**File:** `Merlin/Agents/SubagentEngine.swift`

An `actor` that runs a scoped agentic loop with a filtered tool set. Used for **explorer** and **default** agents.

Tool filtering by role:
- `explorer` — file read, list directory, search, shell read-only commands
- `default` / `worker` — all tools (worker writes go through a dedicated `StagingBuffer` / worktree path)

The current implementation executes real tool calls and loops their actual results back into the child model before completion.

### WorkerSubagentEngine

**File:** `Merlin/Agents/WorkerSubagentEngine.swift`

Extends the worker role with git worktree isolation via `WorktreeManager`. Worker file writes are executed against the isolated worktree, recorded in the worker's own `StagingBuffer`, and shown in the sidebar `WorkerDiffView`.

### AgentRegistry

**File:** `Merlin/Agents/AgentRegistry.swift`

`actor` holding named `AgentDefinition` structs. Built-ins register at launch. Custom agents are loaded from TOML files in `~/.merlin/agents/`:

```toml
name = "code-reviewer"
role = "explorer"
instructions = "Review the code for correctness and style."
model = "pro"
allowed_tools = ["read_file", "list_directory"]
```

### spawn_agent Tool

When the engine calls `spawn_agent`, `SpawnAgentTool` resolves the agent definition from `AgentRegistry`, creates a `SubagentEngine` or `WorkerSubagentEngine`, and fires it. Results flow back as `AgentEvent.subagentUpdate` events that the parent engine yields to the UI. Nested `spawn_agent` calls from inside a subagent are currently rejected explicitly.

---

## UI Architecture

**Files:** `Merlin/Views/`, `Merlin/UI/`

### Scene Graph

```
MerlinApp (@main)
  ├── WindowGroup("Merlin", id: "workspace") → WorkspaceView
  │     └── WorkspaceCoordinator-driven layout
  │           ├── SessionSidebar
  │           ├── ContentView
  │           │     ├── ChatView
  │           │     └── ToolLogView / ScreenPreviewView (optional)
  │           ├── DiffPane (optional)
  │           ├── FilePane (optional)
  │           ├── PreviewPane (optional)
  │           ├── SideChatPane (optional)
  │           └── TerminalPane (optional)
  ├── WindowGroup("help") → HelpWindowView
  └── Settings → SettingsWindowView
```

### FocusedValues

**File:** `Merlin/App/AppFocusedValues.swift`

Two focused value keys bridge state from views to `MerlinCommands`:

- `\.isEngineRunning: Binding<Bool>` — enables/disables the Stop menu item
- `\.activeProviderID: Binding<String>` — drives the Provider menu checkmarks and selection

Set via `.focusedValue(\.key, binding)` on `ContentView`. Read via `@FocusedBinding(\.key)` in `MerlinCommands`.

### WorkspaceLayout

**File:** `Merlin/Windows/WorkspaceLayoutManager.swift`

A `Codable` struct holding pane visibility flags and widths. Persisted per-project to `~/.merlin/layout-<projectID>.json`. `WorkspaceView` saves on every change.

### ChatView

**File:** `Merlin/Views/ChatView.swift`

The primary chat interface. Key responsibilities:

- Renders `Message` objects from `ContextManager.messages`
- Auto-scrolls to the latest message
- Handles `@-mention` autocomplete (file picker)
- Handles `/skill` invocation (skills picker)
- Drag-and-drop file and image attachment
- Submit button doubles as stop button when engine is running (red stop icon)
- Toolbar actions row (quick-access shell shortcuts)

Provider routing status is no longer displayed in the chat header area. Routing
state is represented in the sidebar slot panel instead.

### SlotStatusPanel

**File:** `Merlin/Views/SlotStatusPanel.swift`

`SlotStatusPanel` renders four persistent rows (Execute, Reason, Orchestrate,
Vision) from explicit `AppSettings.slotAssignments` only.

- Resolver: `SlotStatusResolver`
- Row model: `SlotStatusRowModel`
- Unassigned rows remain visible and show `Not configured`
- Provider enablement, active provider selection, and fallback rules do not
  populate rows

---

## Configuration System

**Files:** `Merlin/Config/`

### AppSettings

**File:** `Merlin/Config/AppSettings.swift`

`@MainActor ObservableObject` singleton. Single source of truth for all persisted app configuration.

Backing stores:
- `~/.merlin/config.toml` — feature flags, hooks, memories config, toolbar actions, reasoning overrides
- Keychain — API keys, connector tokens
- `UserDefaults` — UI-only state (theme, fonts, window layout)

`AppSettings.shared` is always accessible. Features read from it directly; they never read `UserDefaults` or `config.toml` themselves.

### TOML Parser

**Files:** `Merlin/Config/TOMLParser.swift`, `TOMLValue.swift`, `TOMLDecoder.swift`

A hand-written TOML parser with no third-party dependencies. `TOMLDecoder` bridges to `JSONDecoder` by converting the parse tree to JSON first.

### config.toml Structure

```toml
[settings]
max_context_tokens = 200000
keep_awake = true
default_permission_mode = "ask"     # "ask" | "auto" | "plan"
memories_enabled = true
memory_idle_timeout = 300           # seconds

[appearance]
theme = "system"                    # "light" | "dark" | "system"
font_size = 13.0
accent_color_hex = ""

[[hooks]]
event = "PreToolUse"
command = "my-hook-script"
enabled = true

[mcp.servers.my-server]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem"]
```

---

## Connectors

**Files:** `Merlin/Connectors/`

Each connector conforms to the `Connector` protocol and stores its token in the Keychain via `ConnectorCredentials`.

| File | Service | Authentication |
|---|---|---|
| `GitHubConnector.swift` | GitHub REST API | Personal Access Token |
| `LinearConnector.swift` | Linear GraphQL API | API key |
| `SlackConnector.swift` | Slack Web API | Bot token |

`PRMonitor.swift` polls open GitHub PRs on a timer, comparing CI check states and posting `UNUserNotification` on transitions.

---

## Testing Strategy

### Test Target Layout

```
MerlinTests/Unit/         — fast unit tests (no I/O, no network)
MerlinTests/Integration/  — real file system, real Process, mocked LLM
MerlinLiveTests/          — real provider APIs (run manually with MerlinTests-Live scheme)
MerlinE2ETests/           — full agentic loop + SwiftUI visual tests
TestHelpers/              — MockProvider, NullAuthPresenter, EngineFactory (shared)
```

`TestHelpers/` is a source folder included in all test targets via `project.yml` (not a separate Swift package).

### MockProvider

`TestHelpers/MockProvider.swift` — conforms to `LLMProvider` and returns scripted responses. Use `EngineFactory` to build a fully-wired engine for tests.

### Auth paths in tests

Always use `/tmp/auth-<test-name>.json` as the auth memory path. **Never** use a shared path — tests run in parallel and will corrupt each other's state.

### Tool count assertions

Do **not** assert a fixed total tool count. Assert that named tools are present. The registry is dynamic and count changes as MCP tools register/unregister.

---

## Code Map

Cross-reference between code comments and this manual:

| Symbol | File | Manual Section |
|---|---|---|
| `AgenticEngine` | `Engine/AgenticEngine.swift` | [Engine — The Agentic Loop](#engine--the-agentic-loop) |
| `AgenticEngine.runLoop()` | `Engine/AgenticEngine.swift` | [The Run Loop](#the-run-loop-runloop) |
| `AgentSlot` | `Engine/AgentSlot.swift` | [Supervisor-Worker Engine → AgentSlot](#agentslot) |
| `CriticEngine` | `Engine/CriticEngine.swift` | [Supervisor-Worker Engine → CriticEngine](#criticengine) |
| `PlannerEngine` | `Engine/PlannerEngine.swift` | [Supervisor-Worker Engine → PlannerEngine](#plannerengine) |
| `ModelPerformanceTracker` | `Engine/ModelPerformanceTracker.swift` | [Supervisor-Worker Engine → ModelPerformanceTracker](#modelperformancetracker) |
| `LoRATrainer` | `Engine/LoRATrainer.swift` | [LoRA Training Pipeline → LoRATrainer](#loratrainer) |
| `LoRACoordinator` | `Engine/LoRACoordinator.swift` | [LoRA Training Pipeline → LoRACoordinator](#loracoordinator) |
| `DomainRegistry` | `MCP/DomainRegistry.swift` | [Supervisor-Worker Engine → DomainRegistry / DomainPlugin](#domainregistry--domainplugin) |
| `DomainPlugin` | `MCP/DomainPlugin.swift` | [Supervisor-Worker Engine → DomainRegistry / DomainPlugin](#domainregistry--domainplugin) |
| `SoftwareDomain` | `MCP/SoftwareDomain.swift` | [Supervisor-Worker Engine → DomainRegistry / DomainPlugin](#domainregistry--domainplugin) |
| `LoRASettingsSection` | `Views/Settings/LoRASettingsSection.swift` | [LoRA Training Pipeline → LoRASettingsSection](#lorasettingssection) |
| `RoleSlotSettingsView` | `Views/Settings/RoleSlotSettingsView.swift` | [Supervisor-Worker Engine → AgentSlot](#agentslot) |
| `PerformanceDashboardView` | `Views/Settings/PerformanceDashboardView.swift` | [Supervisor-Worker Engine → ModelPerformanceTracker](#modelperformancetracker) |
| `MemoryBrowserView` | `Views/Settings/MemoryBrowserView.swift` | [RAG Memory Browser](#rag-memory-browser) |
| `MemoryBackendPlugin` | `Memories/MemoryBackendPlugin.swift` | [Memory System → Local Vector Store (v9)](#local-vector-store-v9) |
| `MemoryBackendRegistry` | `Memories/MemoryBackendPlugin.swift` | [Memory System → Local Vector Store (v9)](#local-vector-store-v9) |
| `LocalVectorPlugin` | `Memories/LocalVectorPlugin.swift` | [Memory System → Local Vector Store (v9)](#local-vector-store-v9) |
| `NullMemoryPlugin` | `Memories/MemoryBackendPlugin.swift` | [Memory System → Local Vector Store (v9)](#local-vector-store-v9) |
| `EmbeddingProviderProtocol` | `Memories/EmbeddingProvider.swift` | [Memory System → Local Vector Store (v9)](#local-vector-store-v9) |
| `NLContextualEmbeddingProvider` | `Memories/EmbeddingProvider.swift` | [Memory System → Local Vector Store (v9)](#local-vector-store-v9) |
| `GroundingReport` | `Engine/GroundingReport.swift` | [Memory System → Behavioral Reliability Framework (v9)](#behavioral-reliability-framework-v9) |
| `ToolRouter` | `Engine/ToolRouter.swift` | [Tool System → ToolRouter](#toolrouter) |
| `ToolRouter.dispatch()` | `Engine/ToolRouter.swift` | [Tool System → ToolRouter](#toolrouter) |
| `ContextManager` | `Engine/ContextManager.swift` | [ContextManager](#contextmanager) |
| `StagingBuffer` | `Engine/StagingBuffer.swift` | [Staging Buffer](#staging-buffer) |
| `AppState` | `App/AppState.swift` | [Session & State Management → AppState](#appstate) |
| `LiveSession` | `Sessions/LiveSession.swift` | [Session & State Management → LiveSession](#livesession) |
| `HookEngine` | `Hooks/HookEngine.swift` | [Hook System](#hook-system) |
| `SkillsRegistry` | `Skills/SkillsRegistry.swift` | [Skill System → SkillsRegistry](#skillsregistry) |
| `MemoryEngine` | `Memories/MemoryEngine.swift` | [Memory System](#memory-system) |
| `MCPBridge` | `MCP/MCPBridge.swift` | [MCP Integration → MCPBridge](#mcpbridge) |
| `SubagentEngine` | `Agents/SubagentEngine.swift` | [Subagent System → SubagentEngine](#subagentengine) |
| `WorkerSubagentEngine` | `Agents/WorkerSubagentEngine.swift` | [Subagent System → WorkerSubagentEngine](#workersubagentengine) |
| `ProviderRegistry` | `Providers/ProviderConfig.swift` | [Provider System → ProviderRegistry](#providerregistry) |
| `AuthGate` | `Auth/AuthGate.swift` | [Auth & Permission System → AuthGate](#authgate) |
| `AppSettings` | `Config/AppSettings.swift` | [Configuration System → AppSettings](#appsettings) |
| `WorkspaceView` | `Views/WorkspaceView.swift` | [UI Architecture → Scene Graph](#scene-graph) |
| `ChatView` | `Views/ChatView.swift` | [UI Architecture → ChatView](#chatview) |
| `AppFocusedValues` | `App/AppFocusedValues.swift` | [UI Architecture → FocusedValues](#focusedvalues) |

---

## Adding a New Tool

1. **Write the failing test** (Task NNa):
   - Test that `ToolRegistry.shared` contains your tool by name after `registerBuiltins()`
   - Test the handler function directly with a mock input

2. **Add the definition** to `ToolDefinitions.swift`:
   ```swift
   static let myTool = ToolDefinition(
       function: .init(
           name: "my_tool",
           description: "What it does",
           parameters: .init(
               type: "object",
               properties: ["param": .init(type: "string", description: "...")],
               required: ["param"]
           )
       )
   )
   ```

3. **Implement the handler** in an appropriate file under `Tools/`:
   ```swift
   static func handle(_ args: String) async throws -> String {
       // decode args from JSON, do the work, return result as String
   }
   ```

4. **Register** in `ToolRegistration.swift`:
   ```swift
   router.register(name: "my_tool") { args in
       try await MyTools.handle(args)
   }
   ```
   And in `registerBuiltins()` in `ToolRegistry.swift`:
   ```swift
   register(ToolDefinitions.myTool)
   ```

5. **Verify** build succeeds and tests pass. Commit.

---

## Adding a New Provider

1. Create `Providers/MyProvider.swift` conforming to `LLMProvider`
2. Add a `ProviderConfig` entry to `ProviderRegistry.defaultProviders` with the correct `id`, `baseURL`, `kind`, and feature flags
3. If your wire format is OpenAI-compatible — just instantiate `OpenAICompatibleProvider` in `makeLLMProvider(for:)`
4. If it needs a custom format — implement `complete()` using `URLSession` + SSE parsing
5. Update `ProviderRegistry+ReasoningEffort.swift` if the provider supports extended thinking
6. Add the API key to `readAPIKey(for:)` / `setAPIKey(_:for:)` if needed
7. Write tests, build, commit

---

## Writing a Skill

Create a Markdown file in `~/.merlin/skills/` or `<project>/.merlin/skills/`:

```markdown
---
name: my-skill
description: Short description for the picker
argument_hint: optional argument placeholder
---

Your prompt template. Use {{args}} where the user's argument should be injected.

You can include any instructions, constraints, or context here.
```

The file is picked up automatically by `SkillsRegistry` within seconds of saving. No rebuild required.

For project-scoped skills that should not be shared across projects, put them in `<project>/.merlin/skills/` instead.

---

## Non-Negotiable Rules

These rules apply to every code change in this repository. They are enforced in `constitution.md` and must not be bypassed.

1. **TDD always.** Tests first, failing commit, then implementation.
2. **Git commit after every task.** No exceptions, no batching.
3. **Zero warnings, zero errors.** `SWIFT_STRICT_CONCURRENCY=complete`.
4. **No third-party Swift packages** in production or test targets.
5. **Non-sandboxed.** Do not use sandbox-only APIs.
6. **OpenAI wire format** for all tool definitions.
7. **No force-unwraps, no `try!`, no `fatalError` in production code.**
8. **`@MainActor`** on all `ObservableObject` subclasses and SwiftUI views that mutate state.
9. **Parallel tool calls** use `async let` / `TaskGroup`, not sequential `await`.
10. **Auth memory path in tests:** `/tmp/auth-<test-name>.json` — never a shared path.

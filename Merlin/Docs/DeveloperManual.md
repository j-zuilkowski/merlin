# Merlin — Developer Manual

**Version 4.0**

This manual covers the complete architecture, development workflow, and code organisation of Merlin. It is intended for contributors working on the codebase. Code references use the format `File.swift:ClassName.method()` matching the comments embedded throughout the source.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Repository Layout](#repository-layout)
3. [Build System](#build-system)
4. [Development Workflow — TDD Phases](#development-workflow--tdd-phases)
5. [Phase Sheet Format](#phase-sheet-format)
6. [Core Architecture](#core-architecture)
7. [Engine — The Agentic Loop](#engine--the-agentic-loop)
8. [Tool System](#tool-system)
9. [Provider System](#provider-system)
10. [Auth & Permission System](#auth--permission-system)
11. [Session & State Management](#session--state-management)
12. [Hook System](#hook-system)
13. [Skill System](#skill-system)
14. [Memory System](#memory-system)
15. [MCP Integration](#mcp-integration)
16. [Subagent System](#subagent-system)
17. [UI Architecture](#ui-architecture)
18. [Configuration System](#configuration-system)
19. [Connectors](#connectors)
20. [Testing Strategy](#testing-strategy)
21. [Code Map](#code-map)
22. [Adding a New Tool](#adding-a-new-tool)
23. [Adding a New Provider](#adding-a-new-provider)
24. [Writing a Skill](#writing-a-skill)
25. [Non-Negotiable Rules](#non-negotiable-rules)

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
│   ├── Automations/          # ThreadAutomation structs and scheduling engine
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
├── TestTargetApp/            # Minimal target app for AX/UI tests
├── phases/                   # Phase sheet Markdown files
├── architecture.md           # High-level design document
├── llm.md                    # Provider wire format details
├── project.yml               # XcodeGen project definition
└── CLAUDE.md                 # Session instructions for AI coding assistants
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

## Development Workflow — TDD Phases

Every feature is built in two committed phases:

### Phase NNa — Tests (failing)

1. Read `phases/PASTE-LIST.md` to find the next unused phase number
2. Write the `phases/phase-NNa-<name>-tests.md` sheet (see format below)
3. Write the test file(s) — **implementation classes must not exist yet**
4. Run `xcodebuild` and confirm `BUILD FAILED` with errors naming the missing symbols
5. Commit: `Phase NNa — <TestNames> (failing)`

### Phase NNb — Implementation

1. Write the `phases/phase-NNb-<name>.md` sheet
2. Implement the production code
3. Run `xcodebuild` and confirm `BUILD SUCCEEDED` with all NNa tests passing
4. Commit: `Phase NNb — <FeatureName>`

**Commits are mandatory after every phase.** Never batch phases into one commit. Never amend a phase commit.

### Git Commit Protocol

```bash
git add <specific files — never git add -A>
git commit -m "Phase NNx — <Description>"
```

---

## Phase Sheet Format

### NNa sheet (`phases/phase-NNa-<name>-tests.md`)

```markdown
# Phase NNa — <Feature> Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed.
SWIFT_STRICT_CONCURRENCY=complete. Working dir: ~/Documents/localProject/merlin
Phase (N-1)b complete: <what was last implemented>.

New surface introduced in phase NNb:
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
git commit -m "Phase NNa — TestName (failing)"
```

### NNb sheet (`phases/phase-NNb-<name>.md`)

```markdown
# Phase NNb — <Feature> Implementation

## Context
<same as NNa, updated>
Phase NNa complete: failing tests in place.

---

## Write to / Edit: SourceFile.swift
<full file content or diff>

---

## Verify
xcodebuild -scheme MerlinTests test ...
# Expected: BUILD SUCCEEDED, all NNa tests pass

## Commit
git add <source files>
git commit -m "Phase NNb — FeatureName"
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

1. Builds a `CompletionRequest` from context, system prompt (CLAUDE.md + memories), tools, and optional vision attachment
2. Calls `proProvider.complete()` and streams events
3. On `toolCallStarted` — fires `HookEngine.runPreToolUse()`, then dispatches via `ToolRouter`
4. On `toolCallResult` — optionally runs `HookEngine.runPostToolUse()` to let hooks rewrite results
5. After all tool results are appended to context — checks `HookEngine.runStop()` to determine whether to continue
6. Recurses at `depth + 1` (max depth prevents infinite loops)

### AgentEvent

All outputs are yielded as `AgentEvent` values:

```swift
enum AgentEvent {
    case text(String)           // streamed text delta
    case thinking(String)       // extended thinking block
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case subagentStarted(id:agentName:)
    case subagentUpdate(id:event:)
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
| `LMStudioProvider.swift` | Discovers the running model name from the LM Studio `/v1/models` endpoint. |

### ProviderRegistry

**File:** `Merlin/Providers/ProviderConfig.swift`

`@MainActor ObservableObject` that holds the list of `ProviderConfig` structs, the `activeProviderID`, and keychain API-key accessors. Persists to `~/Library/Application Support/Merlin/providers.json`.

`makeLLMProvider(for:)` is the factory that converts a `ProviderConfig` to a concrete `LLMProvider` instance.

---

## Auth & Permission System

### AuthGate

**File:** `Merlin/Auth/AuthGate.swift`

Called by `ToolRouter` before every tool execution. Logic:

1. Check `AuthMemory` for an existing allow/deny pattern matching `(tool, argument)`
2. If no pattern found — call `AuthPresenter.requestDecision()` to surface the popup
3. Record the user's decision if they chose "Always"

### AuthMemory

**File:** `Merlin/Auth/AuthMemory.swift`

Stores `(tool, pattern, decision)` triples. Persists to a JSON file (path configured per-session to avoid test cross-contamination). Pattern matching is delegated to `PatternMatcher`.

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
- `ThreadAutomationStore` + `ThreadAutomationEngine` — cron-based automations

`LiveSession.init()` wires all of these together, starts the MCP bridge, and begins the memory idle timer if memories are enabled in `AppSettings`.

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

**Files:** `Merlin/Memories/MemoryEngine.swift`, `Merlin/Memories/MemoryEntry.swift`

`MemoryEngine` is an `actor`. It starts an idle timer when `startIdleTimer(timeout:)` is called. When the timer fires without being reset by conversation activity:

1. Takes a snapshot of the current `ContextManager.messages`
2. Sends them to the flash provider with a summarisation prompt
3. Writes the result as a Markdown file to `~/.merlin/memories/pending/<timestamp>.md`
4. Posts a `UNUserNotification` prompting the user to review

`CLAUDEMDLoader.defaultMemoriesBlock()` reads all approved memory files from `~/.merlin/memories/` at session init and injects them into the system prompt.

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
3. Registers each tool with `ToolRouter.registerMCPTool()`, wrapping the JSON-RPC call as a handler
4. Unregisters all tools on `stop()`

---

## Subagent System

**Files:** `Merlin/Agents/`

### SubagentEngine

**File:** `Merlin/Agents/SubagentEngine.swift`

An `actor` that runs a scoped agentic loop with a filtered tool set. Used for **explorer** agents (read-only).

Tool filtering by role:
- `explorer` — file read, list directory, search, shell read-only commands
- `worker` — all tools (writes go through a dedicated `StagingBuffer`)

### WorkerSubagentEngine

**File:** `Merlin/Agents/WorkerSubagentEngine.swift`

Extends the worker role with git worktree isolation via `WorktreeManager`. Worker file writes are captured in the worker's own `StagingBuffer`, visible in the sidebar `WorkerDiffView`.

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

When the engine calls `spawn_agent`, `SpawnAgentTool` resolves the agent definition from `AgentRegistry`, creates a `SubagentEngine` or `WorkerSubagentEngine`, and fires it. Results flow back as `AgentEvent.subagentUpdate` events that the parent engine yields to the UI.

---

## UI Architecture

**Files:** `Merlin/Views/`, `Merlin/UI/`

### Scene Graph

```
MerlinApp (@main)
  ├── WindowGroup("picker") → ProjectPickerView
  ├── WindowGroup(for: ProjectRef.self) → WorkspaceView
  │     └── mainLayout(session:)
  │           ├── SessionSidebar
  │           ├── ContentView
  │           │     ├── ChatView
  │           │     └── ToolLogView / ScreenPreviewView (optional)
  │           ├── DiffPane (optional)
  │           ├── FilePane (optional)
  │           ├── PreviewPane (optional)
  │           └── SideChatPane (optional)
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

1. **Write the failing test** (Phase NNa):
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

These rules apply to every code change in this repository. They are enforced in `CLAUDE.md` and must not be bypassed.

1. **TDD always.** Tests first, failing commit, then implementation.
2. **Git commit after every phase.** No exceptions, no batching.
3. **Zero warnings, zero errors.** `SWIFT_STRICT_CONCURRENCY=complete`.
4. **No third-party Swift packages** in production or test targets.
5. **Non-sandboxed.** Do not use sandbox-only APIs.
6. **OpenAI wire format** for all tool definitions.
7. **No force-unwraps, no `try!`, no `fatalError` in production code.**
8. **`@MainActor`** on all `ObservableObject` subclasses and SwiftUI views that mutate state.
9. **Parallel tool calls** use `async let` / `TaskGroup`, not sequential `await`.
10. **Auth memory path in tests:** `/tmp/auth-<test-name>.json` — never a shared path.

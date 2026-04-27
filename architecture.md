# Merlin — Architecture Document

## Overview

Merlin is a personal, non-distributed agentic development assistant for macOS. It connects to multiple LLM providers — remote (DeepSeek, OpenAI, Anthropic, Qwen, OpenRouter) and local (Ollama, LM Studio, Jan.ai, LocalAI, Mistral.rs, vLLM) — exposes a rich tool registry covering file system, shell, Xcode, and GUI automation, and presents a SwiftUI chat interface.

**[v1]** Single serial session, direct file writes, fixed layout.
**[v2]** Multiple windows (one per project), parallel sessions in Git worktrees, staged diff/review layer, draggable pane workspace, skills, MCP, scheduling, PR monitoring, external connectors.
**[v3]** Agent intelligence + UX completeness: unified settings window, config system, AI-generated memories, hooks, thread automations, web search, reasoning effort, toolbar actions, notifications, personalization, context usage indicator, floating pop-out window, voice dictation.

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

The pro/flash split is retired. One active provider per session. A skill's `model` frontmatter field overrides the active provider for that skill's turn. [v2]

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
com.merlin.xcalibre           / api-token  (RAG server)
```

`ProviderRegistry.setAPIKey(_:for:)` writes and `readAPIKey(for:)` reads. Keys never written to disk in plaintext, never included in session JSON, never logged.

`ProviderSettingsView` lets the user enter API keys and toggle providers from the settings sheet. On the first launch for any remote provider, `FirstLaunchSetupView` prompts for the active provider's key and writes it via `ProviderRegistry`.

**[v2]** Connector tokens (GitHub, Slack, Linear) stored as separate Keychain items under `com.merlin.<service>`.

---

## Project Structure

```
Merlin/
├── App/
│   ├── MerlinApp.swift
│   └── AppState.swift
├── Sessions/
│   ├── Session.swift
│   ├── SessionStore.swift
│   ├── SessionManager.swift          [v2] — parallel session lifecycle
│   ├── StagingBuffer.swift           [v2] — pending write queue
│   └── WorktreeManager.swift         [v2] — git worktree create/remove
├── Providers/
│   ├── LLMProvider.swift
│   ├── OpenAICompatibleProvider.swift    — parameterised OAI-compat (replaces DeepSeekProvider + LMStudioProvider)
│   ├── AnthropicProvider.swift           — Anthropic Messages API + SSE translation
│   ├── AnthropicSSEParser.swift          — content_block_delta parser
│   ├── ProviderConfig.swift              — ProviderConfig + ProviderKind + ProviderRegistry
│   ├── DeepSeekProvider.swift            — kept for live test backward compat
│   └── LMStudioProvider.swift            — kept for live test backward compat
├── Engine/
│   ├── AgenticEngine.swift
│   ├── ContextManager.swift
│   ├── ToolRouter.swift
│   └── ThinkingModeDetector.swift
├── Auth/
│   ├── AuthGate.swift
│   ├── AuthMemory.swift
│   └── PatternMatcher.swift
├── Tools/
│   ├── ToolDefinitions.swift
│   ├── FileSystemTools.swift
│   ├── ShellTool.swift
│   ├── AppControlTools.swift
│   ├── ToolDiscovery.swift
│   ├── XcodeTools.swift
│   ├── AXInspectorTool.swift
│   ├── ScreenCaptureTool.swift
│   ├── CGEventTool.swift
│   ├── VisionQueryTool.swift
│   └── PreviewTools.swift            [v2]
├── MCP/
│   └── MCPBridge.swift               [v2]
├── Skills/
│   ├── SkillsRegistry.swift          [v2]
│   └── BuiltinSkills.swift           [v2]
├── Connectors/
│   ├── GitHubConnector.swift         [v2]
│   ├── SlackConnector.swift          [v2]
│   └── LinearConnector.swift         [v2]
├── Scheduler/
│   └── SchedulerEngine.swift         [v2]
├── PRMonitor/
│   └── PRMonitor.swift               [v2]
├── Context/
│   └── CLAUDEMDLoader.swift          [v2]
├── Layout/
│   └── WorkspaceLayoutManager.swift  [v2]
├── Keychain/
│   └── KeychainManager.swift
├── RAG/
│   ├── XcalibreClient.swift          — RAG HTTP client, actor-based
│   └── RAGTools.swift                — buildEnrichedMessage, formatChunks, formatBooks
└── Views/
    ├── ChatView.swift
    ├── SessionSidebar.swift          [v2]
    ├── DiffPane.swift                [v2]
    ├── FilePane.swift                [v2]
    ├── TerminalPane.swift            [v2]
    ├── PreviewPane.swift             [v2]
    ├── ToolLogView.swift
    ├── ScreenPreviewView.swift
    ├── AuthPopupView.swift
    ├── ProviderHUD.swift
    ├── SkillsPicker.swift            [v2]
    ├── SideChat.swift                [v2]
    ├── FirstLaunchSetupView.swift
    └── Settings/
        ├── ProviderSettingsView.swift — per-provider API key + enable/disable + base URL
        ├── SchedulerView.swift       [v2]
        ├── ConnectorsView.swift      [v2]
        └── MCPServersView.swift      [v2]
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

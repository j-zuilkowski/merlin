# Merlin — Features

A complete reference of everything Merlin can do. For implementation details see [`architecture.md`](architecture.md).

---

## LLM Providers

Merlin connects to remote and local providers interchangeably. Switch mid-session from the toolbar.

**Remote**
- Anthropic (Claude Opus, Sonnet, Haiku)
- DeepSeek
- OpenAI (GPT-4o, o1, o3, o4-mini)
- Qwen
- OpenRouter

**Local (no API key required)**
- LM Studio
- Ollama
- Jan.ai
- LocalAI
- Mistral.rs
- vLLM

All providers share a single configuration surface (Settings → Providers). API keys are stored in macOS Keychain — never written to disk. Local providers are auto-probed for availability at launch.

---

## Agentic Engine

- **Autonomous loop** — the model calls tools, reads results, and continues until the task is complete. No user intervention required between steps.
- **Parallel tool calls** — multiple tools dispatched concurrently via Swift structured concurrency.
- **Interrupt at any time** — Stop button cancels the active turn cleanly; the session remains in a valid state.
- **Error retry** — first failure retries silently; second failure surfaces to the user with Retry / Skip / Abort options.
- **Context compaction** — at 800,000 tokens, old tool results are summarised automatically. Conversation and code context are preserved verbatim.
- **Thinking mode** — automatically enabled for reasoning-heavy prompts (architecture, debugging, analysis) when the active provider supports it. Suppressed for simple operations.
- **Reasoning effort** — configurable per provider; overridable per session.

---

## Multi-Provider Setup

On first launch, a setup wizard lets you pick and configure any provider. You can skip it and configure later in Settings → Providers.

---

## Projects & Windows

- **Project-scoped windows** — each window is bound to one project root. Open multiple projects simultaneously in separate windows.
- **Project picker** — launch screen lists recent projects with last-opened timestamps. One click to reopen.
- **Window state restoration** — macOS restores all open workspace windows on relaunch.

---

## Sessions

- **Parallel sessions per project** — run multiple independent agent threads in the same window, each with its own context, provider, and permission mode.
- **Session sidebar** — lists open sessions with title, model badge, activity indicator, and permission mode. Switch instantly.
- **Git worktree isolation** — each session works in its own git worktree so parallel sessions never conflict on disk.
- **Session persistence** — sessions are saved to disk after each turn and reloaded on relaunch.
- **New Session shortcut** — ⌘N opens the project picker / new session.

---

## File Operations

| Tool | What it does |
|---|---|
| Read file | Returns contents with line numbers |
| Write / Create file | Creates or overwrites files |
| Delete file | Removes a file |
| Move / Rename file | Moves or renames |
| List directory | Returns directory tree, recursive optional |
| Search files | Glob pattern + optional content grep |

---

## Shell

- Runs any shell command via `Foundation.Process`
- Streams stdout and stderr to the Tool Log in real time
- Configurable working directory (defaults to project root / active worktree)
- Default 120s timeout; Xcode builds allow 600s

---

## Xcode Integration

| Capability | Details |
|---|---|
| Build | `xcodebuild` with scheme, configuration, destination |
| Test | Full suite or single test by ID |
| Clean | Build folder and DerivedData |
| Open file at line | Via AppleScript — jumps Xcode to the exact line |
| Parse results | Extracts errors, warnings, coverage from `.xcresult` |
| Simulators | List, boot, screenshot, install `.app` |
| Swift Package Manager | `swift package resolve`, list dependencies |

Build output is parsed and structured before being added to context.

---

## GUI Automation

Three strategies work together. The agent selects automatically based on what the target app exposes.

**Accessibility Tree** — inspects, finds, and reads AX elements. Works with any app that exposes accessibility.

**Screenshot + Vision** — captures windows via ScreenCaptureKit, sends frames to a vision model for coordinate and action inference. Falls back to this when AX is unavailable or sparse.

**Input Simulation** — mouse clicks, double-clicks, right-clicks, drags, keyboard input, modifier shortcuts, scroll — all via CGEvent. Always available regardless of app.

Requires Accessibility and Screen Recording permissions (requested on first use).

---

## Diff / Review Layer

- **Staged writes** — in Ask and Plan modes, all file writes are intercepted and queued rather than applied immediately.
- **Unified diff view** — each queued change shown as a colour-coded diff. Accept or Reject per change, or accept/reject all.
- **Inline comments** — click any diff line to attach a comment. Comments are sent back to the agent as a follow-up; the agent revises and the diff updates in place.
- **Commit from diff** — after accepting, commit directly from the diff pane with an auto-generated message.
- **Auto-accept mode** — skip staging entirely; writes apply immediately.

---

## Permission Modes

| Mode | File writes | Shell | Effect |
|---|---|---|---|
| **Ask** (default) | Staged | Runs | AuthGate popup for new patterns |
| **Auto-accept** | Immediate | Runs | AuthGate popup for new patterns |
| **Plan** | Blocked | Blocked | Read-only; produces a plan for review |

Switch modes per-session with ⌘⇧M.

---

## Auth Gate & Sandbox

Every tool call — including MCP tools — passes through the auth gate before execution.

- **Pattern matching** — glob patterns per tool (e.g. `~/Documents/localProject/**` for `read_file`, `xcodebuild *` for `run_shell`)
- **Remember decisions** — Allow Once, Allow Always, Deny Once, Deny Always
- **Auth memory** — persisted to `~/Library/Application Support/Merlin/auth.json`
- **Keyboard shortcuts** in popup — ⌘↩ Allow Once, ⌥⌘↩ Allow Always, ⎋ Deny

---

## Skills / Slash Commands

Skills are Markdown files with YAML frontmatter. Drop them in `~/.merlin/skills/` (personal, all projects) or `.merlin/skills/` (project-scoped). Invoke with `/skill-name` or let the model invoke them automatically.

**Built-in skills**

| Skill | What it does |
|---|---|
| `/review` | Code review of staged changes |
| `/plan` | Switch to Plan mode and map out the task |
| `/commit` | Generate a commit message from the staged diff |
| `/test` | Write tests for a function or module |
| `/explain` | Explain selected code in plain English |
| `/debug` | Debug a failing test or error |
| `/refactor` | Propose a refactor for a code section |
| `/summarise` | Summarise the current session |

Skills reload automatically when files change. The skills picker (`/`) shows a fuzzy-searchable list.

---

## MCP Server Support

Connect any MCP server via stdio transport. Configure in `~/.merlin/mcp.json`. Servers start automatically at launch; their tools register into the tool router alongside built-in tools. All MCP tool calls go through the auth gate.

---

## Context Injection

- **@mention files** — type `@` in the prompt to open a file picker. Selected files are inlined with line numbers. Supports line-range syntax: `@Engine.swift:50-120`.
- **Drag and drop** — drop files directly onto the chat input.
- **Attachments** — source files inlined as code blocks; images sent to the vision model and result inlined; PDFs text-extracted via PDFKit.
- **CLAUDE.md auto-load** — at session start, Merlin searches for `CLAUDE.md` files from the project root upward and prepends them to the system prompt.
- **Memory injection** — accepted AI-generated memories are injected as a second system prompt block every session.

---

## AI-Generated Memories

Opt-in. After 5 minutes of session inactivity, Merlin uses the fastest available model to distill the session transcript into a memory file. Memories capture preferences, workflow conventions, project patterns, and known pitfalls — never raw file contents or secrets.

- Pending memories appear in Settings → Memories for review before acceptance.
- Accepted memories live in `~/.merlin/memories/` and are injected at the start of every future session.

---

## Hooks

Shell scripts that intercept the agentic lifecycle. Defined in `~/.merlin/config.toml`.

| Hook | When | Can block |
|---|---|---|
| `PreToolUse` | Before tool call reaches auth gate | Yes |
| `PostToolUse` | After tool completes | No — can inject a system note |
| `UserPromptSubmit` | Before user message is sent | No — can augment the prompt |
| `Stop` | After a turn completes | No — can trigger continuation |

`PreToolUse` runs before the auth gate and fails closed (crash = deny).

---

## Scheduler

Set recurring agent sessions on a cron-like schedule. Each scheduled task specifies a project, a prompt or skill, a time, and a permission mode. On fire, Merlin opens a background session, runs the prompt to completion, and posts a macOS notification with a summary.

---

## Thread Automations

Trigger prompts automatically within an open session on a schedule (e.g. "check CI status every 15 minutes"). Different from the Scheduler — automations run inside an existing live session rather than opening a new one.

---

## PR Monitor

Polls GitHub pull requests associated with the active project.

- On CI failure: posts a macOS notification; opening it launches a new session pre-loaded with the PR diff and CI output.
- On CI pass: optionally auto-merges if the flag was set.
- Requires a GitHub token in Settings → Connectors.

---

## External Connectors

| Connector | Read | Write |
|---|---|---|
| **GitHub** | PRs, CI checks, issues, file contents | Create PR, comment, merge, push |
| **Slack** | Channel messages | Post message |
| **Linear** | Issues, project status, cycle items | Create issue, update status, comment |

All connectors are opt-in. Credentials in Keychain.

---

## Web Search

Brave Search integration. When a Brave API key is configured (Settings → Search), a `web_search` tool is registered and available to the agent. Disabled entirely when no key is present.

---

## Supervisor-Worker Multi-LLM

Tasks are classified by complexity and routed to the most appropriate LLM slot. Different providers can be assigned to each slot in Settings → Role Slots.

**Agent Slots**

| Slot | Purpose |
|---|---|
| `execute` | General task execution — file ops, code generation, tool loops. LoRA adapter routes here when loaded. |
| `reason` | Deep reasoning, debugging, architecture decisions. Always uses the unmodified base model. |
| `orchestrate` | Multi-step planning and subagent coordination. Falls back to `reason` if unassigned. |
| `vision` | GUI screenshot analysis, UI element localization. |

**Domain System** — `DomainRegistry` holds pluggable `DomainPlugin` instances that supply domain-specific verification commands and task types. The built-in `SoftwareDomain` covers Swift/Xcode workflows. Domains inject a `systemPromptAddendum` into the system prompt for the active slot.

**Complexity Classification** — `PlannerEngine` classifies each message into one of three tiers:

| Tier | Routing |
|---|---|
| `routine` | Execute slot, no planning pass |
| `standard` | Execute slot, optional planning pass |
| `high-stakes` | Reason slot, full planning pass |

Override with `#routine`, `#standard`, or `#high-stakes` prefix in your message.

**Critic Engine** — `CriticEngine` scores outputs after the LLM responds without tool calls:

- **Stage 1** — domain verification backend (e.g. `xcodebuild` for Swift tasks)
- **Stage 2** — reason-slot LLM scoring on a 0.0–1.0 scale

Critic verdicts gate xcalibre memory writes: `.fail` suppresses the write so low-quality outputs do not pollute the memory store.

**Performance Tracking** — `ModelPerformanceTracker` builds empirical performance profiles per model × domain × task type from observed outcomes. Profiles are calibrated at 30 samples. Used for model selection and as the data source for LoRA training.

**Skill frontmatter** — skills can declare `role:` (execute/reason/orchestrate/vision) and `complexity:` (routine/standard/high-stakes) in their YAML frontmatter to pre-select routing.

**Settings** — `RoleSlotSettingsView` (Settings → Role Slots), `PerformanceDashboardView` (Settings → Performance).

---

## Performance Tracking

`ModelPerformanceTracker` records an `OutcomeRecord` at the end of every session turn, capturing:

- `OutcomeSignals`: stage1Passed (domain verification), stage2Score (critic LLM score), diffAccepted, diffEditedOnAccept, criticRetryCount, userCorrectedNextTurn, sessionCompleted, addendumHash
- `prompt` and `response` text — stored for LoRA training export

`ModelPerformanceProfile` aggregates these into a per-model × task-type profile with:
- Exponentially-weighted success rate (decay factor 0.9)
- Sample count (calibration minimum: 30 samples)
- Trend: improving / stable / declining

Profile files: `~/.merlin/performance/<model-id>.json`  
Training data files: `~/.merlin/performance/records-<model-id>.json` (persist across restarts)

`exportTrainingData(minScore:)` filters records by score threshold and excludes records with empty prompt or response text — ensuring only high-quality session data enters the LoRA pipeline.

---

## RAG (Retrieval-Augmented Generation)

Connects to a local xcalibre-server instance. When available:

- **Auto-inject** — relevant context chunks are injected into the prompt before each LLM call.
- **Explicit tools** — `rag_search(query, source?, project_path?)` and `rag_list_books()` available as explicit tool calls.
- **Source attribution** — `RAGSourcesView` shows a "Sources" footer in the chat after every RAG-enriched message, listing book titles and memory chunk IDs used.
- **Project scoping** — `AppSettings.projectPath` scopes memory chunk retrieval to the active project path. Set in Settings → Agent.
- **Memory Browser** — `MemoryBrowserView` (Settings → Memories) lets you search and delete individual xcalibre memory chunks.
- **Hardware-configurable** — `ragRerank` (default `false`) and `ragChunkLimit` (default 3) are tunable in Settings. On an RTX 5080, set `ragRerank = true` and `ragChunkLimit = 10` with no code changes.
- **Critic-gated writes** — when the critic returns `.fail`, the memory write to xcalibre is suppressed for that session. This keeps low-quality outputs out of the memory store.

**xcalibre-server hardware** — runs on a Windows 11 machine with RTX 2070, serving phi-3-mini-4k-instruct (library maintenance tasks) and nomic-embed-text-v1.5 (vector embeddings) via LM Studio. `ragRerank` is off by default because the RTX 2070 benefits from the reduced load; the code requires no changes for an RTX 5080 upgrade.

---

## LoRA Self-Training

Merlin can fine-tune a local model on your own accepted sessions using MLX-LM on an M4 Mac with 128GB unified memory.

**How it works**

1. `ModelPerformanceTracker` accumulates `OutcomeRecord` entries after each session turn, storing the user prompt and the model's response.
2. `LoRATrainer.exportJSONL()` serialises records above the score threshold as MLX-LM chat-format JSONL: `{"messages":[{"role":"user","content":"..."},{"role":"assistant","content":"..."}]}`. Records with empty prompt or response are silently skipped.
3. `LoRATrainer.train()` shells out to `python -m mlx_lm.lora --train` with the exported JSONL and writes the adapter to `loraAdapterPath`.
4. When `loraAutoLoad` is true and the adapter file exists, `AppState` constructs a `loraProvider` pointing at `mlx_lm.server` and routes the execute slot through it.
5. `LoRACoordinator` handles threshold-gating (`loraMinSamples`, default 50) and prevents concurrent training runs via `isTraining`.

**Activation**

1. Install MLX-LM: `pip install mlx-lm`
2. Download a base model (see recommendations below)
3. Open Settings → LoRA and enable **LoRA Self-Training**
4. Set **Base Model** to the model path or Hugging Face ID
5. Set **Adapter Path** to a local directory for the trained adapter
6. Set **Server URL** to `http://localhost:8080/v1` (or the port `mlx_lm.server` is listening on)
7. Enable **Auto-Train** to trigger training automatically once the sample threshold is reached
8. Enable **Auto-Load** to route the execute slot through the trained adapter

**Recommended models**

| Model | Purpose | Notes |
|---|---|---|
| `Qwen2.5-Coder-7B-Instruct` | Development and testing | Fits in ~15GB RAM; fast LoRA iterations |
| `Qwen2.5-Coder-32B-Instruct` | Production use | Requires ~65GB; recommended for M4 128GB |

**mlx_lm.server** — after training, serve the adapter:

```bash
python -m mlx_lm.server --model Qwen2.5-Coder-32B-Instruct \
    --adapter-path ~/merlin-adapters/my-adapter \
    --port 8080
```

**ShellRunnerProtocol** — the trainer uses an injectable `ShellRunnerProtocol` so tests inject a stub runner rather than executing real system commands.

---

## Workspace Layout

Five resizable, collapsible panes arranged in the window:

| Pane | Purpose |
|---|---|
| Session Sidebar | Open sessions list, new session button |
| Chat | Primary conversation thread |
| Diff | Staged file changes, Accept/Reject/Comment |
| Terminal | Persistent user-controlled shell (Ctrl+`) |
| File Viewer | Read-only syntax-highlighted file view |
| Preview | WKWebView for local HTML/dev server output |

Layout is draggable and persisted per project. Toggle panes from the View menu.

---

## Floating Pop-Out Window

Pop any session out into a floating window that stays on top of other apps (⌘⇧P). Useful for keeping a session visible while working in another application.

---

## Side Chat

A slide-over ephemeral chat panel (⌘⇧/) — independent context, not persisted. Useful for quick one-off questions without polluting the main session.

---

## Voice Dictation

Press Ctrl+M to start dictating. Speech is transcribed via SFSpeechRecognizer and appended to the prompt input. Press again to stop.

---

## Toolbar Actions

Define custom one-click prompt buttons that appear above the chat input. Configured in `~/.merlin/config.toml` or Settings → Toolbar Actions.

---

## Settings

Full settings window (⌘,) with these sections:

| Section | Contents |
|---|---|
| General | Startup behaviour, default permission mode, notifications, keep-awake |
| Appearance | Theme, UI font, code font, message density, accent colour, live preview |
| Providers | API keys, endpoint URLs, model overrides, enable/disable per provider |
| Agent | Default model, reasoning effort, standing custom instructions |
| Memories | Enable/disable, idle timeout, pending review queue |
| Connectors | GitHub, Slack, Linear tokens and status |
| MCP | MCP server list — add, remove, edit, view connection status |
| Skills | Skill paths, per-skill enable/disable |
| Hooks | View and edit hook definitions inline |
| Search | Brave API key, enable/disable |
| Permissions | Current allow/deny pattern list, clear all |
| Advanced | Open config in Finder, open memories folder, reset to defaults |
| Role Slots | Assign LLM providers to execute / reason / orchestrate / vision slots |
| Performance | ModelPerformanceProfile dashboard per model × task type, trend chart, export training data |
| LoRA | Master toggle, auto-train, min-samples threshold, base model, adapter path, auto-load, server URL |

---

## Subagents

The model can spawn child agents to work in parallel using the `spawn_agent` tool.

**Explorer agents** (read-only) — search the codebase, read files, run read-only shell commands, perform web searches. Results stream back as inline collapsible blocks in the chat.

**Worker agents** (write-capable) — each gets its own isolated git worktree. Changes accumulate in a per-worker staging buffer for review before merge. Workers appear as child entries in the session sidebar.

- Up to 4 concurrent subagents (configurable)
- Up to 2 levels of nesting (configurable)
- Hooks apply to all subagent tool calls
- Custom agent definitions in `~/.merlin/agents/*.toml`

---

## Appearance

- **Theme** — System / Light / Dark
- **UI font** — family and size
- **Code font** — monospace family and size (applied to tool output, code blocks, diff view)
- **Message density** — Compact / Comfortable / Spacious
- **Accent colour** — full colour picker

All appearance settings apply live with a preview pane in Settings.

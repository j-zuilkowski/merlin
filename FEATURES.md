# Merlin — Features

A complete reference of everything Merlin can do. For implementation details see [`spec.md`](spec.md).

---

## LLM Providers

Merlin connects to remote and local providers interchangeably. Routing is controlled by
explicit slot assignments, not by selecting a provider from the chat header.

**Remote**
- Anthropic
- DeepSeek
- OpenAI
- Qwen
- OpenRouter

**Local (no API key required)**

| Provider | Status | Notes |
|---|---|---|
| LM Studio | Fully supported | Recommended. General + vision pair passed live calibration. |
| Jan.ai | Fully supported | Recommended. General + vision pair passed live calibration. |
| LocalAI | Fully supported | Recommended. General + vision pair passed live calibration. |
| llama.cpp (router mode) | Live smoke validated | First-class local provider (`llamacpp`) at `http://localhost:8081/v1`; one router-mode `llama-server` served the local general+vision GGUF pair on May 25, 2026. |
| Ollama | Not recommended | General model works, but the tested vision model crashes the runner on real image requests. |
| vLLM-Metal | Not recommended | General model works, but vision is not implemented in the tested `vllm-metal` runtime on Metal. |
| Mistral.rs | Currently unusable | The tested Qwen3 MoE GGUF model fails on first inference on Metal. |

Upstream issue tracking for the malfunctioning local providers is recorded in
[`docs/local-provider-configs/RESULTS.md`](docs/local-provider-configs/RESULTS.md).

All providers share a single configuration surface (Settings → Providers). API keys are file-backed at `~/.merlin/api-keys.json` for Debug/dev-loop builds and stored in macOS Keychain for Release builds. The pre-push and CI gates block tracked local-only key files. Local providers are auto-probed for availability at launch.

---

## Agentic Engine

- **Autonomous loop** — the model calls tools, reads results, and continues until the task is complete. No user intervention required between steps.
- **Parallel tool calls** — multiple tools dispatched concurrently via Swift structured concurrency.
- **Interrupt at any time** — Stop button cancels the active turn cleanly; the session remains in a valid state.
- **Error retry** — first failure retries silently; second failure surfaces to the user with Retry / Skip / Abort options.
- **Context compaction** — old tool results are summarised automatically at three trigger points: (1) pre-run when estimated tokens exceed 6,000, (2) mid-loop every time tool results push past 20,000 tokens within a single turn, and (3) emergency overflow at 800,000 tokens. Mid-loop summarisation uses the active LLM to produce a narrative digest of removed exchanges rather than a static truncation marker, so the model retains a meaningful summary of what it already did. Type `/compact` in the chat bar or use Session → Compact Context (⌘⇧K) to compact on demand. (Authoritative values in `ContextManager.swift`; see constitution.md → Canonical Defaults.)
- **Context-length recovery** — when the provider rejects a prompt as too long (HTTP 400 "context_length_exceeded"), Merlin compacts automatically and retries the failed turn once rather than stopping.
- **Thinking mode** — automatically enabled for reasoning-heavy prompts (architecture, debugging, analysis) when the active provider supports it. Suppressed for simple operations.
- **Reasoning effort** — configurable per provider; overridable per session.
- **Scroll lock** — scrolling up during a streaming response pauses auto-scroll and shows a "Resume auto-scroll" banner. Clicking the banner or sending a new message snaps back to the bottom.
- **Checkpoint restoration (`/rewind`)** — Merlin saves a snapshot before each user turn. Type `/rewind` to restore to the previous checkpoint, or `/rewind N` to go back N steps. Restores both the context window and the visible conversation. Up to 50 checkpoints are retained per session.
- **Side questions (`/btw`)** — type `/btw <question>` to open a floating overlay that sends a one-shot question directly to the active provider. The response appears in the overlay without touching the conversation history or context window. Dismiss with Esc or a click outside.

---

## CAG — Cache-Augmented Generation

- CAG caches the cold, stable prefix: system prompt, project instructions, domain addenda, pinned docs, and stable tool schemas.
- constitution.md can be kept hot with `pin_constitution = false`; it remains in the request but outside Anthropic's cache-marked block.
- RAG/KAG enrichment, tool results, and user turns remain hot suffix content and are not part of the cacheable prefix.
- Anthropic uses explicit prompt-cache markers (`cache_control`) plus the prompt-caching beta header.
- OpenAI-compatible, DeepSeek, and local providers do not receive Anthropic-specific fields; they benefit from stable prefix bytes when server-side automatic cache or KV reuse is available.
- Cache metrics track read, creation, and uncached input token usage through `CAGCacheUsage` and surface in Settings plus the workspace CAG Metrics panel.

---

## Prompt Compression

Agentic loops accumulate context quadratically — every step sends the full history to the model, so a 100-step run with a 5 K-token history costs 500 K tokens in total. Merlin applies three complementary compression strategies to keep per-turn cost linear regardless of session length. The approach is informed by ["Implementing Prompt Compression to Reduce Agentic Loop Costs"](https://machinelearningmastery.com/implementing-prompt-compression-to-reduce-agentic-loop-costs/) (MachineLearningMastery.com).

### Mid-loop compaction

`ContextManager` tracks estimated tokens after every tool result is appended to the context. When tokens exceed the **mid-loop threshold** (20,000 by default), compaction fires immediately — inside the `while true` execute loop, before the next LLM request is built. This prevents a long tool chain from silently growing the context window across dozens of iterations without the model (or the user) realising.

The threshold is intentionally well below the provider's context window so there is always ample headroom for the next LLM response. Compaction removes the oldest complete tool-exchange groups (an assistant message with `tool_calls` together with all its `tool` result messages) so the context never violates the OpenAI wire format.

### LLM summarisation (recursive summarisation)

When mid-loop compaction fires, the removed tool exchanges are passed to the active LLM provider as a compact one-shot summarisation request (no tools, temperature 0). The model produces a short narrative digest — "read `Engine.swift`, found the run loop at line 550, patched lines 711–715, ran tests: 3 passed" — which is inserted as a `system` message in place of the raw exchanges.

This contrasts with the overflow path (800 K tokens) and the pre-run path (6 K tokens), which both use a static truncation marker rather than an LLM call. The mid-loop path spends one cheap summarisation call to preserve task continuity across hundreds of tool steps.

### Instruction distillation

The core system prompt and the user's `constitution.md` file are sent verbatim on every single LLM request. In a 100-step loop, a 2 K-token system prompt costs 200 K tokens in overhead before any work is done.

Merlin addresses this in two layers:

- **Static distillation** — the built-in `coreSystemPrompt` is expressed in a compact, symbol-dense form (~6 lines) that conveys the same constraints as the original 18-line prose version at a fraction of the token count.
- **Dynamic distillation** — when `promptCompressionEnabled` is `true` (Settings → Agent → Prompt Compression), Merlin calls the reason-slot provider once to compress the project's `constitution.md` into a shorthand equivalent. The distilled version is cached against a hash of the original; it is only re-distilled when the source file changes. `buildStablePrefix()` uses the distilled variant for every subsequent request in the session.

Enable dynamic distillation in **Settings → Agent → Prompt Compression** or via `prompt_compression_enabled = true` in `~/.merlin/config.toml`. The distillation call is made once per changed `constitution.md`, not per turn.

**Token savings summary**

| Technique | Trigger | Savings mechanism |
|---|---|---|
| Mid-loop compaction | 20,000 tokens within a turn | Removes old tool exchanges; keeps context linear |
| LLM summarisation | Mid-loop compaction path | Preserves task continuity with a narrative digest |
| Instruction distillation | Per session (dynamic) or static | Shrinks system prompt sent on every request |

---

## Inference Settings

Merlin persists default sampling values in the `[inference]` TOML section and applies them only when a request leaves the corresponding field unset.

- `applyInferenceDefaults(to:)` fills nil fields without overwriting explicit per-request overrides.
- Supported keys are `temperature`, `max_tokens`, `top_p`, `top_k`, `min_p`, `repeat_penalty`, `frequency_penalty`, `presence_penalty`, `seed`, and `stop`.
- `stop` is stored as a list of stop strings; leaving it empty preserves provider defaults.
- These defaults feed the OpenAI-compatible `CompletionRequest` payload used by the provider adapters.

---

## Local Model Management

Local providers expose load-time controls in Settings → Providers. The editor only shows fields that the provider manager advertises through `supportedLoadParams`.

- `ModelControlView` lets you edit local load-time parameters per provider and then either reload in place or display restart instructions.
- The lower-left sidebar `SlotStatusPanel` always shows Execute, Reason, Orchestrate, and Vision rows from explicit slot assignments.
- Unassigned rows remain visible and are labelled `Not configured`; enabling a provider by itself does not populate slot rows.
- Slot status dots use grey for unconfigured, green for ready/finished, orange for busy, and red for the last failed turn on that slot.
- LM Studio, Ollama, Jan.ai, and llama.cpp router mode can reload model presence at runtime.
- LocalAI, Mistral.rs, and vLLM-Metal are restart-only and surface a copyable command plus any config snippet they need.
- LM Studio, Ollama, and Jan.ai now all participate in advisory-driven context auto-resize. Restart-only providers still require the manual restart flow.
- llama.cpp uses router endpoints (`/models`, `/models/load`, `/models/unload`) when available; single-model `/v1/models` servers fall back to restart guidance using the current `llama-server --models-dir` and `--models-preset` flags.
- Recommended local providers for full general+vision use are LM Studio, Jan.ai, and LocalAI.
- Ollama and vLLM-Metal remain available for general-model use, but are not recommended for pair calibration because the tested vision path failed live.
- Mistral.rs remains listed for completeness, but is currently unusable for the tested Qwen3 MoE model on Apple Metal.
- The Performance Dashboard automatically detects truncation, critic-score variance, trigram repetition, and context-overflow markers.
- Each advisory has a one-tap `Fix this` action that routes through the same `applyAdvisory(_:)` path used by the engine.

## Model Calibration (`/calibrate`)

Type `/calibrate` in the chat bar to benchmark the active local model against any configured
remote provider (Anthropic, OpenAI, DeepSeek, etc.).

**What it does:**
- Runs an 18-prompt battery (reasoning, coding, instruction-following, summarization). For each prompt, the local and reference provider run in parallel; prompts themselves run sequentially to avoid saturating local backends.
- Critic-scores every response pair and computes per-category and overall score gaps.
- Identifies up to four parameter issues: context length too small, temperature too high,
  output truncation, and repetitive output.
- Shows a report with a side-by-side score breakdown and one-tap "Apply All Suggestions"
  that routes fixes through the existing advisory pipeline (runtime reload where supported,
  restart instructions where not).
- Surfaces degraded critic fallback explicitly in the report instead of quietly treating it as a normal score.

**What it cannot fix:**
- Model weight quality - use the LoRA self-training pipeline (`/lora`) for that.
- Provider network latency or API rate limits.

---

## Multi-Provider Setup

On first launch, a setup wizard lets you pick and configure any provider. You can skip it and configure later in Settings → Providers.

---

## Projects & Workspace

- **Multi-project workspace** — a single window holds multiple open projects simultaneously. Each project occupies its own section in the sidebar; the content area shows the active session from any project.
- **Project picker** — lists recent projects with last-opened timestamps. One click to add a project to the workspace. Accessible from ⌘N or the "+ New Project Workspace" button.
- **Workspace persistence** — open projects and the active session are saved to `~/.merlin/workspace.json` and restored automatically on relaunch. No manual reopening required.
- **Close project** — tap the project header to open a popover with "New Session" and "Close Project" actions.
- **Pane layout persistence** — sidebar width, visible panes, and chat panel state are saved to `~/.merlin/layout-workspace.json`.

---

## Sessions

- **Sessions per project** — each project has its own list of sessions in the sidebar, each with its own context, provider, and permission mode.
- **Session sidebar** — lists active sessions with title, activity indicator, and relative timestamp. Switch instantly by clicking any row.
- **Session history** — all past sessions are stored per project (`~/Library/Application Support/Merlin/sessions/<project-id>/`). Prior sessions (not currently live) are listed under "Prior Sessions" in the sidebar with relative timestamps (2h, 3d, 1w).
- **Auto-title** — after the first turn completes, the session title is automatically generated from the first 50 characters of the user's message, matching Claude app and Codex behaviour. No manual rename required. (v1.8.1: each new session is registered in `SessionStore` on init so title generation works from the very first turn.)
- **Session isolation** — each new session gets its own `ContextManager`, message history, and `AppState`. Switching sessions switches the entire view tree; no state bleeds between sessions. (v1.8.1: `.id(session.id)` on `ContentView` forces SwiftUI to fully recreate the view when the active session changes.)
- **Activity indicator** — a small dot in the sidebar row shows when a session's engine is running. Clears automatically when the engine finishes, even if the session is not the active view. (v1.8.1: `AppState` observes `engine.isRunning` via Combine and resets `toolActivityState` directly, so the dot always clears.)
- **Context compaction** — old tool-result groups are removed automatically at three points: pre-run (6,000 tokens), mid-loop (20,000 tokens, with LLM summarisation), and overflow (800,000 tokens). Session → Compact Context (⌘⇧K) forces immediate compaction. When the context has no tool-exchange groups, compaction hard-truncates to the last 20 messages instead of appending a no-op sentinel.
- **Archive & recall** — sessions can be archived (hidden from the main list) via right-click context menu. Archived sessions are revealed under "Show archived…" and can be recalled to active status at any time.
- **Session restore** — clicking a prior session restores it as a live session with its full message history. If the restored history exceeds 10 000 estimated tokens, context compaction runs automatically before the next prompt.
- **Git worktree isolation** — each session works in its own git worktree so parallel sessions never conflict on disk.
- **New Session shortcut** — ⌘N opens the project picker to add a new project workspace.

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
- **constitution.md auto-load** — at session start, Merlin searches for `constitution.md` files from the project root upward and prepends them to the system prompt.
- **Memory injection** — accepted AI-generated memories are injected as a second system prompt block every session.

---

## AI-Generated Memories

Opt-in. After 5 minutes of session inactivity, Merlin uses the fastest available model to distill the session transcript into a memory file. Memories capture preferences, workflow conventions, project patterns, and known pitfalls — never raw file contents or secrets.

- Pending memories appear in Settings → Memories for review before acceptance.
- Accepted memories follow two paths simultaneously:
  1. **File injection** — moved to `~/.merlin/memories/` and prepended to the system prompt as a verbatim block at the start of every future session.
  2. **Local RAG indexing** — written to Merlin's local SQLite memory store as a `"factual"` chunk tagged `"session-memory"`, making them queryable by the RAG layer so only contextually relevant memories surface per prompt rather than all memories all the time.

---

## Local Memory Storage (v9)

Merlin stores approved memories and session summaries in a local SQLite database, so session memory no longer depends on an external server.

**How it works:**
- Approved memories from the Memory Review sheet are written as `factual` chunks.
- Session summaries are written as `episodic` chunks at the end of each turn, unless the critic marks the turn as failed.
- Both chunk types are embedded with Apple's built-in `NLContextualEmbedding` model on macOS 14+.
- At the start of each turn, Merlin retrieves the top-5 matching chunks by cosine similarity and prepends them to the user message as RAG context.

**Plugin system:**
- The backend is selectable in Settings → Memories → Memory backend.
- `Local (on-device)` is the default and stores data at `~/.merlin/memory.sqlite`.
- `None` disables memory persistence for ephemeral sessions.
- xcalibre-server remains available as an optional book-content source; it is no longer used for Merlin session memory.

---

## Behavioral Reliability

Merlin's reliability features address four failure patterns described in ["Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems"](https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems) (S. Patil, VentureBeat, 2025).

| Failure pattern | What goes wrong | Merlin's response |
|---|---|---|
| **Context degradation** | The model's retrieval becomes stale or incomplete. Answers look polished but lose grounding — the model doesn't know what it doesn't know. | `GroundingReport` is emitted every turn: chunk count, average cosine score, staleness flag, and `isWellGrounded`. Visible in the Tool Log. |
| **Orchestration drift** | Multi-step agentic runs diverge over time — small errors compound across tool calls until the output no longer matches the original intent. | `CriticEngine` scores every turn independently. `ModelParameterAdvisor` tracks score variance across sessions and surfaces an advisory before drift becomes visible. |
| **Silent partial failure** | A subsystem degrades before it fully breaks. Each individual turn looks acceptable; the cumulative pattern does not. | The circuit breaker counts consecutive critic failures. After `agentCircuitBreakerThreshold` (default 3) failures, it halts the engine and notifies the user. Nothing fails silently. |
| **Automation blast radius** | A bad step in an agentic loop propagates into later steps and decisions, compounding the damage before anything is flagged. | `AuthGate` blocks unauthorised tool calls at the boundary. Critic failures suppress memory writes, so low-quality outputs cannot pollute the retrieval store and corrupt future sessions. |

### Circuit Breaker

After `agentCircuitBreakerThreshold` consecutive critic `.fail` verdicts (default: 3), the engine activates:

- **Halt mode** (default) — stops the next turn cleanly and emits a system note directing the user to act.
- **Warn mode** — emits a warning but lets the turn proceed.

The counter resets to zero on any `.pass` or `.skipped` verdict, and on every new session. Configure in **Settings → Agent** or via `agent_circuit_breaker_threshold` / `agent_circuit_breaker_mode` in `~/.merlin/config.toml`.

### Grounding Confidence

Every turn emits a `GroundingReport` as an `AgentEvent`, even when no chunks were retrieved. The report contains:

| Field | Meaning |
|---|---|
| `totalChunks` | Number of RAG chunks injected this turn |
| `averageScore` | Mean cosine similarity across all chunks (0–1) |
| `hasStaleMemory` | True when any memory chunk is older than `ragFreshnessThresholdDays` (default: 90 days) |
| `isWellGrounded` | True when `totalChunks > 0` and `averageScore ≥ ragMinGroundingScore` (default: 0.30) |

Configure thresholds in **Settings → Agent** or via `rag_freshness_threshold_days` / `rag_min_grounding_score` in `~/.merlin/config.toml`.

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

Set recurring agent sessions on an hourly, daily, or weekly schedule. Each scheduled task specifies a project, a prompt or skill, a time, and a permission mode. On fire, Merlin opens a background session, waits for MCP startup, runs the prompt to completion, and posts a macOS notification with a summary.

---

## Thread Automations

Legacy internal scheduling scaffolding for per-session follow-up prompts. This is not a supported user-facing feature in the current product surface.

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

Brave Search integration. When a Brave API key is configured in **Settings → Search** (see [Settings reference](#settings-reference) — `Search` row), a `web_search` tool is registered and available to the agent. Disabled entirely when no key is present.

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

Unassigned slot fallback is runtime-based:
- `execute` → active provider
- `reason` → active provider
- `orchestrate` → `reason`, then active provider
- `vision` → active provider unless a dedicated vision-capable provider is assigned

**Domain System** — `DomainRegistry` holds pluggable `DomainPlugin` instances that supply domain-specific verification commands and task types. Built-in domains are `SoftwareDomain` and `ElectronicsDomain`; external MCP domain manifests register through `MCPDomainAdapter`. Domains inject a `systemPromptAddendum` into the system prompt for the active slot.

### V2.0 Electronics Domain (KiCad)

KiCad integration is a first-class domain extension with deterministic completion gates: raster/PDF schematic ingestion, KiCad CLI as primary authority, the Merlin-owned `merlin-kicad-mcp` server for structured operations (schematic, board, placement, routing, library, simulation), FreeRouting-backed auto-route, ERC/DRC/parity/SPICE/fab gates, and vendor-native BOM/order workflows for JLCPCB / PCBWay / OSHPark / custom. High-stakes designs (hazardous energy, isolation, mission-critical) require explicit user sign-off; visual QA can block on presentation issues but cannot override electrical or fabrication gates.

Requires KiCad `>= 10.0.0`. Full design (locked v2.0 decisions, extraction-confidence thresholds, board-rule defaults, BOM canonical model, fab acceptance checks, terminal status codes) is specified in [spec.md → V2.0 Electronics/KiCad Domain](spec.md#v20-electronics-domain). See also [Requirements.md §6](Requirements.md#6-kicad--electronics-domain) for tooling versions.

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

Critic verdicts gate local memory writes: `.fail` suppresses the episodic backend write so low-quality outputs do not pollute the memory store.

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

Connects to Merlin's local memory store and, when configured, an optional xcalibre-server book-content source. When available:

- **Auto-inject** — relevant context chunks are injected into the prompt before each LLM call.
- **Explicit tools** — `rag_search(query, source?, project_path?)` and `rag_list_books()` available as explicit tool calls.
- **Source attribution** — `RAGSourcesView` shows a "Sources" footer in the chat after every RAG-enriched message, listing book titles and memory chunk IDs used.
- **Project scoping** — `AppSettings.projectPath` scopes memory chunk retrieval to the active project path. Set in Settings → Agent.
- **Memory Browser** — `MemoryBrowserView` (Settings → Memories) lets you search and delete individual memory chunks.
- **Hardware-configurable** — `ragRerank` (default `false`) and `ragChunkLimit` (default 3) are tunable in Settings. On an RTX 5080, set `ragRerank = true` and `ragChunkLimit = 10` with no code changes.
- **Critic-gated writes** — when the critic returns `.fail`, the episodic memory write is suppressed for that session. This keeps low-quality outputs out of the memory store.

**xcalibre-server hardware** — when present, it runs on a Windows 11 machine with RTX 2070, serving phi-3-mini-4k-instruct (library maintenance tasks) and nomic-embed-text-v1.5 (vector embeddings) via LM Studio. `ragRerank` is off by default because the RTX 2070 benefits from the reduced load; the code requires no changes for an RTX 5080 upgrade.

---

## KAG — Knowledge-Augmented Generation

KAG adds a structured knowledge graph layer alongside the RAG vector store. Where RAG retrieves semantically similar chunks ("what was said about X"), KAG retrieves *relationships* ("which entities relate to X and how"). Available from v1.8.0.

**Why KAG?** For non-software domains — PCB design, construction, cooking, finance — there is no `grep` equivalent for "which components share a power net" or "which structural members carry this load." KAG provides graph traversal for any domain where entities have relational structure.

**How it works**

After every assistant turn (when `kagEnabled = true` in Settings → Agent):

1. `KAGEngine.scheduleExtraction(from:domain:)` fires after a 2-second idle delay to avoid blocking the UI.
2. A background LLM call extracts `(subject, predicate, object)` triples from the assistant's response text.
3. Triples are written to the active KAG backend — either `LocalKAGPlugin` (SQLite at `~/.merlin/kag/graph.sqlite`) or `XcalibreKAGPlugin` (preferred when xcalibre-server is configured).
4. At retrieval time, `RAGTools.buildEnrichedMessage` injects a graph subgraph (traversal up to `kagHops` hops) alongside the vector chunks.

**KAG backends**

| Backend | Storage | Use case |
|---|---|---|
| `LocalKAGPlugin` (default fallback) | `~/.merlin/kag/graph.sqlite` | Fully local; no xcalibre-server required |
| `XcalibreKAGPlugin` (preferred) | xcalibre-server via REST | Fuses session triples with book knowledge triples in a single traversal; cross-session persistence |

**xcalibre-server integration** — `XcalibreKAGPlugin` writes session triples to `POST /api/v1/graph/triples` and queries via `GET /api/v1/graph/traverse`. Book-level triples are extracted at ingestion time on the xcalibre side. The query response merges book knowledge with session working triples transparently.

**Settings**

| Key | Default | Description |
|---|---|---|
| `kagEnabled` | `false` | Master toggle in Settings → Agent |
| `kagHops` | `2` | Graph traversal depth at retrieval time |
| `kagXcalibreURL` | `""` | URL of xcalibre-server instance; empty = use LocalKAGPlugin |

**Test injection** — `KAGEngine` accepts a `kagEngine` parameter in `AgenticEngine.init` (default `.shared`) so unit tests inject a mock `KAGEngine` without affecting the singleton. `KAGEngine.pendingTask` is `private(set)` so tests can assert extraction was scheduled.

---

## LoRA Self-Training (MLX-format base models)

Merlin can fine-tune a local MLX-format model on your own accepted sessions using MLX-LM on an M4 Mac with 128GB unified memory. Automatic training requires an MLX base — `mlx_lm.lora` cannot train GGUF or HF-safetensors bases directly.

The trained adapter is served by an **MLX-native runtime**. Three runtimes serve MLX format directly:

| Runtime | How to deploy the trained adapter |
|---|---|
| `mlx_lm.server` | Direct: `--adapter-path <adapter>` on top of the base (default Merlin routing target) |
| **LM Studio** | Direct: load adapter via the LM Studio UI |
| **vLLM-Metal** | `mlx_lm.fuse --model <base> --adapter-path <adapter> --save-path <merged>` then `vllm serve <merged>` — no GGUF conversion required, but not recommended for the current general+vision pair workflow |

GGUF providers (**Ollama**, **Jan.ai**, **LocalAI**, **llama.cpp**) require an additional step: fuse the adapter, then convert to GGUF via `llama.cpp/convert_hf_to_gguf.py`. **Mistral.rs cannot serve Qwen3-MoE on Metal** today regardless of fine-tuning (see Per-Provider Notes below) — fine-tuning targeting Mistral.rs is only useful for non-MoE base models.

**How it works**

1. `ModelPerformanceTracker` accumulates `OutcomeRecord` entries after each session turn, storing the user prompt and the model's response.
2. `LoRATrainer.exportJSONL()` serialises records above the score threshold as MLX-LM chat-format JSONL: `{"messages":[{"role":"user","content":"..."},{"role":"assistant","content":"..."}]}` (filtering is upstream — see `exportTrainingData(minScore:)` above).
3. `LoRATrainer.train()` shells out to `python -m mlx_lm.lora --train` with the exported JSONL and writes the adapter to `loraAdapterPath`.
4. When `loraAutoLoad` is true and the adapter file exists, `AppState` constructs a `loraProvider` pointing at `mlx_lm.server` and routes the execute slot through it. (Future: routing to vLLM-Metal or LM Studio as alternative MLX runtimes is a Settings-level choice rather than a fixed default.)
5. `LoRACoordinator` handles threshold-gating (`loraMinSamples`, default 1000) and prevents concurrent training runs via `isTraining`.

**Activation**

1. Install MLX-LM: `pip install mlx-lm`
2. Download a base model (see recommendations below)
3. Open Settings → LoRA and enable **LoRA Self-Training**
4. Set **Base Model** to the model path or Hugging Face ID
5. Set **Adapter Path** to a local directory for the trained adapter
6. Pick **Serving runtime** (Settings → LoRA → Inference):
   - **mlx_lm.server** (default) — direct adapter load. Launch with
     `python -m mlx_lm.server --model <base> --adapter-path <adapter> --port 8080`
   - **vLLM-Metal** — fuse first via `mlx_lm.fuse --model <base> --adapter-path <adapter> --save-path <merged>`,
     then `vllm serve <merged> --port 8000 --enable-auto-tool-choice --tool-call-parser qwen3_coder`
     (text-only use is the safer assumption; not recommended for the current general+vision pair workflow)
   - **LM Studio** — load the base + attach the adapter via the LM Studio UI; endpoint `:1234/v1`
   - **Custom** — any other MLX-compatible OpenAI-compat endpoint
7. Set **Server URL** to match the chosen runtime (the picker pre-fills sensible defaults)
8. Enable **Auto-Train** to trigger training automatically once the sample threshold is reached
9. Enable **Auto-Load** to route the execute slot through the trained adapter

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

Six panes in a single window, all collapsible via the toolbar:

| Pane | Purpose |
|---|---|
| Session Sidebar | All open projects and their sessions; switch projects and sessions instantly |
| Chat | Primary conversation thread for the active session |
| Diff | Staged file changes, Accept/Reject/Comment |
| Terminal | Persistent user-controlled shell (Ctrl+\`); working directory follows the active project |
| File Viewer | Read-only syntax-highlighted file view |
| Preview | WKWebView for local HTML/dev server output |
| Side Chat | Slide-over ephemeral chat panel (⌘⇧/); scoped to the active project |

Pane visibility is persisted to `~/.merlin/layout-workspace.json`. Toggle from the View menu or toolbar buttons.

---

## Floating Pop-Out Window

Pop any session out into a floating window that stays on top of other apps (⌘⇧P). Useful for keeping a session visible while working in another application.

---

## Side Chat

A slide-over ephemeral chat panel (⌘⇧/) — independent context, not persisted. Scoped to the active project's working directory. Useful for quick one-off questions without polluting the main session.

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
- Nested `spawn_agent` from inside a subagent is currently rejected explicitly rather than supported recursively.
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

---

## Project Discipline (v2.2)

Merlin can enforce construction discipline automatically — running scanners after every turn, surfacing findings at session start, and blocking bad commits via git hooks. Five skills give you deliberate control over the creation side.

### The five project skills

| Skill | What it does |
|---|---|
| `/project:init` | Scaffold a new project with constitution.md, doc set, task structure, and git hooks |
| `/project:task` | Build a TDD task pair (NNa failing tests + NNb implementation) for one new surface |
| `/project:revise` | Run the discipline scanner, review findings, and accept or dismiss each one |
| `/project:release` | Consolidated release gate — verifies tests, docs, version bump, then tags and publishes |
| `/project:adopt` | Apply discipline to an existing project without rewriting its history |

### Enforcement layers

Three layers enforce discipline. Only the first requires you to act.

**Layer 1 — Creation skills (manual).** The five skills above. Use them when you want to create something.

**Layer 2 — DisciplineEngine + hooks (automatic).** After every turn, the engine scans the project for drift and queues findings in `.merlin/pending.json`. At session start, the top findings appear as a system reminder. Silent when everything is healthy.

**Layer 3 — Git hooks (hard gates).** Installed by `/project:init` or `/project:adopt`. Block commits when violations are present: missing WHY-comments, user-facing surfaces with no manual coverage, task files that no longer match the code.

### Adopting an existing project

`/project:adopt` applies discipline to a codebase that wasn't built with Merlin. It detects the language, reads existing documentation, runs a full scan, and installs the enforcement layers. Because existing projects always have coverage gaps, it records the current gap count as a baseline and requires the gap to shrink by a configurable amount with each release — forward work continues in parallel while the backlog closes incrementally.

### Adapters

Discipline rules are language-aware. Adapters (TOML files in `~/.merlin/adapters/`) declare the build command, test command, version file, WHY-comment trigger patterns, and manual-coverage surface patterns for each language. Seed adapters ship for Swift/Xcode and Rust/Cargo.

---

## Comparison: Merlin vs. Codex vs. Claude Code

Merlin, OpenAI Codex, and Anthropic Claude Code are all agentic coding tools with autonomous loop execution, file operations, and shell access. They diverge significantly in architecture, provider strategy, and target use case.

The detailed side-by-side analysis lives in two dedicated documents that stay current with the latest Codex / Claude Code releases:

- [**codex-gap.md**](codex-gap.md) — Merlin vs. OpenAI Codex App
- [**claude-code-gap.md**](claude-code-gap.md) — Merlin vs. Anthropic Claude Code

Both documents cover the per-feature comparison table, Merlin's advantages (provider freedom, multi-LLM routing, MLX LoRA self-training, prompt compression, persistent RAG memory, staged diff review, auth gate, deep Xcode integration, project discipline enforcement, native macOS integration), and the gaps Merlin doesn't close (cloud-side sandbox execution, remote devbox SSH, plugin marketplaces, IDE integrations).

**Short version:** Merlin is built for a single developer on Apple Silicon who wants full control over every layer — which models run, what they can touch, how outputs are reviewed, and how the system improves over time from their own data. Codex is built for teams in the OpenAI ecosystem who want cloud-isolated execution. Claude Code is built for developers who want a capable, low-friction CLI agent in the Anthropic ecosystem.

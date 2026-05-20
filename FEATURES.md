# Merlin — Features

A complete reference of everything Merlin can do. For implementation details see [`architecture.md`](architecture.md).

---

## LLM Providers

Merlin connects to remote and local providers interchangeably. Switch mid-session from the toolbar.

**Remote**
- Anthropic
- DeepSeek
- OpenAI
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
- **Context compaction** — old tool results are summarised automatically at three trigger points: (1) pre-run when estimated tokens exceed 10,000, (2) mid-loop every time tool results push past 40,000 tokens within a single turn, and (3) emergency overflow at 800,000 tokens. Mid-loop summarisation uses the active LLM to produce a narrative digest of removed exchanges rather than a static truncation marker, so the model retains a meaningful summary of what it already did. Type `/compact` in the chat bar or use Session → Compact Context (⌘⇧K) to compact on demand.
- **Context-length recovery** — when the provider rejects a prompt as too long (HTTP 400 "context_length_exceeded"), Merlin compacts automatically and retries the failed turn once rather than stopping.
- **Thinking mode** — automatically enabled for reasoning-heavy prompts (architecture, debugging, analysis) when the active provider supports it. Suppressed for simple operations.
- **Reasoning effort** — configurable per provider; overridable per session.
- **Scroll lock** — scrolling up during a streaming response pauses auto-scroll and shows a "Resume auto-scroll" banner. Clicking the banner or sending a new message snaps back to the bottom.
- **Checkpoint restoration (`/rewind`)** — Merlin saves a snapshot before each user turn. Type `/rewind` to restore to the previous checkpoint, or `/rewind N` to go back N steps. Restores both the context window and the visible conversation. Up to 50 checkpoints are retained per session.
- **Side questions (`/btw`)** — type `/btw <question>` to open a floating overlay that sends a one-shot question directly to the active provider. The response appears in the overlay without touching the conversation history or context window. Dismiss with Esc or a click outside.

---

## Prompt Compression

Agentic loops accumulate context quadratically — every step sends the full history to the model, so a 100-step run with a 5 K-token history costs 500 K tokens in total. Merlin applies three complementary compression strategies to keep per-turn cost linear regardless of session length. The approach is informed by ["Implementing Prompt Compression to Reduce Agentic Loop Costs"](https://machinelearningmastery.com/implementing-prompt-compression-to-reduce-agentic-loop-costs/) (MachineLearningMastery.com).

### Mid-loop compaction

`ContextManager` tracks estimated tokens after every tool result is appended to the context. When tokens exceed the **mid-loop threshold** (40,000 by default), compaction fires immediately — inside the `while true` execute loop, before the next LLM request is built. This prevents a long tool chain from silently growing the context window across dozens of iterations without the model (or the user) realising.

The threshold is intentionally well below the provider's context window so there is always ample headroom for the next LLM response. Compaction removes the oldest complete tool-exchange groups (an assistant message with `tool_calls` together with all its `tool` result messages) so the context never violates the OpenAI wire format.

### LLM summarisation (recursive summarisation)

When mid-loop compaction fires, the removed tool exchanges are passed to the active LLM provider as a compact one-shot summarisation request (no tools, temperature 0). The model produces a short narrative digest — "read `Engine.swift`, found the run loop at line 550, patched lines 711–715, ran tests: 3 passed" — which is inserted as a `system` message in place of the raw exchanges.

This contrasts with the overflow path (800 K tokens) and the pre-run path (10 K tokens), which both use a static truncation marker rather than an LLM call. The mid-loop path spends one cheap summarisation call to preserve task continuity across hundreds of tool steps.

### Instruction distillation

The core system prompt and the user's `CLAUDE.md` file are sent verbatim on every single LLM request. In a 100-step loop, a 2 K-token system prompt costs 200 K tokens in overhead before any work is done.

Merlin addresses this in two layers:

- **Static distillation** — the built-in `coreSystemPrompt` is expressed in a compact, symbol-dense form (~6 lines) that conveys the same constraints as the original 18-line prose version at a fraction of the token count.
- **Dynamic distillation** — when `promptCompressionEnabled` is `true` (Settings → Agent → Prompt Compression), Merlin calls the reason-slot provider once to compress the project's `CLAUDE.md` into a shorthand equivalent. The distilled version is cached against a hash of the original; it is only re-distilled when the source file changes. `buildStablePrefix()` uses the distilled variant for every subsequent request in the session.

Enable dynamic distillation in **Settings → Agent → Prompt Compression** or via `prompt_compression_enabled = true` in `~/.merlin/config.toml`. The distillation call is made once per changed `CLAUDE.md`, not per turn.

**Token savings summary**

| Technique | Trigger | Savings mechanism |
|---|---|---|
| Mid-loop compaction | 40,000 tokens within a turn | Removes old tool exchanges; keeps context linear |
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
- LM Studio, Ollama, and Jan.ai can reload at runtime.
- LocalAI, Mistral.rs, and vLLM are restart-only and surface a copyable command plus any config snippet they need.
- The Performance Dashboard automatically detects truncation, critic-score variance, trigram repetition, and context-overflow markers.
- Each advisory has a one-tap `Fix this` action that routes through the same `applyAdvisory(_:)` path used by the engine.

## Model Calibration (`/calibrate`)

Type `/calibrate` in the chat bar to benchmark the active local model against any configured
remote provider (Anthropic, OpenAI, DeepSeek, etc.).

**What it does:**
- Sends an 18-prompt battery (reasoning, coding, instruction-following, summarization) to both
  the local and reference provider simultaneously.
- Critic-scores every response pair and computes per-category and overall score gaps.
- Identifies up to four parameter issues: context length too small, temperature too high,
  output truncation, and repetitive output.
- Shows a report with a side-by-side score breakdown and one-tap "Apply All Suggestions"
  that routes fixes through the existing advisory pipeline (runtime reload where supported,
  restart instructions where not).

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
- **Context compaction** — old tool-result groups are removed automatically at three points: pre-run (10,000 tokens), mid-loop (40,000 tokens, with LLM summarisation), and overflow (800,000 tokens). Session → Compact Context (⌘⇧K) forces immediate compaction. When the context has no tool-exchange groups, compaction hard-truncates to the last 20 messages instead of appending a no-op sentinel.
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
- **CLAUDE.md auto-load** — at session start, Merlin searches for `CLAUDE.md` files from the project root upward and prepends them to the system prompt.
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

**Behavioral reliability:**

- **Circuit breaker** — after `agentCircuitBreakerThreshold` consecutive critic `.fail` verdicts (default: 3), the engine activates. In `halt` mode (default) it stops the next turn cleanly and emits a `systemNote` directing the user to act. In `warn` mode it emits a warning but lets the turn proceed. The counter resets to zero on any `.pass` or `.skipped` verdict, and on every new session. Addresses the *silent partial failure* pattern — sustained degradation that accumulates below any single-turn alert threshold. Configure in Settings → Agent or via `agent_circuit_breaker_threshold` / `agent_circuit_breaker_mode` in `~/.merlin/config.toml`.

- **Grounding confidence** — every turn emits a `GroundingReport` as an `AgentEvent`, even when no chunks were retrieved. The report contains: `totalChunks` (chunks injected this turn), `averageScore` (mean cosine similarity, 0–1), `hasStaleMemory` (true when any injected memory chunk is older than `ragFreshnessThresholdDays`, default 90), and `isWellGrounded` (true when `totalChunks > 0` and `averageScore ≥ ragMinGroundingScore`, default 0.30). Both thresholds are configurable in Settings → Agent or via `rag_freshness_threshold_days` / `rag_min_grounding_score` in `~/.merlin/config.toml`. Addresses the *context degradation* pattern — the model reasoning confidently over stale or thin retrieval in a way invisible to the user.

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

### V2.0 Electronics Domain (KiCad)

KiCad integration is defined as a first-class domain extension with deterministic completion gates.

**Locked v2.0 decisions**
- Raster/PDF schematic ingestion is in scope.
- Merlin owns the `merlin-kicad-mcp` server.
- Extraction confidence is measured from geometry, OCR, library, net-graph, and cross-pass agreement.
- Ambiguity resolution uses targeted user clarification.
- First MVP board profile is `jlcpcb_2layer_default`, followed by `pcbway_2layer`, `oshpark_2layer`, and `custom`.
- Ethernet/control designs may use IoT/component modules to reduce custom high-speed layout risk.
- Vendor integration includes BOM export, pricing/availability lookup, order preparation, and order submission.
- Layer-count and fabrication-profile changes require user approval.
- Routing uses FreeRouting first through `merlin-kicad-mcp` and KiCad DSN/SES interchange.
- Schematic mutation uses a Merlin-owned `.kicad_sch` parser/writer with round-trip tests.

**Supported intents**
- "Draw me a PCB from this schematic (`.pdf` / `.png` / native KiCad input)."
- "Design a control circuit from requirements and produce schematic + PCB + fab package."

**Execution model (hybrid)**
- KiCad CLI (`>= 10.0.0`) is the primary authority for pass/fail gates.
- Merlin-owned `merlin-kicad-mcp` tools provide structured schematic, board, placement, routing, library, and simulation operations.
- GUI automation + screenshot vision are fallback/QA only and cannot be sole success criteria.

**Schematic extraction**
- PDF/raster extraction uses image preprocessing, geometry tracing, symbol recognition, OCR, junction detection, net graph construction, power-symbol inference, and off-sheet/hierarchical label handling.
- Confidence is computed from weighted geometry, OCR, library matches, net graph plausibility, and cross-pass agreement rather than LLM self-report; contradictions force ambiguity instead of being averaged away.
- Ambiguous nets/components trigger targeted clarification before PCB synthesis.
- Hand-drawn, whiteboard, and paper sketches are treated as conceptual requirements input unless they meet the same extraction thresholds as machine-drawn schematics.

**Footprints and libraries**
- Every schematic symbol must resolve to a footprint before board synthesis.
- Footprints are assigned from existing KiCad fields, exact MPN/vendor metadata, package constraints, project defaults, or user clarification.
- Missing symbols/footprints are handled through project-local library creation/import with pin, pad, package, and field verification.

**Board rules and net classes**
- Routing requires an explicit board profile: outline, fabricator, layer count, stackup, copper weight, trace/space, vias, edge clearance, silkscreen/mask rules, and impedance constraints when needed.
- Net classes are generated before routing for power, ground, Ethernet differential pairs, clocks/reset, control nets, and isolation-boundary nets.
- Board-house profiles are required immediately, starting with JLCPCB, PCBWay, OSHPark, and custom.
- Default Ethernet rules include 100BASE-TX intra-pair skew <= 10 mm and 1000BASE-T intra-pair skew <= 5 mm, overridden by cited vendor/module layout guidance.

**Placement and routing recovery**
- Placement is a required optimization stage before routing: mechanical items, safety regions, power, Ethernet, controller, I/O, then DFT/silkscreen.
- Router failure triggers congestion analysis, placement repair, net-class correction, seed routes/via changes, and constraint review before returning blocked status.

**Hard gates for `COMPLETE`**
- `unrouted_nets == 0`
- ERC error count = 0
- DRC error count = 0
- schematic/PCB parity pass
- fab export sanity pass (Gerber + drill artifacts present and valid)
- required simulation scenarios pass (for applicable designs)
- explicit human sign-off in high-stakes designs

**Input quality policy**
- Raster schematic inputs must be at least 300 DPI.
- Extraction confidence thresholds:
  - overall `>= 0.985`
  - critical fields (RefDes, net labels, connector pins) `>= 0.995`
- `ambiguous_nets == 0` and `unknown_components == 0` before PCB synthesis.

**Routing/simulation defaults**
- Route loop cap: 15 iterations, early stop after 3 no-improvement iterations.
- SPICE-required design classes: analog, power, timing-critical control, protection circuits.
- SPICE uses KiCad/ngspice-compatible netlist extraction, model provenance tracking, structured measurement parsing, and tolerance comparison.
- Manufacturer SPICE models are cached locally with license/source metadata and are not redistributed unless the license permits it; legally unobtainable models produce a warning and generic-model suggestion when an acceptable substitute is available.
- Default simulation tolerances:
  - rails `±3%`
  - analog setpoints `±5%`
  - timing windows `±10%`
  - protection thresholds `±7%`

**Requirement-driven design**
- Requirement-to-circuit workflows produce functional decomposition, known-good topology selection, component/module selection matrix, captured constraints, design rationale, and verification plan before schematic synthesis.
- If no defensible topology/component set exists, the workflow returns `BLOCKED_ENGINEERING_DECISION`.

**High-stakes boundary (mandatory user sign-off)**
- Engine/generator start-stop/shutdown control
- Hazardous energy (`>60VDC` or `>30VAC RMS`)
- Current path above 5A
- Isolation/interlock/protection function present
- Military or mission-critical industrial usage

**Distributor/BOM feature requirement**
- Vendor-native BOM import/export adapters per distributor, backed by a canonical internal BOM model.
- Initial vendor set: Digi-Key, Mouser, Arrow, Newark/Farnell/element14, LCSC, Parts Express.
- Vendors lacking public API support use authenticated portal automation fallback.
- KiCad fields map to canonical BOM fields: RefDes, value, footprint, manufacturer, MPN, vendor SKUs, quantity, DNP, lifecycle, and substitutions.
- Order submission requires explicit user approval, final vendor/cart review, and a recorded order summary.

**Fabrication and assembly outputs**
- Gerbers, Excellon drills, drill map/report, BOM, pick-and-place/centroid file, assembly drawing, fabrication notes, STEP/3D output when available, and verification report.
- Fabricator profiles define file naming and acceptance checks for JLCPCB, PCBWay, OSHPark, Eurocircuits, and custom board houses.
- STEP models come from KiCad libraries, vendor/manufacturer downloads, generated package envelopes, or user-supplied files; omitted models are listed in the final report.

**Visual QA**
- Flags silkscreen overlap, RefDes legibility, polarity/pin-1 markings, connector orientation, front-panel label consistency, test point accessibility, keepout/enclosure visibility, and orientation anomalies.
- Visual QA can block release for presentation/mechanical-readability issues but cannot override electrical, simulation, parity, or fabrication gates.

**Terminal statuses**
- `COMPLETE`
- `BLOCKED`
- `BLOCKED_INPUT_QUALITY`
- `BLOCKED_VERSION`
- `BLOCKED_SIMULATION`
- `BLOCKED_TOOLING`
- `BLOCKED_LIBRARY`
- `BLOCKED_ENGINEERING_DECISION`
- `IN_PROGRESS`

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
| `/project:init` | Scaffold a new project with CLAUDE.md, doc set, phase structure, and git hooks |
| `/project:phase` | Build a TDD phase pair (NNa failing tests + NNb implementation) for one new surface |
| `/project:revise` | Run the discipline scanner, review findings, and accept or dismiss each one |
| `/project:release` | Consolidated release gate — verifies tests, docs, version bump, then tags and publishes |
| `/project:adopt` | Apply discipline to an existing project without rewriting its history |

### Enforcement layers

Three layers enforce discipline. Only the first requires you to act.

**Layer 1 — Creation skills (manual).** The five skills above. Use them when you want to create something.

**Layer 2 — DisciplineEngine + hooks (automatic).** After every turn, the engine scans the project for drift and queues findings in `.merlin/pending.json`. At session start, the top findings appear as a system reminder. Silent when everything is healthy.

**Layer 3 — Git hooks (hard gates).** Installed by `/project:init` or `/project:adopt`. Block commits when violations are present: missing WHY-comments, user-facing surfaces with no manual coverage, phase files that no longer match the code.

### Adopting an existing project

`/project:adopt` applies discipline to a codebase that wasn't built with Merlin. It detects the language, reads existing documentation, runs a full scan, and installs the enforcement layers. Because existing projects always have coverage gaps, it records the current gap count as a baseline and requires the gap to shrink by a configurable amount with each release — forward work continues in parallel while the backlog closes incrementally.

### Adapters

Discipline rules are language-aware. Adapters (TOML files in `~/.merlin/adapters/`) declare the build command, test command, version file, WHY-comment trigger patterns, and manual-coverage surface patterns for each language. Seed adapters ship for Swift/Xcode and Rust/Cargo.

---

## Comparison: Merlin vs. Codex vs. Claude Code

Merlin, OpenAI Codex, and Anthropic Claude Code are all agentic coding tools with autonomous loop execution, file operations, and shell access. They diverge significantly in architecture, provider strategy, and target use case.

### At a Glance

| Capability | Merlin | Codex (OpenAI) | Claude Code (Anthropic) |
|---|---|---|---|
| **Interface** | macOS native SwiftUI app | Desktop app + CLI + web | CLI (terminal-first) |
| **LLM providers** | Any — Anthropic, DeepSeek, OpenAI, Qwen, OpenRouter, LM Studio, Ollama, vLLM, + more | OpenAI models only (GPT-5.5 / GPT-5.4 family) | Anthropic models only (Opus/Sonnet/Haiku) |
| **Local model support** | Full — LM Studio, Ollama, Jan.ai, LocalAI, Mistral.rs, vLLM | CLI supports custom endpoints (workaround); app is cloud-first | Primarily Anthropic cloud; limited Ollama workaround |
| **Execution environment** | Local machine, non-sandboxed | Cloud sandboxes (tasks run remotely) or local CLI | Local machine |
| **Multi-LLM routing** | Yes — execute / reason / orchestrate / vision slots with automatic complexity routing | No | No |
| **Vision / GUI automation** | AX tree + ScreenCaptureKit + CGEvent (3 strategies, auto-selected) | Computer use (desktop control) | Computer use (added March 2026) |
| **Xcode integration** | Deep — build, test, clean, xcresult parsing, open-at-line, simulator control | IDE plugin only | IDE plugin only |
| **RAG / persistent memory** | Yes — local SQLite memory store (vector search, project-scoped, critic-gated per-turn writes + accepted memories indexed as factual chunks); optional xcalibre-server for book content only | No | No (uses agentic grep/search instead) |
| **Prompt compression** | Yes — mid-loop LLM summarisation + instruction distillation; context cost stays linear across long tool chains | No | No |
| **LoRA self-training** | Yes — MLX-LM on M4 Mac; adapts execute slot to your own sessions | No | No |
| **Diff review layer** | Yes — all writes staged; accept/reject per change; inline comments | No (direct writes) | No (direct writes) |
| **Auth gate** | Yes — glob-pattern permission gate on every tool call, per session mode | No | No |
| **Permission modes** | Ask / Auto-accept / Plan (read-only) | No equivalent | No equivalent |
| **Parallel sessions** | Yes — each in its own git worktree, independent context | Yes — background agents in cloud | Yes — up to 10 subagents |
| **Subagents** | Yes — up to 4 concurrent, 2 nesting levels | Yes — multiple parallel agents | Yes — up to 10 parallel |
| **Skills / slash commands** | Yes — Markdown files, personal + project-scoped, auto-reload | No | Yes — built-in and custom |
| **Project discipline enforcement** | Yes — TDD gating, manual coverage, WHY-comment scanner, prose readability, phase drift detection (v2.2) | No | No |
| **Hooks** | Yes — PreToolUse, PostToolUse, UserPromptSubmit, Stop | No | Yes — PreToolUse, PostToolUse |
| **MCP support** | Yes | No | Yes |
| **Scheduling** | Local scheduler (cron-like, macOS notifications) | Cloud-managed (runs when computer is off) | Cloud-managed routines |
| **PR / CI monitor** | Yes — GitHub PR polling, auto-merge on CI pass | Yes — PR review built-in | Limited |
| **External connectors** | GitHub, Slack, Linear | GitHub, SSH to remote devboxes | GitHub |
| **Web search** | Brave Search integration | Yes | Yes |
| **In-app browser / preview** | WKWebView preview pane | In-app browser | No |
| **Voice dictation** | Yes (SFSpeechRecognizer) | No | No |
| **IDE integration** | No (standalone app) | VS Code, JetBrains, Xcode, Eclipse | VS Code, JetBrains, Xcode, Eclipse |
| **Cost** | Self-hosted; no subscription fee (pay per API call or free for local models) | Pro $100/mo (OpenAI subscription) | Max plan $100–200/mo (Anthropic subscription) |
| **Distribution** | Personal use (not distributed) | Public — macOS app + CLI | Public — CLI |
| **Platform** | macOS 14+ only | macOS (desktop app), cross-platform (CLI) | macOS and Linux (CLI) |

---

### Where Merlin goes further

**Provider freedom.** Merlin is the only tool in this group that routes work across genuinely different providers — switching between DeepSeek for reasoning, a local Qwen model for fast iteration, and a vision model for GUI work — all within the same session. Codex is GPT-only. Claude Code is Claude-only. Merlin has no lock-in.

**Supervisor-worker multi-LLM routing.** Merlin classifies each task by complexity tier and routes it to the most appropriate LLM slot. Routine file operations go to the execute slot (fast/cheap); architecture decisions go to the reason slot (most capable). Neither Codex nor Claude Code do this — they use a single model for all task types.

**LoRA self-training.** Merlin is unique in being able to fine-tune a local model on your own accepted session data using MLX-LM on an M4 Mac. Over time, the execute slot adapts to your coding patterns and project conventions. This is not a feature Codex or Claude Code offer.

**Prompt compression.** Agentic loops accumulate context quadratically — without intervention, a 100-step run costs far more than 100× the cost of a single step. Merlin applies mid-loop LLM summarisation (replacing old tool exchanges with a narrative digest before the next request) and instruction distillation (caching a token-efficient version of `CLAUDE.md` and the core system prompt). The result is linear cost growth regardless of session length. Neither Codex nor Claude Code have an equivalent compression pipeline.

**Persistent RAG memory.** Merlin stores project knowledge in a local SQLite-backed vector store and injects relevant context into every prompt. Memory writes are critic-gated — only outputs that passed the quality check enter the memory store. xcalibre-server remains available for book content, but it no longer stores Merlin session memory. Claude Code explicitly chose not to do RAG, relying on agentic grep/search instead. Codex has no RAG layer.

**Diff review + inline comments.** In Ask and Plan modes, every file write is staged rather than applied. You review a unified diff, accept or reject per change, and can attach inline comments that feed back to the agent for revision — without leaving the app. Both Codex and Claude Code apply writes directly with no staging step.

**Auth gate.** Merlin intercepts every tool call — including MCP tools — through a pattern-matching permission gate before execution. You can allow or deny by glob pattern, and decisions persist. This gives fine-grained, auditable control over what the agent can touch. Neither Codex nor Claude Code have an equivalent mechanism.

**Deep Xcode integration.** Merlin parses `.xcresult` bundles, extracts structured errors and coverage, controls simulators, and can jump Xcode to an exact file and line via AppleScript. IDE plugins (the approach both Codex and Claude Code take) are shallower — they don't parse build artifacts or own the build loop.

**Project discipline enforcement.** Merlin is the only tool in this group that mechanically enforces construction discipline — TDD phase pairs, comprehensive manual coverage, WHY-comments where warranted, prose readability, and phase-file/code sync — through a combination of automatic scanners, session-start reminders, and hard git-hook gates. Neither Codex nor Claude Code have an enforcement layer; discipline is left to the user's memory.

**macOS-native, non-sandboxed.** As a native SwiftUI app, Merlin integrates with the macOS Accessibility tree, ScreenCaptureKit, CGEvent, SFSpeechRecognizer, and macOS Keychain in ways a CLI or Electron app cannot. GUI automation uses three complementary strategies and auto-selects the best one per target app.

---

### Where Codex and Claude Code have advantages

**Codex** runs tasks in cloud sandboxes, which means agents can execute long-running jobs without tying up your machine. Remote devbox SSH support makes it practical for teams with shared infrastructure. Codex is embedded in the broader ChatGPT + OpenAI ecosystem, which benefits users already on that platform. GPT-5.5 is the current flagship model for complex reasoning and coding tasks.

**Claude Code** has a lower barrier to entry — it is a single CLI install with no configuration required. Scheduled routines run on Anthropic-managed infrastructure and continue even when your laptop is off. The ultrareview subcommand integrates into CI pipelines without a running desktop session. Claude's models consistently perform at the top of coding benchmarks, and the tool benefits from continuous Anthropic investment.

**Both** are publicly distributed, actively maintained by large engineering teams, and have broad ecosystem support (IDE plugins, CI integrations, community plugins). Merlin is a personal tool maintained by one person and is not distributed.

---

### Summary

Merlin is built for a specific workflow: a single developer on Apple Silicon who wants full control over every layer — which models run, what they can touch, how outputs are reviewed, and how the system improves over time from their own data. It trades distribution breadth and zero-setup convenience for depth of integration, provider flexibility, and long-term self-improvement via LoRA.

Codex is best for teams embedded in the OpenAI ecosystem who want cloud-isolated execution and a polished multi-platform app. Claude Code is best for developers who want a capable, low-friction CLI agent and are comfortable with Anthropic's model portfolio.

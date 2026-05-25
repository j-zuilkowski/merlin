# Merlin — User Guide

**Version 2.2.5**

Merlin is a macOS agentic AI assistant that connects to multiple LLM providers and can autonomously read, write, and execute code in your projects using a rich tool set.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [The Workspace](#the-workspace)
3. [Chatting with the AI](#chatting-with-the-ai)
4. [Tool Execution & Permissions](#tool-execution--permissions)
5. [Sessions](#sessions)
6. [Providers](#providers)
7. [Skills](#skills)
8. [Slash Commands](#slash-commands)
9. [@-Mentions and File Attachments](#-mentions-and-file-attachments)
10. [Staged Changes](#staged-changes)
11. [File Viewer](#file-viewer)
12. [Terminal Pane](#terminal-pane)
13. [Preview Pane](#preview-pane)
14. [Side Chat](#side-chat)
15. [Subagents](#subagents)
16. [Multi-LLM Roles](#multi-llm-roles)
17. [Performance Dashboard](#performance-dashboard)
18. [Memories](#memories)
19. [RAG Memory Browser](#rag-memory-browser)
20. [Project Discipline](#project-discipline)
21. [Hooks](#hooks)
22. [Connectors](#connectors)
23. [Scheduled Automations](#scheduled-automations)
24. [LoRA Self-Training](#lora-self-training)
25. [Settings](#settings)
26. [Keyboard Shortcuts](#keyboard-shortcuts)

---

## Getting Started

### First Launch

When you first open Merlin you will see the **Project Picker**. Click **Open Project…** and select the root folder of the codebase you want to work with. Recent projects appear in the list and can be re-opened with a single click.

Before the AI can respond you need a provider API key. Merlin defaults to **DeepSeek**. Go to **Settings → Providers**, find DeepSeek, and paste your API key. The key is stored in the macOS Keychain — it is never written to disk in plaintext.

If you want to use a local model no API key is required. Enable the relevant provider in Settings and make sure its server is running. As of May 24, 2026, the fully supported local providers are **LM Studio**, **Jan.ai**, and **LocalAI**. **llama.cpp** is now a first-class local provider (`llamacpp`) at `http://localhost:8081/v1` and is pending a fresh calibration sweep. **Ollama** and **vLLM-Metal** remain available but are not recommended because the tested vision path failed live. **Mistral.rs** is currently unusable for the tested Qwen3 MoE model on Apple Metal.

Upstream issue tracking for the malfunctioning local providers is maintained in
[`docs/local-provider-configs/RESULTS.md`](../../docs/local-provider-configs/RESULTS.md).

### Opening a Project

Each workspace window is bound to one project directory. Merlin automatically loads:

- `CLAUDE.md` from the project root (and any parent directories up to `~`) — this becomes part of the system prompt
- Skill files from `~/.merlin/skills/` and `<project>/.merlin/skills/`
- MCP server configuration from `~/.merlin/config.toml` and `<project>/.claude/mcp.json`

---

## The Workspace

The workspace is divided into panes. All panes are optional and toggled from the toolbar.

```
┌─────────────┬──────────────────────────┬───────────┬───────────┐
│  Session    │       Chat View          │  Staged   │   File    │
│  Sidebar    │  (always visible)        │  Changes  │  Viewer   │
│             │                          │           │           │
│             ├──────────────────────────┴───────────┴───────────┤
│             │             Terminal Pane (optional)             │
└─────────────┴─────────────────────────────────────────────────┘
```

| Toolbar Button | What it shows |
|---|---|
| **Staged Changes** (branch icon) | Agent-proposed file modifications awaiting review |
| **File Viewer** (doc icon) | Open and read any file |
| **Terminal** (terminal icon) | Embedded shell output pane |
| **Preview** (eye icon) | Rendered Markdown / HTML / JSON / image preview |
| **Side Chat** (bubble icon) | A second concurrent conversation panel |
| **Memories** (brain icon) | Review AI-generated memory files |

### Session Sidebar

The left sidebar lists all open sessions for this project. Click a session to switch to it. Sessions are independent — each has its own conversation history, context window, and staging buffer.

---

## Chatting with the AI

Type your message in the input field at the bottom of the chat view and press **Return** (or click the send button). Use **Shift+Return** to add a newline without sending.

The AI will respond as a stream of text. If it decides to use tools, you will see tool call entries appear in the conversation before the final answer.

### Stopping

Press **⌘.** or click the **stop button** (the send button turns red while the agent is running) to cancel the current turn immediately.

### Thinking Mode

Merlin automatically detects when your message requires deep reasoning (words like "think through", "analyse", "architecture", "design") and enables the provider's extended thinking mode for that turn. You can see the thinking steps in collapsed blocks in the conversation.

### Scroll Lock

When the AI is streaming a long response, scrolling up pauses automatic scrolling and reveals a **"Resume auto-scroll"** banner at the bottom of the conversation. Click the banner to snap back to the bottom and resume. Sending a new message also resumes auto-scroll automatically.

---

## Tool Execution & Permissions

The AI has access to a large set of built-in tools:

| Category | Tools |
|---|---|
| **File system** | read_file, write_file, create_file, delete_file, list_directory, move_file, search_files |
| **Shell** | run_shell |
| **Xcode** | xcode_build, xcode_test, xcode_clean, xcode_open_simulator |
| **App control** | launch_app, quit_app, focus_app, list_running_apps |
| **Accessibility** | ax_inspect (reads UI element hierarchy) |
| **Screen** | capture_screen, vision_query |
| **Input** | cg_event (synthesises keyboard/mouse events) |
| **Search** | web_search |
| **RAG** | rag_search, rag_list_books |
| **Subagents** | spawn_agent |

### Permission Modes

Every session has a permission mode that controls how tool calls are authorised:

| Mode | Behaviour |
|---|---|
| **Ask** | Every tool call shows an approval popup. You can approve once or create a permanent allow/deny pattern. |
| **Auto-Accept** | All tool calls are approved automatically without interruption. |
| **Plan** | File write/create/delete/move calls are intercepted into the **Staged Changes** buffer. All other tools run normally. |

Click the permission mode indicator in the chat toolbar to cycle between modes.

### The Auth Popup

When a tool call needs approval (Ask mode), a sheet appears showing:

- The tool name and the specific argument (e.g. the file path being read or command being run)
- A reasoning summary from the AI
- A suggested allow/deny pattern

You can:
- **Allow Once** — approve just this call
- **Allow Always** (with a pattern) — create a permanent allow rule for matching future calls
- **Deny** — block this specific call

Patterns support glob syntax: `*` matches a single path segment, `**` matches any number of path segments, `~` expands to your home directory.

---

## Sessions

Each workspace window can hold multiple sessions. A session is an independent conversation with its own:

- Message history
- Context window state
- Staged changes buffer
- MCP server connections
- Memory / domain state

### New Session

Press **⌘N** or choose **File → New Session**.

### Pop Out

Press **⌘⇧P** or choose **Window → Pop Out Session** to open the current session in a floating window that can stay on top of other apps.

### Context Compaction

When the conversation grows large, Merlin automatically summarises old tool-result groups to free up context space. The conversation and code context are preserved verbatim; only intermediate tool output is condensed. A **[context compacted]** note appears in the conversation when this happens.

You can also trigger compaction on demand at any time by typing `/compact` in the chat bar (see [Slash Commands](#slash-commands)).

**Automatic recovery:** if the active provider rejects a prompt because it exceeds its context window (HTTP 400 "context_length_exceeded"), Merlin compacts automatically and retries the failed turn rather than stopping. This means long agentic runs can continue uninterrupted even when a single payload is unusually large.

---

## Providers

Merlin supports multiple LLM backends. Configure providers in **Settings → Providers**
and assign routing in **Settings → Role Slots**.

The lower-left sidebar includes a **Slot Status** panel with four persistent rows:
**Execute**, **Reason**, **Orchestrate**, and **Vision**.

- Rows are driven only by explicit slot assignments.
- Unassigned rows remain visible and are labelled **Not configured**.
- Enabling a provider in Settings does not populate slot rows until a slot is assigned.
- Status dots use grey for unconfigured slots, green for ready or finished slots,
  orange while a slot is busy, and red after the last turn on that slot reports an
  error.

Available providers:

| Provider | Type | Notes |
|---|---|---|
| DeepSeek | Remote | Requires API key. Supports thinking mode. |
| OpenAI | Remote | Requires API key. Supports vision. |
| Anthropic | Remote | Requires API key. Supports thinking mode and vision. |
| Qwen | Remote | Requires API key. |
| OpenRouter | Remote | Routes to any model via single API key. |
| Ollama | Local | `localhost:11434`. Not recommended: general works, but the tested vision model crashed on real image requests. |
| LM Studio | Local | `localhost:1234`. Fully supported. Supports vision and passed live pair calibration. |
| Jan.ai | Local | `localhost:1337`. Fully supported and passed live pair calibration. |
| LocalAI | Local | `localhost:8080`. Fully supported and passed live pair calibration. |
| llama.cpp | Local | `localhost:8081`. First-class router-mode provider; one `llama-server` can host the general+vision pair. Runtime load/unload uses router endpoints when available, and restart guidance uses the current `--models-dir` / `--models-preset` llama-server flags. Pending fresh calibration numbers. |
| Mistral.rs | Local | `localhost:1235`. Currently unusable for the tested Qwen3 MoE model on Apple Metal. |
| vLLM-Metal | Local | `localhost:8000`. Not recommended: general works, but vision is not implemented in the tested `vllm-metal` runtime on Metal. |
| mlx_lm.server | Local | OpenAI-compatible server for LoRA-adapted model inference on Apple Silicon. Configure URL in Settings → LoRA. Used automatically by the execute slot when LoRA Auto-Load is enabled. |

Configure API keys, base URLs, and model names in **Settings → Providers**.

---

## Skills

Skills are reusable prompt templates that extend what the AI can do in one command.

### Invoking a Skill

Type `/` in the chat input to open the skills picker. Continue typing to filter by name. Press **Return** or click to invoke. Some skills accept an argument — type it after the skill name (e.g. `/refactor MyClass`).

### Creating a Skill

Skills are Markdown files with YAML frontmatter saved in `~/.merlin/skills/` (personal, available in all projects) or `<project>/.merlin/skills/` (project-scoped).

```markdown
---
name: summarise
description: Summarise the selected code
argument_hint: optional context
---

Please summarise the following, highlighting the most important behaviour:

{{args}}
```

Merlin watches the skills directories and reloads automatically when files change.

---

## Slash Commands

Several built-in commands are available directly from the chat input. Type `/` followed by the command name and press **Return**.

| Command | What it does |
|---|---|
| `/calibrate` | Benchmark the active local model against a remote reference provider and surface parameter advisories |
| `/compact` | Compact the context window immediately, summarising old tool results to free up space |
| `/rewind` | Restore the conversation to the snapshot taken before your most recent message |
| `/rewind N` | Restore the conversation N turns back (e.g. `/rewind 3` goes back three user turns) |
| `/btw <question>` | Open a floating side-question overlay and ask something without affecting the conversation history |
| `/btw` | Open the side-question overlay with an empty input field |

### /compact

Triggers context compaction immediately regardless of how full the context window is. Useful before sending a large prompt or spawning a subagent when you know the current context is bloated with old tool output. A **[context compacted on demand]** note appears in the conversation to confirm.

### /rewind

Merlin saves a checkpoint of the conversation before each of your messages. `/rewind` restores to the most recent checkpoint — effectively undoing your last message and the AI's response. `/rewind N` goes back N checkpoints.

Checkpoints are kept for the lifetime of the session (up to 50). They are cleared when you start a new session. Rewind restores both the context window (what the AI can see) and the visible conversation.

> **Note:** `/rewind` does not undo file changes the AI made to disk. If the AI wrote or deleted files, those changes remain on disk after rewinding the conversation. Use git to revert file changes.

### /btw

Opens a small floating overlay anchored to the chat area. Type a question, press **Return** — the answer streams in from the active provider without touching your conversation history or the AI's context window. Press **Esc** or click anywhere outside the overlay to dismiss it.

This is useful for quick look-ups ("what does this function signature mean?", "what's the regex for email addresses?") that you don't want polluting the conversation your agent is in the middle of.

---

## @-Mentions and File Attachments

Type `@` in the chat input to open the file autocomplete picker. Select a file to inject its full content (or a line range like `@src/main.swift:10-50`) into your message.

You can also **drag and drop** files directly into the chat input. Images are sent as vision attachments to the active provider if it supports vision.

---

## Staged Changes

When the permission mode is **Plan** (or manually enabled via the toolbar), file-modifying tool calls do not write to disk immediately. Instead they appear in the **Staged Changes** pane as diffs awaiting your review.

Each staged change shows:

- The file path and operation (create / write / delete / move)
- A colour-coded diff (+added lines in green, −removed lines in red)
- Per-line comment controls (click a diff line to add an inline comment)

Actions:

| Button | Effect |
|---|---|
| **Accept** | Applies this one change to disk |
| **Reject** | Discards this change |
| **Submit Comments** | Sends all inline comments back to the AI for revision |
| **Accept All & Commit** | Applies every pending change to disk at once |
| Reject All (✕) | Discards all pending changes |

---

## File Viewer

Click the **File Viewer** toolbar button to open the file pane. Click the folder icon in the pane header or the **Open File…** button to pick a file.

- Text files are shown with monospaced font and are selectable
- Images (jpg, jpeg, png, gif, heic, webp, svg, etc.) are displayed as previews
- Click **×** in the header to close the current file

---

## Terminal Pane

Click the **Terminal** toolbar button to show an embedded terminal running in the project directory. Use it to run build commands, git operations, or any other shell command without leaving Merlin.

---

## Preview Pane

Click the **Preview** toolbar button to open a rendered view of the last content the AI produced. Supports:

- **Markdown** — rendered with headings, code blocks, and emphasis
- **HTML** — rendered in a web view
- **JSON** — syntax-highlighted tree view
- **Images** — inline display

---

## Side Chat

Click the **Side Chat** toolbar button to open a second conversation panel alongside the main chat. This is useful for running quick queries while a long task is in progress in the main session.

---

## Subagents

When a task is parallelisable, the AI can spawn subagents. There are two kinds:

| Type | Behaviour |
|---|---|
| **Explorer** | Read-only. Gathers information in parallel. Results are summarised and injected back into the parent conversation. |
| **Worker** | Can read and write. Operates in an isolated git worktree to avoid conflicting with the main working tree. Staged changes appear in the **Worker Diff View** in the session sidebar. |

Subagents appear as collapsible blocks in the parent conversation, showing their tool call events and final result.

Nested subagent spawning is not currently supported. If a subagent tries to call `spawn_agent`, Merlin rejects it explicitly instead of pretending it worked.

---

## Multi-LLM Roles

Merlin routes each message to the most appropriate LLM based on its complexity and content. There are four slots:

| Slot | Purpose |
|---|---|
| **Execute** | General task execution — file operations, code writing, shell commands, tool loops. When LoRA self-training is active, this slot uses your fine-tuned adapter. |
| **Reason** | Deep reasoning, debugging, architecture analysis. Uses the base model without any adapter. |
| **Orchestrate** | Multi-step task decomposition and subagent coordination. Falls back to the Reason slot if not explicitly assigned. |
| **Vision** | GUI screenshot analysis and UI element localization. |

### Assigning providers to slots

Open **Settings → Role Slots** and choose which LLM provider handles each slot. You can assign different providers — for example, a local model on the Execute slot and a remote API on the Reason slot.

If you leave a slot unassigned, Merlin falls back in this order:

- **Execute** → active provider
- **Reason** → active provider
- **Orchestrate** → Reason slot, then active provider
- **Vision** → active provider unless a dedicated vision-capable provider is assigned

### Overriding routing manually

Prefix your message with a slot annotation to override automatic routing:

- `@reason <message>` — force the reason slot
- `@execute <message>` — force the execute slot
- `@orchestrate <message>` — force the orchestrate slot

You can also prefix with a complexity override:

- `#high-stakes <message>` — use the reason slot with full planning
- `#standard <message>` — planning pass, execute slot
- `#routine <message>` — no planning, execute slot directly

---

## Performance Dashboard

Merlin tracks how well each model performs across different task types. Open **Settings → Performance** to see the dashboard.

For each model and task type combination, the dashboard shows:

- **Success rate** — an exponentially-weighted score based on critic verdicts, diff accept/reject counts, and session completion
- **Sample count** — how many sessions have been recorded. The profile is considered calibrated once 30 samples are collected; routing decisions use uncalibrated profiles as hints only.
- **Trend** — improving, stable, or declining (based on recent sessions vs. the running average)

Performance data is stored in `~/.merlin/performance/`. It persists across restarts and is also used as the training dataset for LoRA self-training.

---

## Memories

Merlin watches for periods of inactivity in a session. After the configured idle timeout, it uses the AI to generate a concise memory from the recent conversation and saves it as a Markdown file to `~/.merlin/memories/pending/`.

### Reviewing Memories

Click the **Memories** toolbar button to open the review sheet. Each pending memory shows its content. You can:

- **Approve** — moves the file to `~/.merlin/memories/` and injects it into future sessions
- **Reject** — deletes the file

Memories are automatically prepended to the system context at the start of each session.

---

## RAG Memory Browser

Merlin writes session summaries to its local memory store and retrieves them in future sessions. The Memory Browser lets you manage those stored memories.

### Opening the Memory Browser

Go to **Settings → Memories** and click **Browse Memory Store**.

### Searching memories

Type in the search field to find memories by content. Results are scoped to the active project path if one is configured in Settings → Agent.

### Deleting memories

Select a memory and click **Delete**. The chunk is immediately removed from the local store. Deletion is permanent.

---

## Electronics / KiCad Domain (v2.0)

Merlin v2.0 adds a complete electronics workflow for designing PCBs with KiCad. The domain is powered by an external MCP server (`merlin-kicad-mcp`) that Merlin launches and communicates with automatically when an electronics session is active.

### Starting an Electronics Session

When you open a project that contains a KiCad project file (`.kicad_pro`), Merlin activates the electronics domain for that session automatically. If you start from a software session and your next prompt clearly indicates board-design or schematic work, Merlin asks whether to switch the session into **Electronics** before sending the prompt. The domain indicator in the session toolbar shows **Electronics** instead of **Software**.

### What you can do

| Capability | How to invoke |
|---|---|
| Import a hand-drawn or PDF schematic | Attach the image/PDF to your message and describe the design |
| Generate a KiCad schematic from requirements | Describe the circuit in plain language |
| Assign footprints and generate a PCB layout | Ask Merlin to assign footprints after schematic review |
| Autoroute the board | Ask Merlin to route; FreeRouting runs automatically |
| Run ERC / DRC verification | Ask Merlin to verify; results appear in the conversation |
| Generate BOM and vendor quotes | Ask Merlin to prepare a BOM; Merlin checks Digi-Key and Mouser |
| Export Gerbers for fabrication | Ask Merlin to export fab files |

### High-Stakes Signoff

Manufacturing actions (placing an order, uploading Gerbers to a board house) require your explicit approval. Merlin will always stop and ask before taking any irreversible action. This cannot be bypassed by permission mode settings — signoff is hardcoded for these operations.

### Switching Between Software and Electronics Sessions

Each session has its own domain. You can have a software session and an electronics session open simultaneously in the same workspace — they do not interfere with each other. Switch between them normally using the session sidebar.

---

## Behavioral Reliability (v9)

Merlin monitors its own output quality and intervenes when confidence cannot be maintained. These features address the failure patterns described in ["Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems"](https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems) (S. Patil, VentureBeat, 2025).

### Circuit Breaker

If the critic returns a failing verdict on several consecutive turns, the circuit breaker activates:

- **Halt mode** (default) — the engine stops the next turn cleanly and shows a banner explaining what happened. You need to act before the agent continues.
- **Warn mode** — a warning is shown but the turn proceeds.

The counter resets to zero on any passing verdict or when you start a new session. Configure the threshold and mode in **Settings → Agent** or via `agent_circuit_breaker_threshold` / `agent_circuit_breaker_mode` in `~/.merlin/config.toml` (default: halt after 3 failures).

This addresses the *silent partial failure* pattern — sustained quality degradation that falls below any single-turn alert threshold.

### Grounding Confidence

Every turn, Merlin emits a `GroundingReport` describing how well the model's response was grounded in retrieved memory context:

| Field | Meaning |
|---|---|
| **Total chunks** | Number of RAG chunks injected this turn |
| **Average score** | Mean cosine similarity of retrieved chunks (0–1) |
| **Has stale memory** | True when any injected memory chunk is older than `ragFreshnessThresholdDays` (default 90 days) |
| **Is well-grounded** | True when chunks were retrieved and average score ≥ `ragMinGroundingScore` (default 0.30) |

These signals are visible in the Tool Log. Configure thresholds via `rag_freshness_threshold_days` / `rag_min_grounding_score` in `~/.merlin/config.toml`.

This addresses the *context degradation* pattern — the model reasoning confidently over stale or sparse retrieval without any visible signal to the user.

---

## Project Discipline

Merlin can enforce construction discipline on any project through a `DisciplineEngine` that runs automatically after every turn, plus five skills for deliberate creation tasks.

### /project:init

Scaffolds a new project. Asks for project name, language, doc-set preference, and which enforcement layers to install. Produces:

- Language-native scaffold (`cargo new`, `xcodegen`, etc.)
- `CLAUDE.md` customised to the chosen language and adapter
- Full doc set (`README.md`, `architecture.md`, `api.md`, `developer-guide.md`, `user-manual.md`, `FEATURES.md`, `CHANGELOG.md`)
- `phases/` directory with a `phase-00` documenting the initial state
- `.merlin/project.toml` with adapter selection
- Git hooks (`pre-commit`, `pre-push`)
- Initial git commit

### /project:phase

Builds a TDD phase pair for one new surface. Asks structuring questions — what the abstraction is, what prior phase it depends on, what surfaces NNb introduces — and produces both the NNa (failing tests) and NNb (implementation) phase files, plus a `PASTE-LIST.md` update.

### /project:revise

Runs the discipline scanner and walks you through every finding. For each one you choose:

- **Accept** — the skill applies the proposed fix
- **Modify** — you edit the fix; the skill validates and applies it
- **Dismiss** — logged to `.merlin/override-log.jsonl` with your rationale
- **Defer** — stays in the pending queue for later

Produces a single commit per accepted batch with a structured commit message.

### /project:release

The consolidated release gate. Checks before releasing:

- All tests pass
- API docs regenerated and committed
- Manual coverage: no new gaps; baseline reduced since last release
- Phase files in sync with code (no red drift)
- WHY-comment violations clear or all overridden with rationale
- Prose readability at target grade for all doc files
- `RELEASE-vX.Y.Z.md` present with required sections
- `CHANGELOG.md` updated
- Version bumped in the project file

On a clean pass: commits the version bump, creates the git tag, pushes, and creates the GitHub release.

### /project:adopt

Applies discipline to an existing project without rewriting its history.

1. Detects language and selects an adapter (or asks).
2. Reads existing `CLAUDE.md` / `architecture.md` — preserves them, adds a "Project Discipline" section if absent.
3. Scans the codebase: surfaces, doc coverage gaps, WHY-comment violations, prose readability failures, phase drift.
4. Records the current coverage gap count as the baseline in `.merlin/project.toml`.
5. Installs git hooks (with per-layer confirmation).
6. Prints a one-page adoption report: baseline count, releases needed to close it at default decay, violations by category.

After adoption, run `/project:revise` to start working through the backlog. New surfaces must be covered from the moment of adoption; the pre-existing gap closes at a configurable rate.

### Automatic enforcement

The `DisciplineEngine` runs without you doing anything:

- **After every turn** (`Stop` hook) — scans the diff for new violations, updates the pending queue.
- **At session start** (`SessionStart` hook) — injects the top findings into context as a system reminder.
- **Before each message** (`UserPromptSubmit` hook) — flags if a feature request has no corresponding phase file.
- **Git hooks** — block commits on hard violations; block pushes on version-tag mismatches.

Findings have three severity levels:

| Severity | Effect |
|---|---|
| **block** | Commit or release refused until resolved or explicitly overridden |
| **nudge** | Surfaced at session start; doesn't block work |
| **silent** | Logged only; visible in `/project:revise` |

The engine disables itself gracefully after three consecutive scan failures rather than blocking your session.

---

## Hooks

Hooks let you run shell scripts at specific points in the agent lifecycle to customise or constrain its behaviour.

| Event | When it fires | Effect |
|---|---|---|
| **PreToolUse** | Before any tool call | Return `{"decision":"allow"}` or `{"decision":"deny","reason":"..."}` |
| **PostToolUse** | After a tool call completes | Return modified output to replace the tool result |
| **UserPromptSubmit** | When you press Send | Return modified prompt text |
| **Stop** | When the agent finishes | Return `{"proceed":true}` to make the agent continue |

Configure hooks in **Settings → Hooks**. Each hook has an event, a shell command, and an enabled toggle.

---

## Connectors

Connectors give the AI access to external services:

| Connector | Capabilities |
|---|---|
| **GitHub** | List PRs and issues, read file at ref, create PRs, post comments, merge PRs |
| **Linear** | List issues, create issues, update status, post comments |
| **Slack** | List channel messages, post messages |

Authenticate each connector in **Settings → Connectors**. Tokens are stored in the Keychain.

**PR Monitor** automatically polls open PRs and notifies you when CI checks change state.

---

## Scheduled Automations

Open **Settings → Scheduler** to create recurring tasks that run automatically on an hourly, daily, or weekly schedule. Each task has:

- A label
- A project path
- A scheduled time
- A permission mode
- A prompt to send to the AI

Scheduled tasks run in a background session for the configured project and post a macOS notification with a summary when they finish.

This Scheduler is the supported automation surface in Merlin. Older thread-automation internals still exist in the codebase, but they are not the supported user-facing scheduling path.

---

## LoRA Self-Training

Merlin can fine-tune a local language model on your accepted sessions using MLX-LM on an M4 Mac with 128GB unified memory. Once trained, the adapter is loaded automatically and the execute slot routes through it.

### What it does

After each session turn, Merlin records the user prompt and the model's response alongside a quality score. When enough high-quality samples accumulate (configurable threshold, default 1000), the trainer exports them as a JSONL fine-tuning dataset and runs `python -m mlx_lm.lora --train`. The resulting adapter is served by an MLX-native runtime — `mlx_lm.server` (the default Merlin routes through), or alternatively LM Studio or vLLM-Metal. vLLM-Metal remains a text-oriented fallback rather than a recommended pair runtime in the current local-provider sweep. The GGUF local providers (Ollama, Jan.ai, LocalAI, llama.cpp) can also serve the fine-tuned model after a manual `mlx_lm.fuse` + `convert_hf_to_gguf.py` step. **Mistral.rs cannot serve MoE models on Metal** (`candle-core 0.10.2` lacks the kernel); fine-tuning targeting Mistral.rs only applies to non-MoE base models.

### Requirements

- macOS on an Apple Silicon Mac (M4 with 128GB recommended for 32B models)
- Python with MLX-LM installed: `pip install mlx-lm`
- A downloaded base model (Qwen2.5-Coder-7B-Instruct for testing, Qwen2.5-Coder-32B-Instruct for production)
- `mlx_lm.server` running locally

### Step-by-step activation

1. Install MLX-LM: `pip install mlx-lm`
2. Download a base model, e.g. `mlx_lm.convert --hf-path Qwen/Qwen2.5-Coder-32B-Instruct`
3. Open **Settings → LoRA** and enable **LoRA Self-Training** (master toggle)
4. Set **Base Model** to the path of your downloaded MLX model
5. Set **Adapter Path** to a directory where the trained adapter will be written (e.g. `~/.merlin/adapters/qwen32b`)
6. Pick **Serving runtime** — which MLX-native runtime serves the trained adapter:
   - `mlx_lm.server` (default) — direct adapter load via `--adapter-path`
   - `vLLM-Metal` — fuse with `mlx_lm.fuse` first, then `vllm serve <merged>` (not recommended for the current general+vision pair workflow)
   - `LM Studio` — load via the LM Studio UI
   - `Custom` — any other MLX-compatible OpenAI-compat endpoint
7. Set **Server URL** to match the chosen runtime (the picker pre-fills the default port)
8. Enable **Auto-Train** to start training automatically once the sample threshold is met
9. Enable **Auto-Load** to automatically route the execute slot through the trained adapter
10. Start the chosen runtime (commands vary per Serving runtime — see the picker's tooltip)

Once Auto-Load is enabled and an adapter file exists, Merlin automatically switches the execute slot to your local fine-tuned model. The reason and critic slots always use the unmodified base provider.

---

## Settings

Access via **Merlin → Settings…** (⌘,).

| Section | What you configure |
|---|---|
| **General** | Default permission mode, auto-compaction toggle, max context tokens, keep-awake toggle, checkpoint store size |
| **Appearance** | Theme (light/dark/system), font size, accent colour, line spacing |
| **Providers** | Enable/disable providers, set API keys, base URLs, and model names |
| **Role Slots** | Assign LLM providers to execute / reason / orchestrate / vision slots |
| **Performance** | Per-model performance dashboard, trend, calibration status, export training data |
| **Agents** | Custom subagent definitions loaded from `~/.merlin/agents/` |
| **Hooks** | Lifecycle hooks with event, command, and enabled toggle |
| **Scheduler** | Hourly, daily, and weekly task scheduling |
| **Memories** | Enable/disable memory generation, configure idle timeout, browse local memory store, select memory backend |
| **LoRA** | Master toggle, auto-train, sample threshold, base model path, adapter path, auto-load, server URL |

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New session |
| ⌘. | Stop the current agent turn |
| ⌘⇧P | Pop out current session as floating window |
| ⌘, | Open Settings |
| ⌘⇧K | Compact context window immediately |
| ⌘⇧A | Copy full conversation to clipboard |
| Return | Send message |
| Shift+Return | New line in input |
| / (in input) | Open skills picker (also starts a slash command) |
| @ (in input) | Open file @-mention picker |
| Ctrl+` | Toggle Terminal pane |
| ⌘⇧/ | Toggle Side Chat |
| ⌘⇧M | Review Memories |
| Esc (in /btw overlay) | Dismiss the side-question overlay |

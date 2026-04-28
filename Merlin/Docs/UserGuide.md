# Merlin — User Guide

**Version 4.0**

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
8. [@-Mentions and File Attachments](#-mentions-and-file-attachments)
9. [Staged Changes](#staged-changes)
10. [File Viewer](#file-viewer)
11. [Terminal Pane](#terminal-pane)
12. [Preview Pane](#preview-pane)
13. [Side Chat](#side-chat)
14. [Subagents](#subagents)
15. [Memories](#memories)
16. [Hooks](#hooks)
17. [Connectors](#connectors)
18. [Scheduled Automations](#scheduled-automations)
19. [Settings](#settings)
20. [Keyboard Shortcuts](#keyboard-shortcuts)

---

## Getting Started

### First Launch

When you first open Merlin you will see the **Project Picker**. Click **Open Project…** and select the root folder of the codebase you want to work with. Recent projects appear in the list and can be re-opened with a single click.

Before the AI can respond you need a provider API key. Merlin defaults to **DeepSeek**. Go to **Settings → Providers**, find DeepSeek, and paste your API key. The key is stored in the macOS Keychain — it is never written to disk in plaintext.

If you want to use a local model (Ollama, LM Studio, Jan.ai, etc.) no API key is required. Enable the relevant provider in Settings and make sure its server is running.

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
- Thread automations

### New Session

Press **⌘N** or choose **File → New Session**.

### Pop Out

Press **⌘⇧P** or choose **Window → Pop Out Session** to open the current session in a floating window that can stay on top of other apps.

---

## Providers

Merlin supports multiple LLM backends. Switch providers using:

- The **Provider menu** in the menu bar
- The **ProviderHUD** widget at the top of the chat view (click it to see a popover)

Available providers:

| Provider | Type | Notes |
|---|---|---|
| DeepSeek | Remote | Requires API key. Supports thinking mode. |
| OpenAI | Remote | Requires API key. Supports vision. |
| Anthropic | Remote | Requires API key. Supports thinking mode and vision. |
| Qwen | Remote | Requires API key. |
| OpenRouter | Remote | Routes to any model via single API key. |
| Ollama | Local | Must be running on localhost:11434. |
| LM Studio | Local | Must be running on localhost:1234. Supports vision. |
| Jan.ai | Local | Must be running on localhost:1337. |
| LocalAI | Local | Must be running on localhost:8080. |
| Mistral.rs | Local | Must be running on localhost:1234. |
| vLLM | Local | Must be running on localhost:8000. |

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

---

## Memories

Merlin watches for periods of inactivity in a session. After the configured idle timeout, it uses the AI to generate a concise memory from the recent conversation and saves it as a Markdown file to `~/.merlin/memories/pending/`.

### Reviewing Memories

Click the **Memories** toolbar button to open the review sheet. Each pending memory shows its content. You can:

- **Approve** — moves the file to `~/.merlin/memories/` and injects it into future sessions
- **Reject** — deletes the file

Memories are automatically prepended to the system context at the start of each session.

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

Open **Settings → Scheduler** to create recurring tasks that run automatically on a cron schedule. Each automation has:

- A label
- A cron expression (e.g. `0 9 * * 1-5` = 9 AM on weekdays)
- A prompt to send to the AI

Automations fire against the active session.

---

## Settings

Access via **Merlin → Settings…** (⌘,).

| Section | What you configure |
|---|---|
| **General** | Default permission mode, auto-compaction toggle, max context tokens, keep-awake toggle |
| **Appearance** | Theme (light/dark/system), font size, accent colour, line spacing |
| **Providers** | Enable/disable providers, set API keys, base URLs, and model names |
| **Agents** | Custom subagent definitions loaded from `~/.merlin/agents/` |
| **Hooks** | Lifecycle hooks with event, command, and enabled toggle |
| **Scheduler** | Cron-based task automations |
| **Memories** | Enable/disable memory generation, configure idle timeout |

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New session |
| ⌘. | Stop the current agent turn |
| ⌘⇧P | Pop out current session as floating window |
| ⌘, | Open Settings |
| Return | Send message |
| Shift+Return | New line in input |
| / (in input) | Open skills picker |
| @ (in input) | Open file @-mention picker |
| Ctrl+` | Toggle Terminal pane |
| ⌘⇧/ | Toggle Side Chat |
| ⌘⇧M | Review Memories |

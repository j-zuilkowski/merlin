# Merlin — Subagent Reference

Subagents are scoped agentic loops that run inside a parent session. The parent engine spawns them via the `spawn_agent` tool; results flow back as `AgentEvent.subagentUpdate` events and appear as collapsible blocks in the parent conversation.

---

## Built-in Agent Roles

Three built-in agent definitions register at launch via `AgentRegistry.shared.registerBuiltins()`.

### explorer

Read-only research agent. Gathers information in parallel without modifying any files or running stateful commands.

| Property | Value |
|---|---|
| Role | `explorer` |
| Allowed tools | `read_file`, `list_directory`, `search_files`, `run_shell` (read-only subset) |
| Worktree isolation | No — operates on the live working tree, read-only |
| Result | Summarised and injected back into the parent conversation |

Use when: you need to inspect code, read documentation, or search for symbols without risking side effects.

### worker

Read-write agent with git worktree isolation. File writes are captured in the worker's own `StagingBuffer`, visible in the sidebar **Worker Diff View**.

| Property | Value |
|---|---|
| Role | `worker` |
| Allowed tools | All built-in tools |
| Worktree isolation | Yes — `WorktreeManager` creates a dedicated branch |
| Result | Staged diff shown in sidebar; parent can accept or reject |

Use when: you want the agent to write, edit, or delete files without conflicting with the main working tree.

### default

General-purpose agent, same tool set as the parent engine. No worktree isolation.

| Property | Value |
|---|---|
| Role | `default` |
| Allowed tools | All built-in tools |
| Worktree isolation | No |

---

## Custom Agent Definitions

Define custom agents in `~/.merlin/agents/` as TOML files. Each file is one agent. `AgentRegistry` watches the directory and reloads automatically.

```toml
name = "code-reviewer"
role = "explorer"
description = "Review code for correctness and style."
model = "pro"
allowed_tools = ["read_file", "list_directory", "search_files"]
```

| Field | Required | Values | Notes |
|---|---|---|---|
| `name` | Yes | string | Used in `spawn_agent` calls |
| `role` | Yes | `"explorer"` / `"worker"` / `"default"` | Determines tool set and isolation |
| `description` | No | string | Shown in Settings → Agents |
| `model` | No | `"pro"` / `"flash"` | Overrides provider slot; defaults to execute slot |
| `allowed_tools` | No | `[string]` | Restricts the tool set; omit to inherit the role default |
| `instructions` | No | string | Injected as a system prompt addendum |

---

## SpawnAgentTool Parameters

When the engine calls `spawn_agent`, the following JSON parameters are accepted:

| Parameter | Type | Required | Description |
|---|---|---|---|
| `agent` | string | Yes | Name of a built-in or custom agent definition |
| `task` | string | Yes | The prompt to run inside the subagent |
| `context` | string | No | Additional context injected before the task prompt |

---

## SubagentEvent Stream

The parent engine yields these events while a subagent runs:

```swift
case subagentStarted(id: UUID, agentName: String)
case subagentUpdate(id: UUID, event: AgentEvent)   // mirrors all child AgentEvent values
```

The UI renders these as a collapsible block labelled with the agent name. The block expands to show the subagent's tool call log and final response.

---

## Depth and Thread Limits

| Setting | Config key | Default |
|---|---|---|
| Max subagent depth | `agent_max_subagent_depth` | 2 |
| Max concurrent subagents | `agent_max_concurrent_subagents` | 4 |

Configure in `~/.merlin/config.toml` under `[settings]`. Depth is the nesting limit — a subagent cannot itself spawn subagents beyond this depth.

---

## Settings → Agents

Open **Settings → Agents** to see all loaded agent definitions (built-in and custom). The panel shows each agent's name, role, and allowed tools. Custom agents loaded from `~/.merlin/agents/` appear here automatically after the file is saved.

---

## Source Files

| File | Purpose |
|---|---|
| `Merlin/Agents/AgentRegistry.swift` | `actor` holding named `AgentDefinition` structs; loads TOML from `~/.merlin/agents/` |
| `Merlin/Agents/SubagentEngine.swift` | Scoped agentic loop for `explorer` and `default` roles |
| `Merlin/Agents/WorkerSubagentEngine.swift` | Worker role with `WorktreeManager` isolation |
| `Merlin/Tools/Agents/SpawnAgentTool.swift` | Resolves the definition, creates the engine, returns results |
| `Merlin/Views/Settings/AgentsSettingsView.swift` | Settings UI |

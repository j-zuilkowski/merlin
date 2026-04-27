# Merlin Skill & Plugin Standard

Merlin implements the [Agent Skills](https://agentskills.io) open standard, the same standard used by Claude Code and Codex. Skills written for either product work in Merlin without modification. This document codifies the subset of the standard that Merlin supports, plus the plugin packaging format.

---

## Skills

A skill is a directory containing a `SKILL.md` file. The directory name becomes the slash command.

```
my-skill/
├── SKILL.md            required — instructions + frontmatter
├── reference.md        optional — detailed docs loaded on demand
├── examples.md         optional — example outputs
└── scripts/
    └── helper.sh       optional — scripts Claude can run
```

### SKILL.md format

```
---
<YAML frontmatter>
---

<Markdown instructions>
```

Both sections are optional, but at minimum include a `description` so Merlin knows when to use the skill automatically.

---

## Frontmatter fields

All fields are optional.

| Field | Type | Description |
|---|---|---|
| `name` | string | Display name and slash command. Defaults to directory name. Lowercase, hyphens, numbers only. Max 64 chars. |
| `description` | string | What the skill does and when to use it. Claude reads this to decide when to load the skill automatically. Front-load the key use case — truncated at 1,536 chars in the skill listing. |
| `when_to_use` | string | Additional trigger phrases or example requests. Appended to `description` in the listing, counts toward the 1,536-char cap. |
| `argument-hint` | string | Shown in autocomplete. Example: `[issue-number]` or `[filename] [format]`. |
| `arguments` | string or list | Named positional arguments for `$name` substitution. Maps names to positions in order. |
| `disable-model-invocation` | bool | `true` = only the user can invoke this skill. Removes it from Claude's context entirely. Use for side-effect workflows: `/deploy`, `/commit`, `/send-message`. Default: `false`. |
| `user-invocable` | bool | `false` = hides from the `/` menu. Claude can still invoke it. Use for background reference skills users shouldn't call directly. Default: `true`. |
| `allowed-tools` | string or list | Tools Claude may use without an AuthGate prompt while this skill is active. Does not restrict other tools. Example: `Bash(git add *) Bash(git commit *)`. |
| `model` | string | Model to use for this skill's turn. Overrides the session model for the current turn only. Accepts any model ID Merlin recognises (e.g. `deepseek-v4-pro`, `deepseek-v4-flash`). Default: inherits from session. |
| `context` | string | Set to `fork` to run the skill in an isolated subagent. The skill body becomes the subagent's prompt. It has no access to conversation history. |
| `paths` | string or list | Glob patterns. When set, Claude only loads this skill automatically when working with files that match. Example: `**/*.swift` or `["src/**", "tests/**"]`. |

---

## String substitutions

These placeholders are expanded before the skill body reaches Claude.

| Placeholder | Expands to |
|---|---|
| `$ARGUMENTS` | Full argument string as typed after the skill name |
| `$ARGUMENTS[N]` | Argument at 0-based index N |
| `$N` | Shorthand for `$ARGUMENTS[N]` |
| `$name` | Named argument declared in `arguments` frontmatter |
| `${MERLIN_SESSION_ID}` | Current session UUID |
| `${MERLIN_SKILL_DIR}` | Absolute path to the skill's directory |

Multi-word arguments must be quoted: `/my-skill "hello world" second` → `$0` = `hello world`, `$1` = `second`.

If `$ARGUMENTS` is not present in the body and the user passes arguments, Merlin appends `ARGUMENTS: <value>` to the end of the skill body.

---

## Shell injection

Backtick-prefixed commands run before the skill body is sent to Claude. Their stdout replaces the placeholder. This is preprocessing — Claude only sees the final rendered output.

**Inline form:**

```
PR diff: !`gh pr diff`
```

**Block form (multi-line):**

````
```!
node --version
git status --short
```
````

Shell injection uses `/bin/bash`. To disable shell injection globally, set `disableSkillShellExecution: true` in Merlin settings.

---

## Skill locations

Merlin loads skills from these directories in priority order (highest first):

| Scope | Path | Applies to |
|---|---|---|
| Project | `.merlin/skills/<name>/SKILL.md` | This project only |
| Personal | `~/.merlin/skills/<name>/SKILL.md` | All projects |
| Plugin | `<plugin-dir>/skills/<name>/SKILL.md` | Where plugin is enabled |

When skills share the same name, project overrides personal, personal overrides plugin. Plugin skills are namespaced (`/plugin-name:skill-name`) so they cannot conflict with standalone skills.

Merlin watches all skill directories for changes. Edits to `SKILL.md` take effect within the current session without restart. Run `/reload-plugins` to force a reload.

---

## Skill lifecycle

When a skill is invoked, its rendered body enters the conversation as a user message and stays for the rest of the session. Merlin does not re-read the skill file on later turns.

During context compaction, invoked skills are re-attached after the summary (first 5,000 tokens each, combined budget 25,000 tokens, most-recently-invoked first).

---

## Built-in skills

These ship with Merlin and are always available.

| Skill | Description | Invocation |
|---|---|---|
| `/review` | Code review of staged changes | User or model |
| `/plan` | Switch to plan mode and map out a task | User only |
| `/commit` | Generate a commit message from staged diff | User only |
| `/test` | Write tests for a function or module | User or model |
| `/explain` | Explain selected code in plain English | User or model |
| `/debug` | Debug a failing test or error | User or model |
| `/refactor` | Propose a refactor for a code section | User or model |
| `/summarise` | Summarise the current session | User only |

---

## Plugins

A plugin is a directory of skills, optional agents, optional hooks, and optional MCP server configs, identified by a manifest file.

### Directory layout

```
my-plugin/
├── .merlin-plugin/
│   └── plugin.json      required — plugin manifest
├── skills/
│   └── review/
│       └── SKILL.md
├── agents/              optional — custom subagent definitions
├── hooks/
│   └── hooks.json       optional — event hooks
├── .mcp.json            optional — MCP server configs
└── settings.json        optional — default settings when plugin is active
```

**Important:** Only `plugin.json` goes inside `.merlin-plugin/`. All other directories live at the plugin root.

### Plugin manifest (`plugin.json`)

```json
{
  "name": "my-plugin",
  "description": "What this plugin does",
  "version": "1.0.0",
  "author": {
    "name": "Your Name",
    "url": "https://github.com/yourname"
  },
  "homepage": "https://github.com/yourname/my-plugin",
  "repository": "https://github.com/yourname/my-plugin",
  "license": "MIT",
  "keywords": ["swift", "xcode", "review"]
}
```

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Unique identifier and skill namespace. Skills become `/name:skill`. Kebab-case. |
| `description` | Yes | Shown in the plugin manager. |
| `version` | No | If set, updates only apply when bumped. If omitted, every git commit is a new version. |
| `author` | No | Attribution. |
| `homepage` | No | Link shown in plugin manager. |
| `repository` | No | Git URL — used for git-based installation. |
| `license` | No | SPDX identifier. |
| `keywords` | No | Array of strings for discovery. |

### Skill namespacing

Plugin skills are always namespaced to prevent conflicts:

```
/my-plugin:review
/my-plugin:deploy
```

The namespace is the `name` field from `plugin.json`. Standalone skills (`.merlin/skills/`) keep short names with no prefix.

### MCP server configuration (`.mcp.json`)

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/jon/Projects"]
    }
  }
}
```

Environment variable references in `${VAR}` syntax are expanded from the user's shell environment. MCP tools are registered into Merlin's `ToolRouter` as `mcp:<server>:<tool>` and go through `AuthGate` identically to native tools.

### Event hooks (`hooks/hooks.json`)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "write_file|create_file",
        "hooks": [
          {
            "type": "command",
            "command": "swiftlint lint --fix \"$MERLIN_TOOL_INPUT_PATH\""
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "run_shell",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"$MERLIN_TOOL_INPUT\" | grep -q 'rm -rf' && exit 1 || exit 0"
          }
        ]
      }
    ]
  }
}
```

Hook events:

| Event | Fires |
|---|---|
| `PreToolUse` | Before a tool call executes. Non-zero exit blocks the call. |
| `PostToolUse` | After a tool call completes. |
| `SessionStart` | When a session opens. |
| `SessionEnd` | When a session closes. |

Hook environment variables:

| Variable | Value |
|---|---|
| `$MERLIN_TOOL_NAME` | Name of the tool being called |
| `$MERLIN_TOOL_INPUT` | Full JSON arguments string |
| `$MERLIN_TOOL_INPUT_PATH` | `path` argument if present, else empty |
| `$MERLIN_TOOL_RESULT` | Tool result (PostToolUse only) |
| `$MERLIN_SESSION_ID` | Current session UUID |

### Default settings (`settings.json`)

```json
{
  "agent": "security-reviewer",
  "permissionMode": "ask"
}
```

Applied when the plugin is enabled. Supported keys: `agent`, `permissionMode`. Unknown keys are silently ignored.

---

## Installing plugins

### Via git URL (recommended)

```
/plugin install https://github.com/yourname/my-plugin
```

Clones to `~/.merlin/plugins/<name>/` and activates.

### Via local directory (development)

```
/plugin install --local ./my-plugin
```

Or launch Merlin with the flag:

```bash
open Merlin.app --args --plugin-dir ./my-plugin
```

Local plugins take precedence over installed plugins of the same name.

### Managing plugins

```
/plugin list          — list installed plugins and their status
/plugin disable name  — disable without uninstalling
/plugin enable name   — re-enable
/plugin remove name   — uninstall
/reload-plugins       — hot-reload all plugins in the current session
```

Installed plugins cache to `~/.merlin/plugins/<name>/`.

---

## Compatibility

Skills and plugins written to this standard are compatible with Claude Code and Codex with these differences:

| | Merlin | Claude Code | Codex |
|---|---|---|---|
| Manifest location | `.merlin-plugin/plugin.json` | `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` |
| Skill standard | Agent Skills (agentskills.io) | Agent Skills | Agent Skills |
| Personal skills | `~/.merlin/skills/` | `~/.claude/skills/` | `~/.codex/skills/` |
| Project skills | `.merlin/skills/` | `.claude/skills/` | `.codex/skills/` |
| Session variable | `${MERLIN_SESSION_ID}` | `${CLAUDE_SESSION_ID}` | — |
| Skill dir variable | `${MERLIN_SKILL_DIR}` | `${CLAUDE_SKILL_DIR}` | — |
| LSP servers | No | Yes | No |
| Background monitors | No | Yes | No |
| App integrations | No | No | Yes |

To make a skill portable across all three, avoid `${CLAUDE_*}` and `${MERLIN_*}` variables and do not use `context: fork` with Claude-specific agent types.

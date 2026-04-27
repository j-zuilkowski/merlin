# Gap Analysis: Merlin vs Codex App

Reference: https://developers.openai.com/codex/app
Date: 2026-04-26

---

## Merlin has it, Codex doesn't

| Feature | Notes |
|---|---|
| Auth sandbox + pattern memory | Per-tool glob ACL with persistent allow/deny — Codex has no equivalent |
| Tool discovery (PATH scan) | Auto-discovers local executables with `--help` summaries |
| Local vision model | LM Studio + Qwen2.5-VL for on-device screenshot analysis |
| Bring-your-own model + multi-provider | Anthropic Claude, DeepSeek, LM Studio (local) — API key only; in-app model picker switches provider per session |
| Accessibility tree inspection | Reads live AX element hierarchy, attributes, and focus state — Codex Computer Use sees only screenshots |
| CGEvent mouse/keyboard automation | Raw hardware-level input synthesis; works in terminal apps; no screen recording permission; no regional restrictions; fully on-device |
| Xcode-specific tools | Build, test, run, parse Xcode diagnostics natively — Codex has no equivalent for native IDE toolchains |

---

## Codex has it, Merlin doesn't

| Gap | Codex capability | Effort |
|---|---|---|
| **Parallel threads** | Multiple agent tasks running side-by-side with quick switching | High |
| **Git worktree UI** | Isolated per-thread worktrees, not just shell `git` commands | Medium |
| **Session sidebar (worktree list)** | Left panel listing open sessions, each pinned to a Git worktree; click to switch; activity/mode badges per session | Medium |
| **Subagents** | Explicit parallel agent spawning; custom agents defined in TOML (name, description, instructions, model, sandbox); 3 built-ins: default / worker / explorer; configurable max_threads and max_depth | High |
| **Floating pop-out window** | Detach any thread into a standalone floating window; optional always-on-top mode | Low |
| **Project picker / recent projects** | Dedicated launch screen to open or switch between project roots, with recents history | Low |
| **Diff / review pane** | Visual diff, file staging, commit + push from UI | High |
| **Inline diff commenting** | Comment on specific diff lines; agent reads comments and revises | Medium |
| **Scroll lock** | Manual scroll pauses auto-scroll to bottom while streaming; resumes at bottom | Low |
| **Integrated terminal** | Cmd+J persistent terminal pane scoped to current project/worktree; Codex reads its output directly to check status | Medium |
| **Voice dictation** | Ctrl+M to transcribe voice into the prompt composer | Low |
| **Interrupt / stop button** | Halt the agent mid-run and steer without starting over | Low |
| **Side chat** | Ask a question without derailing the main agent thread | Low |
| **PR workflow** | Address PR feedback inside a thread | Medium |
| **@filename / file attachment** | Inject a file by typing @filename; drag-drop files and images into the prompt | Low |
| **Recurring task scheduling** | Wake-up a thread on a schedule | Medium |
| **Thread automations** | Recurring wake-up calls *inside* a specific conversation thread, preserving context; distinct from standalone scheduled tasks | Medium |
| **Toolbar Actions** | Named one-click shortcuts (start dev server, run tests, build) configured per project; plus auto-setup scripts run when a new worktree is initialized | Low |
| **Notifications** | System notifications when tasks complete or need approval while backgrounded | Low |
| **Skills / plugin system** | Reusable skills shared across app, CLI, IDE | High |
| **Permission modes (ask / auto / plan)** | Ask before writes, auto-accept all edits, or plan-only (no file writes) | Medium |
| **CLAUDE.md / per-project instructions** | Per-project instruction file auto-injected as system prompt at session start | Low |
| **MCP server support** | Extend tool set via MCP protocol | Medium |
| **Hooks (lifecycle events)** | Shell scripts injected at PreToolUse, PostToolUse, UserPromptSubmit, Stop, SessionStart, PermissionRequest; can block tool calls, augment prompts, enforce policies | Medium |
| **Built-in web search** | First-party search tool on by default; cached results locally, live results in full sandbox | Low |
| **AI-generated memories** | Agent auto-extracts and writes memory files from past sessions (~/.codex/memories/); updated asynchronously; distinct from manually written per-project instructions | Medium |
| **Personalization** | Agent personality modes (Friendly / Pragmatic / None) plus standing custom instructions, separate from per-project instruction files | Low |
| **Reasoning effort selector** | High / Medium / Low reasoning effort per session or subagent; trades quality against speed and token cost | Low |
| **Context usage indicator** | /status command shows thread ID, context window % used, and current rate limit info | Low |
| **Deeplinks** | codex:// URL scheme to open specific threads, skills, or automations programmatically | Low |
| **In-app browser** | Render pages and run local browser automation | High |
| **Image generation / editing** | Generate or edit images within a thread | Medium |
| **File / artifact preview pane** | Rendered previews of generated files | Medium |
| **Cloud sync** | Threads sync between desktop and IDE extension | High |
| **Cloud-level integration depth** | GitHub: auto-reviews every new PR, fixes CI failures autonomously; Slack: full agent tasks from @Codex channel mentions; Linear: assign issues directly to Codex, auto-triage rules — Merlin's connectors are REST/GraphQL wrappers only | High |
| **Windows support** | Cross-platform — Merlin is macOS-only (by design) | N/A |

---

## Key takeaways

The **biggest functional gap** is parallel threading + git worktrees — Codex's core workflow is running multiple isolated tasks concurrently with a proper review step before committing. Merlin is a single serial conversation.

The **most actionable near-term gaps** for a personal tool:

1. **MCP server support** — plugs in any MCP-compatible tool without writing Swift
2. **Diff / review pane** — shell can run `git diff` but there is no rendered view
3. **Recurring scheduling** — useful for autonomous checks (CI status, PR triage, etc.)

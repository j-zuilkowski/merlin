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
| Bring-your-own model | DeepSeek V4 via API key; no subscription lock-in |

---

## Codex has it, Merlin doesn't

| Gap | Codex capability | Effort |
|---|---|---|
| **Parallel threads** | Multiple agent tasks running side-by-side with quick switching | High |
| **Git worktree UI** | Isolated per-thread worktrees, not just shell `git` commands | Medium |
| **Diff / review pane** | Visual diff, file staging, commit + push from UI | High |
| **PR workflow** | Address PR feedback inside a thread | Medium |
| **Recurring task scheduling** | Wake-up a thread on a schedule | Medium |
| **Skills / plugin system** | Reusable skills shared across app, CLI, IDE | High |
| **MCP server support** | Extend tool set via MCP protocol | Medium |
| **In-app browser** | Render pages and run local browser automation | High |
| **Image generation / editing** | Generate or edit images within a thread | Medium |
| **File / artifact preview pane** | Rendered previews of generated files | Medium |
| **Cloud sync** | Threads sync between desktop and IDE extension | High |
| **Windows support** | Cross-platform — Merlin is macOS-only (by design) | N/A |

---

## Key takeaways

The **biggest functional gap** is parallel threading + git worktrees — Codex's core workflow is running multiple isolated tasks concurrently with a proper review step before committing. Merlin is a single serial conversation.

The **most actionable near-term gaps** for a personal tool:

1. **MCP server support** — plugs in any MCP-compatible tool without writing Swift
2. **Diff / review pane** — shell can run `git diff` but there is no rendered view
3. **Recurring scheduling** — useful for autonomous checks (CI status, PR triage, etc.)

# Gap Analysis: Merlin vs Claude Code Desktop

Reference: https://code.claude.com/docs/en/desktop-quickstart
Date: 2026-04-26

---

## Merlin has it, Claude Code Desktop doesn't

| Feature | Notes |
|---|---|
| Auth sandbox + pattern memory | Per-tool glob ACL with persistent allow/deny — no equivalent in Claude Code |
| Tool discovery (PATH scan) | Auto-discovers local executables and probes `--help` for summaries |
| Local vision model | LM Studio + Qwen2.5-VL for on-device screenshot analysis |
| Bring-your-own model (DeepSeek) | No subscription required — API key only |
| Accessibility tree inspection | Full AX API integration for reading live UI state |
| CGEvent mouse/keyboard automation | Synthesize low-level input events |
| Xcode-specific tools | Build, test, run, parse Xcode diagnostics natively |

---

## Claude Code Desktop has it, Merlin doesn't

### Workspace & UI
| Gap | Claude Code capability | Effort |
|---|---|---|
| **Parallel sessions** | Multiple tasks side-by-side, each in its own Git worktree | High |
| **Diff / review pane** | Visual diff per file with Accept/Reject per change | High |
| **Inline diff commenting** | Comment on specific lines; Claude reads and revises | Medium |
| **Integrated file pane** | Click any file path to open it in a dedicated pane | Medium |
| **Live app preview pane** | Runs dev server in-app; Claude inspects logs and iterates | High |
| **Draggable pane layout** | Chat, diff, terminal, file, preview all rearrangeable | Medium |
| **Side chat** | Ask a question without derailing the main session thread | Low |
| **Interrupt / stop button** | Halt Claude mid-run and steer without starting over | Low |
| **Scroll lock** | Manual upward scroll pauses auto-scroll; streaming continues off-screen; resumes on reaching bottom | Low |

### Context & input
| Gap | Claude Code capability | Effort |
|---|---|---|
| **@filename context** | Pull a specific file into the prompt by typing `@filename` | Low |
| **File / image attachment** | Drag and drop files, images, PDFs into the prompt | Low |

### Permission model
| Gap | Claude Code capability | Effort |
|---|---|---|
| **Permission modes** | Ask (default), Auto-accept edits, Plan mode (no writes) | Medium |
| **Plan mode** | Claude maps out an approach without touching any files | Low |

### Git & code review
| Gap | Claude Code capability | Effort |
|---|---|---|
| **Git worktree isolation** | Each session works in its own worktree, not the working tree | High |
| **PR monitoring + auto-merge** | Watches CI checks; auto-fixes failures or merges when green | High |

### Automation & scheduling
| Gap | Claude Code capability | Effort |
|---|---|---|
| **Recurring scheduled tasks** | Daily/weekly autonomous runs (code review, dependency audit) | Medium |
| **Background subagents** | Tasks pane shows subagents and background commands per session | High |

### Extensibility
| Gap | Claude Code capability | Effort |
|---|---|---|
| **MCP server support** | Plug in any MCP-compatible tool without writing Swift | Medium |
| **Skills / slash commands** | Reusable prompts invokable with `/` (custom + plugin) | Medium |
| **Plugin system** | Install skills, agents, MCP servers from a plugin browser | High |
| **External connectors** | GitHub, Slack, Linear integrations out of the box | High |
| **CLAUDE.md support** | Per-project instruction files Claude reads automatically | Low |

### Session environments
| Gap | Claude Code capability | Effort |
|---|---|---|
| **Remote sessions (cloud VM)** | Runs on Anthropic infrastructure; continues when app is closed | High |
| **SSH sessions** | Connect to remote machines; Claude Code auto-installs on first connect | High |
| **Web / IDE continuation** | Hand off a session to the web app or IDE extension mid-task | High |

### Model selection
| Gap | Claude Code capability | Effort |
|---|---|---|
| **In-app model picker** | Switch between Opus, Sonnet, Haiku per session | Low |

---

## Key takeaways

**Biggest structural gap**: Claude Code Desktop is built around sessions-as-worktrees — every task is isolated, diffed, reviewed, and merged. Merlin has no diff layer and works directly on the live working tree with no staging step.

**Most impactful gaps for daily use**:
1. **Diff / review pane** — without it every tool-written file change is invisible until you open a terminal
2. **Interrupt / stop button** — no way to halt a runaway tool loop without killing the app
3. **@filename + attachment** — context injection is manual copy-paste today
4. **CLAUDE.md** — per-project instructions would make every session context-aware with no prompt boilerplate
5. **MCP server support** — removes the need to write a Swift wrapper for every new tool

**Gaps that are lower priority for a personal local tool**:
- Remote/SSH sessions (Merlin is intentionally local-first)
- Cloud continuation (single-user, single-machine)
- PR auto-merge (can be done via shell tool today)
- Plugin browser (auth sandbox already covers trust for local tools)

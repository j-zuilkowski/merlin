# Gap Analysis: Merlin vs Claude Code

Reference: https://code.claude.com/docs/en
Date: 2026-04-30
Merlin version: v9

---

## Merlin has it, Claude Code doesn't

| Feature | Notes |
|---|---|
| **Multi-provider + bring-your-own model** | Anthropic, DeepSeek, OpenAI, Qwen, OpenRouter, LM Studio, Ollama, Jan.ai, LocalAI, Mistral.rs, vLLM — API key only, no subscription lock-in. Claude Code is Anthropic-only; no local model support beyond a limited Ollama workaround |
| **Local model support (full)** | LM Studio, Ollama, Jan.ai, LocalAI, Mistral.rs, vLLM with zero API cost; model picker switches provider per session |
| **Local vision model** | LM Studio + Qwen2.5-VL for on-device screenshot analysis — no cloud dependency |
| **Auth sandbox + pattern memory** | Per-tool glob ACL with an interactive Allow/Deny popup (Allow Once / Allow Always / Deny Once / Deny Always) and persistent allow/deny patterns per tool. Claude Code uses a classifier (auto mode) and static allowlists — no per-turn interactive popup or per-tool glob pattern memory |
| **Accessibility tree inspection** | Full AX API integration for reading live UI state; finds, reads, and interacts with AX elements — Claude Code has no AX equivalent |
| **CGEvent mouse/keyboard automation** | Synthesizes low-level input events; works in terminal apps; no screen recording permission needed; fully on-device |
| **Xcode-specific tools** | Build, test, clean, .xcresult parsing, simulator control, open-at-line via AppleScript — Claude Code uses an IDE plugin approach only; it cannot own the build loop or parse build artifacts |
| **Supervisor-worker multi-LLM routing** | Classifies each task into routine / standard / high-stakes tiers; dispatches to execute / reason / orchestrate / vision slots, each assignable to a different provider. Claude Code uses a single model for all operation types |
| **Critic engine** | Two-stage per-turn evaluation: (1) domain verification backend (e.g. `xcodebuild` for Swift tasks), (2) LLM scoring on a 0–1 scale. Results gate memory writes and drive automatic correction loops. No equivalent in Claude Code |
| **Staged diff review with inline agent feedback** | All writes intercepted and queued in Ask and Plan modes; unified colour-coded diff per file; Accept/Reject per change or all at once; inline comments on any diff line fed back to the agent for in-place revision. Claude Code applies writes directly; the VS Code extension shows diffs after the fact with no staged write workflow |
| **Persistent local RAG memory (v9)** | SQLite + Apple NLContextualEmbedding (512-dim, on-device, no external dependencies); factual + episodic chunks; top-5 cosine retrieval per turn; critic-gated writes; fully local. Anthropic explicitly chose not to add RAG to Claude Code — they rely on agentic grep/search instead |
| **LoRA self-training** | MLX-LM fine-tuning on accepted session data on an M4 Mac; auto-train at sample threshold; routes execute slot through the trained adapter; quality-gated export. No equivalent in Claude Code |
| **Model calibration (/calibrate)** | 18-prompt benchmark across four categories (reasoning, coding, instruction-following, summarization) against any reference provider; identifies context length, temperature, truncation, and repetition issues; one-tap "Apply All Suggestions" via advisory pipeline |
| **Performance tracking dashboard** | `ModelPerformanceTracker` records per-model × task-type outcomes; exponential decay success rate; trend detection (improving / stable / declining); feeds LoRA training data export |
| **Circuit breaker (v9)** | Surfaces sustained quality degradation after N consecutive critic failures via `systemNote`; configurable threshold and halt vs. warn mode; prevents silent accumulation of bad outputs |
| **Grounding confidence (v9)** | Per-turn `GroundingReport`: chunk count, average retrieval score, memory staleness flag, `isWellGrounded`; addresses the context degradation failure pattern |
| **Thread automations** | Recurring prompts within a live session on a schedule (e.g. "check CI status every 15 minutes") — distinct from opening a new session; GUI-managed in Merlin. Claude Code has `/loop` for in-session scheduling in the CLI only |
| **Domain registry** | Pluggable `DomainPlugin` system; injects domain-specific verification commands and system prompt addenda per slot (e.g. Swift/Xcode conventions for the execute slot) |
| **Voice dictation** | Ctrl+M to start/stop; transcribed via SFSpeechRecognizer and appended to prompt. Not available in Claude Code |
| **Toolbar Actions** | Custom one-click prompt buttons above the chat input, configured per project. No equivalent in Claude Code |
| **macOS-native, non-sandboxed** | Deep integration with AX API, ScreenCaptureKit, CGEvent, SFSpeechRecognizer, macOS Keychain; all three GUI automation strategies auto-selected per target app. Claude Code is a CLI tool with no native GUI layer |

---

## Claude Code has it, Merlin doesn't

### Cloud & Remote Execution

| Gap | Claude Code capability | Effort |
|---|---|---|
| **Cloud Routines** | Saved automations (prompt + repos + connectors) that run on Anthropic-managed infrastructure — scheduled (hourly/daily/weekdays/weekly/one-off), API-triggered (HTTP POST with bearer token), or GitHub event-triggered (pull_request, release, etc.). Continue without your laptop on. Merlin's scheduler is local and requires the machine to be running | High |
| **Remote sessions (cloud VM)** | Claude Code on the web runs full sessions in isolated VMs on Anthropic infrastructure; tasks continue when app is closed | High |
| **SSH sessions** | Connect to remote Mac and Linux machines; Claude Code auto-installs on first connect | High |
| **Remote Control (mobile/web)** | Send instructions from your phone or the claude.ai web app; Claude Code executes desktop operations on your Mac via an encrypted channel. Files never leave your computer | High |

### Extensibility

| Gap | Claude Code capability | Effort |
|---|---|---|
| **Plugin marketplace** | Community and Anthropic plugins bundle skills, hooks, subagents, and MCP servers into a single installable unit; `/plugin` to browse the catalog; shared session history across app, CLI, and IDE extensions | High |
| **Agent teams** | Automated coordination of multiple sessions with a team lead, shared task queue, and cross-session messaging | High |

### Browser Integration

| Gap | Claude Code capability | Effort |
|---|---|---|
| **Claude in Chrome extension** | Opens tabs in the user's browser, tests UI interactions, takes screenshots, and iterates on frontend designs with visual verification — paired with VS Code extension for full round-trip feedback | Medium |

### Minor

| Gap | Claude Code capability | Effort |
|---|---|---|
| **Scroll lock** | Manual scroll pauses auto-scroll to bottom while streaming; resumes at bottom | Low |
| **Checkpoint restoration (/rewind)** | Restores conversation, code state, or both to any prior checkpoint; checkpoints persist across sessions; distinct from git history | Low |
| **/btw (side questions)** | Quick question in a dismissible overlay that never enters conversation history, keeping the main context clean | Low |

---

## Key takeaways

**The biggest structural gap from the original (2026-04-26) analysis is now closed.** The original document identified the lack of sessions-as-worktrees and a diff review layer as the core deficit. Merlin now has full git worktree isolation per session, a staged diff review layer with inline commenting and agent revision, parallel sessions, and subagents. All five "most impactful daily use" gaps from the original doc (diff pane, stop button, @filename, CLAUDE.md, MCP) are implemented.

**Remaining gaps are almost entirely cloud-side:**
1. **Cloud Routines** — tasks that must run overnight, on a schedule, or on GitHub events without the machine being on
2. **Remote sessions** — execution on Anthropic infrastructure when away from the local Mac
3. **SSH sessions** — access to remote machines
4. **Plugin marketplace** — community plugin discovery and one-click install; Merlin has a skills system but no catalog

**Merlin now significantly exceeds Claude Code on:**
- **Provider freedom** — any model (local or remote) vs. Anthropic-only
- **Multi-LLM routing** — complexity-based dispatch to specialised slots vs. single model for all tasks
- **Staged diff review with inline agent feedback** — intercepted writes with per-change accept/reject and agent revision loop vs. direct writes with after-the-fact VS Code diffs
- **Local RAG memory** — on-device SQLite vector store with critic-gating vs. agentic grep
- **LoRA self-training** — unique to Merlin; adapts the local model to your own accepted sessions over time
- **Deep macOS integration** — AX tree, CGEvent, native Xcode toolchain, SFSpeechRecognizer
- **Behavioral reliability** — critic engine, circuit breaker, grounding confidence, performance tracking

**Gaps that are low priority for a personal local tool:**
- Cloud Routines (Merlin's local scheduler covers most scheduling needs; machine is available during working hours)
- Remote sessions (Merlin is intentionally local-first)
- SSH sessions (single-machine workflow)
- Plugin marketplace (skills system covers personal use; no need for community discovery)

# Gap Analysis: Merlin vs Codex App

Reference: https://openai.com/codex / https://developers.openai.com/codex/changelog
Date: 2026-04-30
Merlin version: v9

---

## Merlin has it, Codex doesn't

| Feature | Notes |
|---|---|
| **Multi-provider + bring-your-own model** | Anthropic, DeepSeek, OpenAI, Qwen, OpenRouter, LM Studio, Ollama, Jan.ai, LocalAI, Mistral.rs, vLLM — API key only, no subscription lock-in; in-app model picker switches provider per session. Codex is GPT-only |
| **Local model support** | LM Studio, Ollama, Jan.ai, LocalAI, Mistral.rs, vLLM with zero API cost. Codex is cloud-first; no local model support |
| **Local vision model** | LM Studio + Qwen2.5-VL for on-device screenshot analysis — no cloud dependency |
| **Auth sandbox + pattern memory** | Per-tool glob ACL with an interactive Allow/Deny popup (Allow Once / Allow Always / Deny Once / Deny Always) and persistent allow/deny patterns per tool. Codex has configurable sandboxing and permission profiles but no per-tool glob pattern ACL with interactive per-turn memory |
| **Accessibility tree inspection** | Reads live AX element hierarchy, attributes, and focus state — Codex Computer Use sees only screenshots |
| **CGEvent mouse/keyboard automation** | Raw hardware-level input synthesis; works in terminal apps; no screen recording permission; no regional restrictions; fully on-device |
| **Xcode-specific tools** | Build, test, run, parse .xcresult bundles, simulator control, open-at-line via AppleScript — Codex has no equivalent for native IDE toolchains |
| **Hooks on all lifecycle events** | `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop` — can block tool calls, augment prompts, enforce policies. Codex has a hooks/config.toml system focused on MCP tool configuration and session setup, not tool-call lifecycle interception |
| **Supervisor-worker multi-LLM routing** | Complexity-based task routing (routine / standard / high-stakes) to execute / reason / orchestrate / vision slots, each assignable to a different provider. Codex uses a single GPT model for all operations |
| **Critic engine** | Two-stage per-turn evaluation: (1) domain verification backend (e.g. `xcodebuild`), (2) LLM scoring on a 0–1 scale. Drives correction loops and gates memory writes. Codex has no critic layer |
| **Staged diff review with inline agent feedback** | All writes intercepted and queued in Ask and Plan modes; unified diff per file; Accept/Reject per change or all at once; inline comments on any diff line fed back to the agent for in-place revision. Codex has a diff review UI (final-step, open in VS Code) but applies writes directly — no staged write workflow and no agent feedback from inline comments |
| **Persistent local RAG memory (v9)** | SQLite + Apple NLContextualEmbedding (512-dim, on-device, no external dependencies); factual + episodic chunks; top-5 cosine retrieval per turn; critic-gated writes; fully local. Codex has no RAG layer |
| **LoRA self-training** | MLX-LM fine-tuning on accepted session data on an M4 Mac; auto-train at sample threshold; routes execute slot through the trained adapter; quality-gated export. No equivalent in Codex |
| **Model calibration (/calibrate)** | 18-prompt benchmark across four categories against any reference provider; parameter advisories (context length, temperature, truncation, repetition); one-tap "Apply All Suggestions" |
| **Performance tracking dashboard** | Per-model × task-type empirical profiles; exponential decay success rate; trend detection; training data export for LoRA |
| **Circuit breaker (v9)** | Surfaces sustained quality degradation after N consecutive critic failures via `systemNote`; configurable halt vs. warn mode; prevents silent accumulation |
| **Grounding confidence (v9)** | Per-turn `GroundingReport`: chunk count, average retrieval score, staleness flag, `isWellGrounded` — addresses the context degradation failure pattern |
| **Domain registry** | Pluggable `DomainPlugin` system; injects domain-specific verification commands and system prompt addenda per slot (e.g. Swift/Xcode conventions for the execute slot) |
| **macOS-native, non-sandboxed** | Deep integration with AX API, ScreenCaptureKit, CGEvent, SFSpeechRecognizer, macOS Keychain; three GUI automation strategies auto-selected per target app |

---

## Codex has it, Merlin doesn't

| Gap | Codex capability | Effort |
|---|---|---|
| **Cloud sandbox execution** | Tasks run in isolated cloud sandboxes; agents continue working when the machine is off; useful for long-running overnight jobs. Merlin requires the local machine to be running | High |
| **SSH to remote devboxes** | Connect to remote Linux/Mac development boxes; agents run in cloud or remote infrastructure | High |
| **Cloud sync** | Threads, session history, and configuration sync between desktop app, CLI, and IDE extensions | High |
| **Cloud-level integration depth** | GitHub: auto-reviews every new PR, fixes CI failures autonomously; Slack: full agent tasks triggered by @Codex channel mentions; Linear: assign issues directly to Codex, auto-triage rules — Merlin's GitHub, Slack, and Linear connectors are REST/GraphQL wrappers the agent uses as tools, not reactive integrations | High |
| **Image generation / editing** | Generate or edit images within a thread via the skills system (Codex has an image generation skill) | Medium |
| **Plugin marketplace** | Community skills library on GitHub; open-source skills for Figma, Linear, Cloudflare, Netlify, Render, Vercel, document creation, etc.; one-click install. Merlin has a skills system but no community catalog or shared skills library | High |
| **Agent personality modes** | `/personality` command with Terse/execution-focused (default) and Conversational/empathetic modes. Merlin has standing custom instructions in Settings → Agent but no named personality modes | Low |
| **Deeplinks** | `codex://` URL scheme to open specific threads, skills, or automations programmatically from external apps | Low |
| **Scroll lock** | Manual scroll pauses auto-scroll to bottom while streaming; resumes at bottom | Low |

---

## Key takeaways

**The biggest structural gap from the original (2026-04-26) analysis is now closed.** The original document identified parallel threading with git worktrees and the lack of a pre-commit review step as the core Codex advantage. Merlin now has parallel sessions in isolated worktrees, a staged diff review layer with inline commenting and agent revision, subagents with up to 4 concurrent workers and 2 nesting levels, and both session-level and thread-level scheduling.

**The remaining real gaps are almost entirely cloud-side:**
1. **Cloud sandbox execution** — Codex tasks run remotely and persist when the machine is off; Merlin requires the local machine to be on
2. **Cloud-level integration depth** — Codex's GitHub/Slack/Linear integrations are reactive and deep (auto-review every PR, fix CI failures, Slack agent tasks, Linear auto-triage); Merlin's are REST wrappers that the agent uses as tools on demand
3. **Plugin marketplace** — community ecosystem around skill sharing; Merlin's skills system is equivalent in capability but has no community catalog

**Merlin now significantly exceeds Codex on:**
- **Provider freedom** — any model (local or remote) vs. GPT-only
- **Multi-LLM routing** — complexity-based dispatch to specialised slots vs. single model for all tasks
- **Staged diff review with inline agent feedback** — intercepted writes with per-change accept/reject and agent revision loop vs. final-step diff viewer before VS Code commit
- **Local RAG memory** — on-device SQLite vector store with critic-gating vs. no RAG layer
- **LoRA self-training** — unique to Merlin; adapts the local model to your own accepted sessions over time
- **Deep macOS integration** — AX tree, CGEvent, native Xcode toolchain, SFSpeechRecognizer
- **Behavioral reliability** — critic engine, circuit breaker, grounding confidence, performance tracking
- **Lifecycle hook interception** — PreToolUse can block any tool call including MCP tools; Codex hooks are session/tool configuration, not lifecycle interception

**Lower-priority gaps:**
- Image generation (not a core coding workflow need for Merlin's target use case)
- Deeplinks (URL scheme for external automation — low value for a single-user local tool)
- Cloud sync (single-machine personal tool; not needed)
- Personality modes (custom instructions in Settings → Agent already cover this)
- Scroll lock (cosmetic)

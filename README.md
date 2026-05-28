# Merlin

A personal, non-sandboxed agentic development assistant for macOS. Merlin connects to multiple LLM providers — remote and local — and gives an AI agent full access to your file system, shell, Xcode, GUI automation, and external services to work through development tasks autonomously. It includes a supervisor-worker multi-LLM routing layer and MLX LoRA self-training (MLX-format base models on Apple Silicon) to improve the execute slot on your own accepted sessions over time.

Built with Swift and SwiftUI for macOS 14+. Personal use only — not distributed; build from source via the steps in [`Requirements.md`](Requirements.md).

**Version 2.2.5** (build 24, tag v2.2.5)

---

## What it does

Merlin runs an agentic loop: you describe a task, the model calls tools (read files, run shell commands, build with Xcode, inspect UI, write code), reads the results, and continues until the task is complete. You review staged changes before they land on disk.

**Multi-project workspace** — a single window holds multiple open projects simultaneously. Each project has its own session list in the sidebar; the content area shows whichever session is active. Workspace state (open projects, active session) persists across relaunches.

**Session history** — every session is saved to disk after each turn, scoped per project. Prior sessions appear in the sidebar with relative timestamps. Sessions can be archived (hidden) or recalled to active status. Session titles are auto-generated from the first user message, matching Claude app and Codex behaviour.

**Multi-LLM Supervisor-Worker** — tasks are classified by complexity and routed to the right LLM slot (execute, reason, orchestrate, vision). A critic layer scores outputs; a planner layer decomposes high-stakes work. Model performance is tracked per-model per-task type and stored for training.

**Electronics / KiCad Domain** (v2.0) — a full electronics workflow built on the bus-backed `plugins/electronics` runtime plugin: raster/PDF schematic ingestion, KiCad project and footprint generation, FreeRouting-backed autoroute, ERC/DRC/SPICE/fab verification gates, vendor-native BOM and order workflows. Evidence-gated completion and high-stakes signoff boundaries block irreversible manufacturing actions without explicit approval.

**Multi-Domain Sessions** — each session carries its own active domain IDs. Switching from a software session to an electronics session is instant; the engine, critic, and task-type routing all follow without touching other open sessions.

**Local Memory Backend** — session memories are stored in an on-device SQLite vector store (`LocalVectorPlugin`, `NLContextualEmbedding`, 512-dim) scoped per project path. xcalibre-server is retained for book-content RAG only.

**Behavioral Reliability** — a circuit breaker halts or warns after consecutive critic failures; a grounding confidence signal (`GroundingReport`) surfaces RAG chunk count, average cosine score, and staleness on every turn so you can see when the model is reasoning over thin or stale retrieval.

**Budget-Aware Execution** (v2.1) — every LLM request is sized to the active provider's context window before it is sent. A pre-flight estimator gates each call; working-set caps bound the system prompt, RAG injection, recent turns, and tool-call bursts independently. Oversized work is decomposed into smaller substeps first, with cross-provider routing to a larger-context model only as a last resort.

**LoRA Self-Training** — on an M4 Mac with 128GB unified memory, Merlin can fine-tune a local **MLX-format** model (via MLX-LM) on your own accepted sessions. Automatic training requires an MLX base; GGUF and HF-safetensors bases cannot be trained by `mlx_lm.lora`. The trained adapter is served by any MLX-native runtime — `mlx_lm.server` (the default), LM Studio, or vLLM-Metal after a one-shot `mlx_lm.fuse` for text-only experiments, though vLLM-Metal is non-working for the current Merlin general+vision pair workflow and should be avoided for the foreseeable future. For GGUF providers (Ollama / Jan.ai / LocalAI / llama.cpp), an additional GGUF-conversion step deploys the fine-tuned model; Mistral.rs cannot serve MoE models on Metal regardless.

**Project Discipline** (v2.2) — Merlin can enforce construction discipline on any project: TDD task pairs, comprehensive user-manual coverage, WHY-comments where warranted, prose readability, and task-file/code sync. Five `/project:*` skills (`init`, `task`, `revise`, `release`, `adopt`) handle creation; a `DisciplineEngine` plus git hooks enforce the rules automatically. `/project:adopt` applies the discipline to an existing codebase.

See [`FEATURES.md`](FEATURES.md) for a complete capability reference.  
See [`spec.md`](spec.md) for implementation details and design decisions.

---

## Providers

Remote: **Anthropic**, **DeepSeek**, **OpenAI**, **Qwen**, **OpenRouter**

Local provider status (validated live on May 27, 2026):

Preferred local provider: **llama.cpp router mode**. Use it first for local
general+vision work because one router-mode `llama-server` can own the GGUF text
model, the GGUF vision model, and the vision `mmproj` behind one OpenAI-compatible
endpoint. LM Studio and Jan.ai remain reliable alternatives.

| Provider | Status | Notes |
|---|---|---|
| llama.cpp (router mode) | Preferred reliable | First-class provider at `http://localhost:8081/v1`; one router-mode server handled the local general+vision GGUF pair |
| LM Studio | Reliable alternative | General + vision pair passed live calibration |
| Jan.ai | Reliable alternative | General + vision pair passed live calibration |
| LocalAI | Non-working for Merlin full surface | Text, streaming, and vision responded, but tool-call requests returned plain content without OpenAI `tool_calls` |
| Ollama | Non-working for Merlin full surface | Text works, but the tested Qwen3-VL path crashes the runner on real image requests; skip until upstream fixes land |
| vLLM-Metal | Non-working / avoid | Text and auto tool calls can work, but forced tool choice is unreliable and vision is not implemented on Metal; avoid for the foreseeable future |
| Mistral.rs | Non-working for tested model | The tested Qwen3 MoE GGUF model loads, then fails on first inference on Apple Metal |

Upstream blocker tracking for the malfunctioning local providers lives in
[`docs/local-provider-configs/RESULTS.md`](docs/local-provider-configs/RESULTS.md).

`/calibrate` is live-validated in the app against the supported local providers. The GUI flow now completes picker → running → report, surfaces scorer failures materially better than before, and reports degraded critic fallback explicitly when it occurs.

Routing is driven by explicit slot assignments (Execute, Reason, Orchestrate, Vision) in
Settings → Role Slots. The sidebar slot-status panel reflects those assignments directly;
enabled provider inventory alone does not configure routing. API keys are stored in
`~/.merlin/api-keys.json` during Debug/dev-loop builds and in macOS Keychain for
Release builds. The release/pre-push path and CI block tracked local-only key
files such as `api-keys.json`, `.env*`, and `secrets.json`.

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15.4 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

---

## Build & Run

```bash
# Generate the Xcode project
xcodegen generate

# Build and launch (Debug)
xcodebuild -scheme Merlin -configuration Debug \
    SYMROOT="$(pwd)/build" \
    CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED'

open build/Debug/Merlin.app
```

Or open `Merlin.xcodeproj` in Xcode and run from there.

---

## Project layout

```
Merlin/             Main application target (Swift sources)
MerlinTests/        Unit and integration tests
MerlinLiveTests/    Real-provider API tests (run manually)
MerlinE2ETests/     Full agentic loop + UI tests (run manually)
TestHelpers/        Shared test utilities (MockProvider, EngineFactory, …)
TestTargetApp/      Fixture app for GUI automation tests
tasks/             Task-by-task implementation sheets
scripts/            DMG packaging script
```

---

## Configuration

| File | Purpose |
|---|---|
| `~/.merlin/config.toml` | Hooks, memories, reasoning overrides, toolbar actions |
| `~/.merlin/mcp.json` | MCP server definitions |
| `~/.merlin/skills/` | Personal slash-command skills |
| `~/.merlin/agents/` | Custom subagent definitions |
| `~/.merlin/memories/` | Accepted AI-generated memories |
| `~/.merlin/workspace.json` | Open projects and active session (persisted across relaunches) |
| `~/.merlin/layout-workspace.json` | Pane layout (sidebar width, visible panes) |
| `~/Library/Application Support/Merlin/providers.json` | Provider configuration |
| `~/Library/Application Support/Merlin/auth.json` | Auth gate allow/deny patterns |
| `~/Library/Application Support/Merlin/sessions/<project-id>/` | Per-project session history |

---

## Running tests

```bash
# Unit + integration (fast, no network)
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED'

# Live provider tests (requires API keys)
RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived
```

---

## Packaging

```bash
bash scripts/package-dmg.sh <version>
# → dist/Merlin-<version>.dmg
```

Or build a release DMG directly:

```bash
xcodebuild -scheme Merlin -configuration Release \
    -derivedDataPath /tmp/merlin-release \
    -destination 'platform=macOS' build

hdiutil create -volname "Merlin <version>" \
    -srcfolder /tmp/merlin-release/Build/Products/Release/Merlin.app \
    -ov -format UDZO dist/Merlin-$(date +%Y-%m-%d)-v<version>.dmg
```

Requires [`create-dmg`](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`) or falls back to `hdiutil`.

---

## Further reading

- [`FEATURES.md`](FEATURES.md) — complete feature reference
- [`spec.md`](spec.md) — system design and implementation decisions
- [`llm.md`](llm.md) — LLM provider and context design details
- [`skill-standard.md`](skill-standard.md) — skill and plugin authoring guide
- `Merlin/Docs/UserGuide.md` — in-app user guide (Help menu)
- `Merlin/Docs/DeveloperManual.md` — in-app developer reference (Help menu)

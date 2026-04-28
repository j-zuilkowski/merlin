# Merlin

A personal, non-sandboxed agentic development assistant for macOS. Merlin connects to multiple LLM providers — remote and local — and gives an AI agent full access to your file system, shell, Xcode, GUI automation, and external services to work through development tasks autonomously.

Built with Swift and SwiftUI for macOS 14+. Personal use only — not distributed.

---

## What it does

Merlin runs an agentic loop: you describe a task, the model calls tools (read files, run shell commands, build with Xcode, inspect UI, write code), reads the results, and continues until the task is complete. You review staged changes before they land on disk.

See [`FEATURES.md`](FEATURES.md) for a complete capability reference.  
See [`architecture.md`](architecture.md) for implementation details and design decisions.

---

## Providers

Remote: **Anthropic**, **DeepSeek**, **OpenAI**, **Qwen**, **OpenRouter**  
Local: **LM Studio**, **Ollama**, **Jan.ai**, **LocalAI**, **Mistral.rs**, **vLLM**

Switch providers per-session from the toolbar. API keys stored in macOS Keychain.

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
phases/             Phase-by-phase implementation sheets
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
| `~/Library/Application Support/Merlin/providers.json` | Provider configuration |
| `~/Library/Application Support/Merlin/auth.json` | Auth gate allow/deny patterns |

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
bash scripts/package-dmg.sh 4.0
# → dist/Merlin-4.0.dmg
```

Requires [`create-dmg`](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`) or falls back to `hdiutil`.

---

## Further reading

- [`FEATURES.md`](FEATURES.md) — complete feature reference
- [`architecture.md`](architecture.md) — system design and implementation decisions
- [`llm.md`](llm.md) — LLM provider and context design details
- [`skill-standard.md`](skill-standard.md) — skill and plugin authoring guide
- `Merlin/Docs/UserGuide.md` — in-app user guide (Help menu)
- `Merlin/Docs/DeveloperManual.md` — in-app developer reference (Help menu)

# Merlin — Codex Session Instructions

Read this file at the start of every session. These rules apply to all work in this project.

---

## Project

macOS SwiftUI agentic chat app. Non-sandboxed. Connects to multiple LLM providers (remote and local) with a full tool registry (file system, shell, Xcode, GUI automation via AX + ScreenCaptureKit + CGEvent).

- Full design: `architecture.md` and `llm.md`. Do not re-derive — implement exactly as specified.
- Working directory: `~/Documents/localProject/merlin`
- Phase sheets: `phases/`

---

## Non-Negotiable Rules (apply to every session)

- **TDD always.** Tests are written first (phase `NNa`), confirmed failing, then implementation follows (phase `NNb`). Never skip the failing-tests commit.
- **Git commit after every phase.** Each phase ends with an explicit `git add` + `git commit`. No exceptions — do not skip or batch commits across phases.
- **Zero warnings, zero errors.** Every file must compile clean. `SWIFT_STRICT_CONCURRENCY=complete` is on.
- **No third-party Swift packages** in production targets (`Merlin`, `TestTargetApp`). Test targets may not add packages either — all helpers go in `TestHelpers/`.
- **Non-sandboxed.** The app entitlement `com.apple.security.app-sandbox` is `false`. Do not add sandbox-only APIs.
- **OpenAI function calling wire format** for all tool definitions. No translation layer except inside `AnthropicProvider`.

---

## Swift Standards

- Swift 5.10, macOS 14+, SwiftUI + `async`/`await` + actors
- All value types: conform to `Sendable`
- No force-unwraps, no `try!`, no `fatalError` in production code
- `@MainActor` on all `ObservableObject` subclasses and SwiftUI views that mutate state
- Parallel tool calls: use `async let` / `TaskGroup`, not sequential `await`

---

## Phase Sheet Format

Every feature follows this two-phase pattern:

### `phases/phase-NNa-<name>-tests.md` (write first)
```
# Phase NNa — <Feature> Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase (N-1)b complete: <summary of prior state>.

New surface introduced in phase NNb:
  - <TypeName.methodName()> — short description
  - ...

TDD coverage:
  File 1 — <TestFileName>: <what it tests>
  File 2 — <TestFileName>: <what it tests>

---

## Write to: MerlinTests/Unit/<TestFile>.swift
<full file content>

---

## Verify
<xcodebuild command — expected: BUILD FAILED with errors naming the missing symbols>

## Commit
git add <test files>
git commit -m "Phase NNa — <TestNames> (failing)"
```

### `phases/phase-NNb-<name>.md` (write after NNa commit)
```
# Phase NNb — <Feature> Implementation

## Context
<same block as NNa, updated>
Phase NNa complete: failing tests in place.

---

## Write to / Edit: <SourceFile>.swift
<full file content or diff>

---

## Verify
<xcodebuild command — expected: BUILD SUCCEEDED, all NNa tests pass>

## Commit
git add <source files>
git commit -m "Phase NNb — <FeatureName>"
```

---

## Build Verification Commands

Use these exact commands for verification — do not invent variants:

```bash
# Build for testing (unit tests, no network)
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Run unit tests
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Regenerate project after editing project.yml
xcodegen generate
```

---

## Test Target Layout

```
MerlinTests/Unit/          — fast unit tests (no I/O, no network)
MerlinTests/Integration/   — real file system, real Process, mocked LLM
MerlinLiveTests/           — real provider APIs (manual scheme: MerlinTests-Live)
MerlinE2ETests/            — full agentic loop + SwiftUI visual (manual scheme)
TestHelpers/               — MockProvider, NullAuthPresenter, EngineFactory (shared across all test targets)
```

`TestHelpers/` is a source folder, not a separate target. It is included in `MerlinTests`, `MerlinLiveTests`, and `MerlinE2ETests` via `project.yml`.

---

## Git Commit Protocol

Every phase ends with:

```bash
cd ~/Documents/localProject/merlin
git add <specific files — never git add -A>
git commit -m "Phase NNx — <Description>"
```

Commit message format: `Phase NNa — <TestNames> (failing)` or `Phase NNb — <FeatureName>`.

Never skip the commit. Never amend a prior phase commit when adding the next phase — always create a new commit.

---

## Project File Generation

After any change to `project.yml`:

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

Then re-verify with `xcodebuild`.

---

## Phase Numbering

Current phases live in `phases/`. Before starting a new feature, check the highest existing phase number and increment. The `phases/PASTE-LIST.md` tracks what has been handed off. Check it before writing a new phase sheet to avoid duplicates.

---

## Running the App

Builds go to the project-local `build/` folder (not DerivedData). Always launch from:

```bash
open ~/Documents/localProject/merlin/build/Debug/Merlin.app
```

Kill and relaunch after each build:
```bash
pkill -x Merlin 2>/dev/null; sleep 1
open ~/Documents/localProject/merlin/build/Debug/Merlin.app
```

---

## Xcode 26 / SwiftUI 6 Notes

- `@FocusedSceneObject` is **not available** — use `@FocusedObject` in `Commands` structs
- Match with `.focusedObject()` in views (not `.focusedSceneObject()`)
- `CommandMenu` works; `CommandGroup` works

---

## Key Constraints

- **Tool registry is dynamic.** `ToolDefinitions` holds static schemas for built-in tools. `ToolRegistry.shared` is the runtime source — all features query it, not `ToolDefinitions.all` directly. Built-ins register via `ToolRegistry.shared.registerBuiltins()` at launch. MCP tools, web search, and future conditional tools register/unregister at runtime. There is no enforced count — tests assert named tools are present, not a total count.
- `ContextManager` exposes `forceCompaction()` for test use
- `ShellTool` has a `stream()` variant returning `AsyncThrowingStream<ShellOutputLine, Error>`
- `Notification.Name.merlinNewSession` raw value: `"com.merlin.newSession"`
- Auth memory path in tests: use `/tmp/auth-<test-name>.json` — never a shared path
- `@FocusedObject` in `MerlinCommands` — views expose via `.focusedObject()`

---

## AppSettings (v3+)

`AppSettings` is a `@MainActor ObservableObject` singleton and the **single source of truth** for all persisted configuration. Features never read `UserDefaults`, `Keychain`, or `config.toml` directly — they read `AppSettings` properties.

Backing stores:
- `~/.merlin/config.toml` — feature flags, hook definitions, memories config, toolbar actions, reasoning overrides
- Keychain — API keys, connector tokens, search API key
- `UserDefaults` — UI-only state (theme, fonts, window layout)

`AppState` reads from `AppSettings` at init and observes it for changes. `AppState` never writes to a backing store directly. Agent-proposed changes go through `AppSettings.propose(_ change: SettingsProposal) async -> Bool`, which surfaces an approval sheet; approved proposals write through to the backing store.

---

## ~/.merlin/ Directory Layout

```
~/.merlin/
  config.toml          — persisted settings (FSEvents-watched; external edits apply live)
  memories/            — accepted AI-generated memory files
    pending/           — generated memories awaiting user review
  skills/              — personal SKILL.md files
  agents/              — custom subagent TOML definitions (v4)
```

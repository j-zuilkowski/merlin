# Merlin — Claude Session Instructions

Read this file at the start of every session. These rules apply to all work in this project.

---

## Project

macOS SwiftUI agentic chat app. Non-sandboxed. Connects to multiple LLM providers (remote and local) with a full tool registry (file system, shell, Xcode, GUI automation via AX + ScreenCaptureKit + CGEvent).

- Full design: `spec.md` and `llm.md`. Do not re-derive — implement exactly as specified.
- Working directory: `~/Documents/localProject/merlin`
- Task sheets: `tasks/`

---

## Non-Negotiable Rules (apply to every session)

- **TDD always.** Tests are written first (phase `NNa`), confirmed failing, then implementation follows (phase `NNb`). Never skip the failing-tests commit.
- **Git commit after every phase.** Each phase ends with an explicit `git add` + `git commit`. No exceptions — do not skip or batch commits across phases.
- **Zero warnings, zero errors.** Every file must compile clean. `SWIFT_STRICT_CONCURRENCY=complete` is on.
- **No third-party Swift packages** in production targets (`Merlin`, `TestTargetApp`). Test targets may not add packages either — all helpers go in `TestHelpers/`.
- **Non-sandboxed.** The app entitlement `com.apple.security.app-sandbox` is `false`. Do not add sandbox-only APIs.
- **OpenAI function calling wire format** for all tool definitions. No translation layer except inside `AnthropicProvider`.
- **Task files must stay in sync with the code.** Any code change — bug fix, refactor, new feature, or addendum — must also update or create the relevant task file(s) before the git commit:
  - **New feature:** write a failing `NNa` tests phase, commit it, implement in `NNb`, update `REBUILD-GUIDE.md` and `PASTE-LIST.md`.
  - **Change to an existing file:** update the file's primary task doc (the `b` implementation phase) to reflect the new behaviour. If the change is large, create a `c` addendum phase (e.g. `task-17c`) and add a superseded banner to the old `b` phase.
  - **Bug fix with no new surface area:** add a `## Fixes` section to the relevant `b` task doc noting what changed and why.
  - **Never commit code whose task doc still describes the old behaviour.** Task files are the rebuild source of truth — if they are wrong, a future rebuild produces broken code.

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

### `tasks/task-NNa-<name>-tests.md` (write first)
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

### `tasks/task-NNb-<name>.md` (write after NNa commit)
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
<xcodebuild - both MerlinTests and, when test targets in the live scheme changed,
 MerlinTests-Live. Expected: BUILD SUCCEEDED, all NNa tests pass>

## Commit
git add <source files>
git commit -m "Phase NNb — <FeatureName>"
```

---

## Build Verification Commands

Use these exact commands for verification — do not invent variants:

```bash
# Build for testing (unit gate)
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Run unit tests
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Live/E2E compile gate - compiles MerlinLiveTests, MerlinE2ETests, TestTargetApp.
# build-for-testing only COMPILES (no run), so it needs no API keys and no LM Studio.
# Omitting this is how those three targets rotted uncompiled for roughly 160 phases.
xcodebuild -scheme MerlinTests-Live build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Regenerate project after editing project.yml
xcodegen generate
```

> **Both schemes are part of the gate.** Every phase's Verify must keep `MerlinTests`
> *and* `MerlinTests-Live` compiling. `MerlinTests` builds the app + unit tests;
> `MerlinTests-Live` builds the live/E2E targets the unit scheme never touches. A target
> compiled by neither scheme rots silently - `TargetGateScanner` (Project Discipline)
> flags that condition, but compiling the scheme every phase is the real prevention.

### Local E2E test execution (proving suite)

For actually *running* the E2E proving-suite scenarios (`MerlinTests-Live test`,
e.g. `CapabilityScenarioTests/testS1SwiftGUIDebugCycle`), the build must be **signed
with the local `Merlin Dev Signing` identity** — NOT ad-hoc. The four compile/unit-test
commands above force ad-hoc by passing `CODE_SIGN_IDENTITY=""`, `CODE_SIGNING_REQUIRED=NO`,
and `CODE_SIGNING_ALLOWED=NO`. That's correct for those commands — they're compile-only
or pure-Swift unit tests with no TCC surface, and the flags also let CI / `git push` runs
succeed on machines that don't have the dev cert. But for E2E:

- The test host launches `Merlin.app` as a real GUI process whose subprocesses (the
  fixture extractor, the critic's `xcodebuild test`, etc.) traverse `~/Documents` — so
  the app needs a macOS TCC "Full Disk Access" grant.
- macOS TCC keys the grant on the app's **designated requirement** — `identifier
  "com.merlin.app" AND certificate leaf = "Merlin Dev Signing"`. With ad-hoc signing
  the requirement falls back to the binary cdhash, so every rebuild silently invalidates
  the grant.
- `project.yml` already configures `CODE_SIGN_IDENTITY: "Merlin Dev Signing"`. The
  three disable-flags above override it — dropping them lets the project's signing
  config take effect.

```bash
# Local E2E proving-suite invocation — signed, used for live test runs
xcodebuild -scheme MerlinTests-Live test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    -only-testing:MerlinE2ETests/CapabilityScenarioTests/<scenario> 2>&1 \
    | grep -E 'Test Case|TEST (EXECUTE )?(SUCCEEDED|FAILED)|passed \(|failed \(|skipped \(' | head -40
```

**First-time setup:** grant `Full Disk Access` to `/private/tmp/merlin-derived/Build/Products/Debug/Merlin.app`
in `System Settings → Privacy & Security → Full Disk Access`. Once granted to the
signed identity, the grant persists across rebuilds. Re-grant only if the
`Merlin Dev Signing` cert itself is regenerated.

**Do NOT use signing for CI / `git push` / compile gates.** The dev cert is local-only;
CI machines don't have it. Keep `CODE_SIGN_IDENTITY=""`, `CODE_SIGNING_REQUIRED=NO`,
`CODE_SIGNING_ALLOWED=NO` on the four commands above so they remain CI-portable.

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

## Versioning

**Single source of truth: `project.yml`** — never hardcode version strings anywhere else.

Full versioning policy (increment rules, release steps, tag conventions) is defined in
`spec.md` → **Versioning Policy** section. Follow that document exactly.

After every `git push --tags`, immediately create a GitHub release:
```bash
gh release create vX.Y.Z \
    --repo j-zuilkowski/merlin \
    --title "vX.Y.Z — <Short description>" \
    --notes "<Release notes>" \
    --latest
```
Tags alone do not update the "Latest" release on GitHub — the `gh release create` step is mandatory.

**Current version: 2.2.5** (build 24, tag v2.2.5)

---

## Project File Generation

After any change to `project.yml`:

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

Then re-verify with `xcodebuild`.

---

## Git State Checks

At the start of any session, check for in-progress git operations before doing any work:

```bash
git status   # look for "revert in progress", "rebase in progress", "merge in progress"
git log --oneline -5
git tag --list | sort -V | tail -5
```

If an in-progress operation exists, surface it to the user and ask whether to abort or continue before proceeding. Never commit or tag over an unresolved git state.

---

## Phase Numbering

Current phases live in `tasks/`. Before starting a new feature, check the highest existing phase number and increment. The `tasks/PASTE-LIST.md` tracks what has been handed off. Check it before writing a new task sheet to avoid duplicates.

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

---

## Canonical Defaults

Source-of-truth values that user-facing docs (`README.md`, `FEATURES.md`, `Requirements.md`,
`Merlin/Docs/UserGuide.md`, `Merlin/Docs/DeveloperManual.md`) must match. When changing any
of these, update **this table first**, then propagate to the docs in the same commit. The
runtime literal in source is authoritative — if a doc disagrees, the doc is wrong.

| Setting | Default | Source of truth | Notes |
|---|---|---|---|
| `loraMinSamples` | `1000` | `AppSettings.swift:73` | Min OutcomeRecords before `LoRACoordinator.considerTraining` fires |
| `LoRACoordinator` minScore | `0.8` | `LoRACoordinator.swift:38` | Critic score threshold for inclusion in the training set |
| `loraEnabled` / `loraAutoTrain` / `loraAutoLoad` | `false` / `false` / `false` | `AppSettings.swift:70-72` | Master + auto-train + auto-load all opt-in |
| `ragChunkLimit` | `3` | `AppSettings.swift:55` | Top-K RAG chunks per turn |
| `ragRerank` | `false` | `AppSettings.swift:53` | xcalibre rerank pass (off by default — RTX 2070 friendly) |
| `ragFreshnessThresholdDays` | `90` | `AppSettings.swift:60` | Chunks older than this trip the `isStale` flag on `GroundingReport` |
| `ragMinGroundingScore` | `0.30` | `AppSettings.swift:62` | Cosine threshold below which `isWellGrounded == false` |
| `agentCircuitBreakerThreshold` | `3` | `AppSettings.swift:64` | Consecutive critic failures before the breaker fires |
| `agentCircuitBreakerMode` | `"halt"` | `AppSettings.swift:66` | `halt` or `warn` |
| `preRunCompactionThreshold` | `6_000` | `ContextManager.swift:83` | Tokens at run start that trigger pre-run compaction |
| `midLoopCompactionThreshold` | `20_000` | `ContextManager.swift:88` | Mid-loop trigger; `var` so tests can lower it |
| `compactionThreshold` (emergency) | `800_000` | `ContextManager.swift:20` | Hard overflow ceiling |
| `compactionKeepRecentTurns` | `20` | `ContextManager.swift:21` | Sentinel-truncate floor when no tool-exchange groups exist |
| `skillBudgetTokens` (total) | `25_000` | `ContextManager.swift:22` | Working-set cap for skill injection |
| `skillBudgetPerSkill` | `5_000` | `ContextManager.swift:23` | Per-skill cap |
| `maxCeilingContinuations` | `10` | `AgenticEngine.swift:225` | Loop-ceiling continuation cap per turn |
| `nearCeilingThreshold` | `8` | `AgenticEngine.swift:237` | Remaining-steps count that fires the near-ceiling warning |

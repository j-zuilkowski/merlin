# Merlin — Codex Handoff Context

## What This Is
macOS SwiftUI non-sandboxed agentic chat app. Connects to multiple LLM providers (OpenAI-compatible, Anthropic, local via LM Studio/Ollama). Full tool registry: file system, shell, Xcode, GUI automation via AX + ScreenCaptureKit + CGEvent. MCP bridge for dynamic tool and domain extension.

## Full Design
See `../architecture.md` and `../llm.md` for all decisions. Do not re-derive — implement exactly as specified.

## Rules (apply to every phase)
- Swift 5.10, macOS 14+, SwiftUI + Swift Concurrency (async/await, actors)
- `SWIFT_STRICT_CONCURRENCY=complete` — zero warnings, zero errors required
- No third-party packages (production targets; test targets use TestHelpers/ source folder only)
- Non-sandboxed app — `com.apple.security.app-sandbox = false`
- OpenAI function calling wire format for all tool definitions; Anthropic wire format handled inside `AnthropicProvider` only
- TDD: tests in MerlinTests/ pass before phase is complete
- Git commit after every phase — never batch across phases

## Project Layout
```
Merlin.xcodeproj
├── Merlin/
│   ├── App/                   — entry point, ToolRegistration, AgentRegistration
│   ├── Agents/                — AgentDefinition, AgentRegistry, SubagentEngine, WorkerSubagentEngine
│   ├── Auth/                  — PatternMatcher, AuthMemory, AuthGate
│   ├── Automations/           — ThreadAutomation, HookEngine
│   ├── Config/                — TOMLDecoder, AppSettings, config.toml loading
│   ├── Connectors/            — ConnectorCredentials, GitHubConnector
│   ├── Engine/                — AgenticEngine, ContextManager, ToolRouter, ThinkingModeDetector
│   ├── Hooks/                 — HookDefinition, HookEngine
│   ├── Keychain/              — KeychainManager
│   ├── MCP/                   — MCPBridge, MCPServerConfig, MCPDomainAdapter (V5)
│   ├── Memories/              — MemoryEngine, MemoryStore
│   ├── Notifications/         — NotificationsGuard
│   ├── Providers/             — ProviderRegistry, OpenAICompatibleProvider, AnthropicProvider, LMStudioProvider
│   ├── RAG/                   — XcalibreClient, RAGTools
│   ├── Scheduler/             — SchedulerEngine, ScheduledTask
│   ├── Sessions/              — SessionManager, LiveSession
│   ├── Skills/                — SkillsRegistry, Skill, SkillFrontmatter
│   ├── Toolbar/               — ToolbarActions
│   ├── Tools/                 — FileSystemTool, ShellTool, XcodeTools, AXInspectorTool, ScreenCaptureTool, CGEventTool, VisionQueryTool, WebSearchTool
│   ├── UI/                    — DiffEngine, StagingBuffer, WorktreeManager
│   ├── Views/                 — ChatView, WorkspaceLayout, DiffPane, SettingsWindow, etc.
│   ├── Voice/                 — VoiceDictation
│   └── Windows/               — FloatingWindow, ProjectPicker
├── MerlinTests/               — unit + integration (no network); TestHelpers/ is a source folder here
├── MerlinLiveTests/           — real provider APIs (manual scheme: MerlinTests-Live)
├── MerlinE2ETests/            — full agentic loop + visual (manual scheme)
└── TestTargetApp/             — fixture SwiftUI app for GUI automation tests
```

## Version History (shipped)
- **V1** — Core engine: DeepSeek + LM Studio, tool registry, auth, sessions, basic chat UI
- **V2** — Multi-project workspace: SessionManager, StagingBuffer, DiffPane, CLAUDE.md, context injection, skills, MCP, scheduler, PR monitor, connectors
- **V3** — Config + settings: TOMLDecoder, AppSettings, config.toml, MemoryEngine, HookEngine, ThreadAutomations, WebSearch, reasoning effort, toolbar, floating window
- **V4** — Subagent system: AgentDefinition, AgentRegistry, SubagentEngine, WorktreeManager, WorkerSubagentEngine, subagent sidebar UI (phases 54–59); plus V3 settings panels, workspace layout, skill compaction, vision attachments, memory generation/injection (phases 60–98)

## Current Status
Phase 98 complete. V4 fully shipped. V5 (Supervisor-Worker Multi-LLM + Domain Plugin System) in design — architecture complete in `../architecture.md`, no phase files written yet. Phase files to be written starting at phase 99.

## Key Architecture Decisions (V3+)
- **AppSettings**: `@MainActor ObservableObject` singleton. Single source of truth for all persisted config. Backing stores: `~/.merlin/config.toml` (feature flags, hooks, memories, toolbar, reasoning), Keychain (API keys), UserDefaults (UI-only). Features never read backing stores directly — they read `AppSettings`.
- **ToolRegistry**: Runtime source of available tools (`ToolRegistry.shared`). `ToolDefinitions` holds static schemas for built-ins. `ToolRegistry.shared.registerBuiltins()` called at launch. MCP tools, web search, domain tools register/unregister at runtime. Tests assert named tools are present — not a total count.
- **ProviderRegistry**: Runtime registry of all providers. `OpenAICompatibleProvider` handles any OpenAI-format API. `AnthropicProvider` translates to Anthropic wire format internally. Providers identified by string ID — no hardcoded provider enum.
- **AgenticEngine**: Stateless actor. Receives `provider`, `tools`, `contextManager` at call time — no stored provider references. Route to execute/reason/orchestrate slots (V5) is determined at call time from `AppSettings`.

## Key Constraints
- All value types: conform to `Sendable`
- `ShellTool` has `stream()` variant → `AsyncThrowingStream<ShellOutputLine, Error>`
- `ContextManager` exposes `forceCompaction()` for test use
- `TestHelpers/` is a source folder included in all three test targets (not a separate Swift package target)
- Tool handlers registered in `Merlin/App/ToolRegistration.swift`, agents in `Merlin/App/AgentRegistration.swift`, both called from `AppState.init`
- `Notification.Name.merlinNewSession` raw value: `"com.merlin.newSession"`
- Auth memory path in tests: `/tmp/auth-<test-name>.json` — never a shared path
- `@FocusedObject` in `MerlinCommands` — views expose via `.focusedObject()` (`@FocusedSceneObject` not available)

## Build Verification Commands
```bash
# Build for testing
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

## Codex Invocation
```bash
codex --model gpt-5.4-mini -q "$(cat phases/phase-NN.md)" --approval-mode auto
```

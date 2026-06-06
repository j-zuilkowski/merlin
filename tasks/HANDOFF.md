# Merlin — Codex Handoff Context

## What This Is
macOS SwiftUI non-sandboxed agentic chat app. Connects to multiple LLM providers (OpenAI-compatible, Anthropic, local via LM Studio/Ollama). Full tool registry: file system, shell, Xcode, GUI automation via AX + ScreenCaptureKit + CGEvent. MCP bridge for dynamic tool and domain extension.

## Full Design
See `../spec.md` and `../llm.md` for all decisions. Do not re-derive — implement exactly as specified.

## Rules (apply to every task)
- Swift 5.10, macOS 14+, SwiftUI + Swift Concurrency (async/await, actors)
- `SWIFT_STRICT_CONCURRENCY=complete` — zero warnings, zero errors required
- No third-party packages (production targets; test targets use TestHelpers/ source folder only)
- Non-sandboxed app — `com.apple.security.app-sandbox = false`
- OpenAI function calling wire format for all tool definitions; Anthropic wire format handled inside `AnthropicProvider` only
- TDD: tests in MerlinTests/ pass before task is complete
- Git commit after every task — never batch across  tasks

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
- **V2** — Multi-project workspace: SessionManager, StagingBuffer, DiffPane, constitution.md, context injection, skills, MCP, scheduler, PR monitor, connectors
- **V3** — Config + settings: TOMLDecoder, AppSettings, config.toml, MemoryEngine, HookEngine, ThreadAutomations, WebSearch, reasoning effort, toolbar, floating window
- **V4** — Subagent system: AgentDefinition, AgentRegistry, SubagentEngine, WorktreeManager, WorkerSubagentEngine, subagent sidebar UI ( tasks 54–59); plus V3 settings panels, workspace layout, skill compaction, vision attachments, memory generation/injection ( tasks 60–98)

## Current Status
Current active line: electronics plugin hardening for evidence-gated KiCad/SPICE
workflows. Latest completed task is Task 467.

Recent commits on `codex/stabilize-merlin-e2e`:

- Task 467 — gate schematic realism before workflow verification
- Task 466 — wire full workflow SPICE evidence gates
- `97491b9` — Task 465: gate SPICE models and repair bounds
- `594fe86` — Task 464: require explicit SPICE scenarios
- `094a06c` — Task 463: gate SPICE measurements by envelope
- `69b7c42` — Task 462: record AmpDemo PCB DRC slice
- `6731b7a` — Task 461: gate ERC schematic warnings
- `3b10c7b` — Tasks 439-444: mark repair actions complete
- `cfdd1ec` — Task 460: harden live catalog cache gating
- `1189367` — Task 459b: datasheet cache settings
- `dc6e1f4` — Task 458b: AmpDemo PCB layout evidence gates

The repo was clean after Task 466 was committed. Task 467 completed the
schematic realism gate and focused schematic/harness tests below.

## Current Electronics Plugin State

The electronics plugin is no longer allowed to advance major workflow gates from
plain narrative claims or placeholder artifacts. Recent hardening includes:

- Read-only file inspection remains allowed in electronics/KiCad sessions while
  shell/write/subagent/UI escape paths stay gated.
- Text-encoded local-model tool calls are parsed and executed only when the tool
  was actually offered.
- Reason-slot execution has been tightened: reason is advisory and should not
  directly execute turns.
- Provider discovery is reduced/cached; startup probes active and configured
  slot providers instead of repeatedly discovering every provider.
- Tool discovery is cached and rerun only when a listed tool location is missing
  or not found.
- Electronics plugin settings/providers are plugin-scoped. Digi-Key, Mouser,
  onsemi, TrustedParts scrape/feed, datasheet cache location, and related
  settings must not appear when the electronics plugin is absent.
- Datasheet PDFs are cached locally and should be checked before download.
  Existing cached PDFs should only be replaced when the upstream file changes.
- Component selection requires structured electrical intent and provider/catalog
  evidence, not symbol names alone.
- Footprint assignment, schematic synthesis, PCB placement, ERC, DRC, SPICE,
  BOM/vendor, and fabrication paths have focused evidence gates.
- Schematic verification now requires current KiCad schematic format,
  `merlin-electronics` generator provenance, emitted KiCad symbols for Circuit
  IR components, matching selected symbols/footprints/source/pins, emitted
  connectivity labels, and no metadata-only/composite block caricatures.
- ERC warnings and DRC violations block progress until parsed repair evidence
  is generated and rerun.
- SPICE now requires:
  - explicit `SPICESimulationScenario` JSON;
  - a real circuit deck path;
  - declared analyses;
  - declared required model references;
  - declared pass/fail measurement envelopes;
  - local SPICE model-record evidence for every required model;
  - artifact-backed full workflow evidence carrying model-record and circuit
    deck provenance;
  - a scenario deck with declared analyses and `.meas` entries for required
    measurement envelopes, not a generic smoke deck;
  - measurement-envelope pass before completion;
  - bounded repair parameters before repair patches are proposed.

Task 467 focused test command passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests \
  -only-testing:MerlinTests/KiCadSchematicParserTests \
  -only-testing:MerlinTests/AmpLowVoltageFixtureTests \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests
```

Result: `TEST SUCCEEDED`, 31 tests, 0 failures.

Task 466 focused test command passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests \
  -only-testing:MerlinTests/SPICEOptimizationTests \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationRejectsProjectOnlyGenericDeckRequest \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationBlocksMissingEnvelopesAndModelRefs \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationBlocksMissingOrUnusableModelEvidence \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationProducesExplicitRunnableDeckArtifact \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOutOfEnvelopeMeasurementsAndKeepsLog
```

Result: `TEST SUCCEEDED`, 22 tests, 0 failures.

Task 465 focused test command passed:

```bash
touch /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-spice-slice
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/SPICEOptimizationTests/testSPICEScenarioRequiresCircuitPathAnalysesAndMeasurementEnvelopes \
  -only-testing:MerlinTests/SPICEOptimizationTests/testNgspiceMeasurementParserReadsScalarMeasurements \
  -only-testing:MerlinTests/SPICEOptimizationTests/testModelResolverBlocksRequiredUnapprovedGenericSubstitute \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationRejectsProjectOnlyGenericDeckRequest \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationBlocksMissingEnvelopesAndModelRefs \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationBlocksMissingOrUnusableModelEvidence \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEScenarioGenerationProducesExplicitRunnableDeckArtifact \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testSPICEGateBlocksOutOfEnvelopeMeasurementsAndKeepsLog \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testSPICERepairActionPlansMeasurementRepairAndBlocksUnsupportedLog \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testAmpDemoSPICESliceRunsExplicit25WOutputStageScenario
rm -f /Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/run-spice-slice
```

Result: `TEST SUCCEEDED`, 10 tests, 0 failures.

Latest focused AmpDemo SPICE evidence:

- Source deck: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/BD078EDD-477A-40D4-8867-9AA5B10F8DD6/amp_low_voltage_audio_output_stage.cir`
- Generated deck: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/BD078EDD-477A-40D4-8867-9AA5B10F8DD6/amp_low_voltage_audio-amp-output-power-scenario.cir`
- Scenario JSON: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/BD078EDD-477A-40D4-8867-9AA5B10F8DD6/amp_low_voltage_audio_spice_scenario.json`
- Model records: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/spice-slice/BD078EDD-477A-40D4-8867-9AA5B10F8DD6/amp_low_voltage_audio_spice_models.json`
- ngspice log: `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/6ACE10FE-AEB4-4576-9877-ACC0D6D1857B-spice.log`
- `output_power_w = 26.9563` against required envelope `24.0...28.0 W`

Important limitation: this SPICE evidence is a representative low-voltage
Class-A output-stage gate only. It does not prove the full amplifier, mains
board, thermal design, complete schematic, PCB, BOM, ERC, DRC, CAM, or release
package is complete.

## Remaining Electronics Work

Do not run the full AmpDemo demo until the next integration gates are in place.
The immediate remaining work is:

1. Implement generic multi-board design decomposition so Merlin derives board
   boundaries, safety domains, isolation barriers, inter-board connectors, and
   verification plans from any electronics `DesignIntent`. AmpDemo is only a
   regression fixture: the expected behavior is that Merlin independently
   separates mains/transformer and low-voltage amplifier domains when the
   request implies that split, not that Codex manually splits the sample design.
2. Continue generic topology/materialization from structured `DesignIntent`
   instead of AmpDemo-specific shortcuts.
3. Run full ERC repair loops: parse failures, apply bounded repairs, rerun until
   pass or explicitly blocked.
4. Run full DRC/layout repair loops: placement, routing, DRC, repair, rerun
   until pass or explicitly blocked.
5. Finish vendor/BOM flow with Digi-Key, Mouser, onsemi fallback, cached
   datasheets, stock/price evidence, and real BOM artifact.
6. Finish fabrication flow: Gerbers, Excellon drills, CAM checks,
   pick-and-place, drawings, and consolidated verification report.
7. Verify GUI job state consistency: slot status, electronics job list, and live
   leaderboard must agree about running/blocked/complete jobs.
8. Only after the above, clean Merlin and AmpDemo and run a full GUI AmpDemo
   pass with app-only screenshots captured while the app is working.

The biggest open risk is still schematic/PCB realism. SPICE gating is now much
stronger, but it does not by itself make Merlin capable of arbitrary reliable
electronics synthesis.

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
codex --model gpt-5.4-mini -q "$(cat tasks/task-NN.md)" --approval-mode auto
```

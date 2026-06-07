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
workflows. Latest completed task is Task 479.

Recent commits on `codex/stabilize-merlin-e2e`:

- Task 479 — surface component revision questions in workflow and GUI state
- Task 478 — generic component-selection revision workflow
- Task 477 — record AmpDemo GUI component-selection gate
- Task 476 — mutate DRC routing repairs with native segment/via edits
- Task 475 — synchronize electronics GUI job state projections
- Task 474 — gate fabrication output evidence
- Task 473 — gate vendor BOM evidence
- Task 472 — mutate PCB DRC repair plans
- Task 471 — gate DRC layout rerun evidence
- Task 470 — require explicit ERC rerun evidence
- Task 469 — generic topology and materialization realism
- Task 468 — generic multi-board decomposition gates
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

Task 476 replaced the DRC routing repair marker with native KiCad route object
mutation. Routing repair application now parses the target net and pad anchors
from the board, inserts `(segment ...)` and `(via ...)` objects when at least two
pad anchors exist, records `routing_segment` and `routing_via` changed objects,
and blocks unchanged with `regenerate_drc_repair_plan` when pad-level routing
geometry is missing.

Task 477 ran a fresh app-only AmpDemo GUI workflow attempt through
`/Applications/Merlin.app` opened with `--open-project
/Users/jonzuilkowski/Documents/localProject/AmpDemo --active-domain
electronics`. The run used Merlin's live-session `~/.merlin/inject.txt` path to
submit the user prompt through the active GUI session, after direct keyboard
focus and exploratory XCUITest automation were not reliable in this desktop
environment. Merlin generated DesignIntent, approved DesignIntent, Circuit IR,
and component matrix artifacts, then stopped truthfully at
`COMPONENT_SELECTION_BLOCKED` / `BLOCKED_INPUT_QUALITY`. The component matrix
contains 21 components and all 21 remain `requires_vendor_resolution`; no
footprint, schematic, PCB, ERC, DRC, SPICE, BOM, or fabrication step advanced
from unresolved component decisions.

Task 477 evidence paths:

- Screenshots:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/01_clean_session_app_only.png`
  through
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/04_component_selection_blocked_app_only.png`
- Approved DesignIntent:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/53FEDAD1-FEDF-4A53-9F2A-D721428B9614-design_intent.json`
- Circuit IR:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/19397343-C00B-46CD-90C0-C93DA986AC6D-circuit_ir.json`
- Blocked component matrix:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/03ECE826-D739-446D-A057-FEDDA41B16FB-component_matrix.json`

Task 478 added a generic component-selection revision path. The electronics
plugin now exposes `kicad_revise_component_selection`, which accepts a blocked
component matrix plus design intent, optional Circuit IR, and catalog evidence.
It reruns the evidence-backed selection machinery for unresolved components,
completes only when the revised matrix has concrete manufacturer parts, and
otherwise emits `COMPONENT_SELECTION_REVISION_BLOCKED` with targeted missing
evidence questions. The focused GUI continuation path now treats
`revise_component_selection` from a blocked component-selection result as a
handoff to `kicad_revise_component_selection`, not as permission to assign
footprints or repeat narrative initial selection.

Task 478 focused test evidence:

```bash
rm -rf /tmp/merlin-derived-task478 && xcodebuild build-for-testing -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task478
```

Result: `TEST BUILD SUCCEEDED`.

Before the direct XCTest run, the rebuilt `Merlin.debug.dylib` and
`MerlinElectronicsPlugin.dylib` were copied into the test bundle's
`Contents/Frameworks` directory because the Xcode test launcher had previously
stalled before launching the test host in this environment.

```bash
xcrun xctest -XCTest 'MerlinTests.EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionResolvesBlockedMatrixWithCatalogEvidence,MerlinTests.EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBlocksWithSpecificQuestionsWhenEvidenceIsStillMissing,MerlinTests.LoopContinuationTests/testBlockedComponentMatrixSchedulesRevisionInsteadOfAssigningFootprints' /tmp/merlin-derived-task478/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest
```

Result: selected tests passed, 3 tests, 0 failures.

```bash
xcrun xctest -XCTest 'MerlinTests.ElectronicsRealRegistrationTests/testAllRequiredElectronicsCapabilitiesUsePluginNamespace' /tmp/merlin-derived-task478/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest
```

Result: 1 test, 0 failures.

`git diff --check` passed. The full AmpDemo GUI demo was not run.

Task 479 surfaced blocked component-selection revision questions through the
full focused workflow and electronics GUI/job state. `kicad_revise_component_selection`
blocked results now stop with an explicit recovery summary containing
`COMPONENT_SELECTION_REVISION_BLOCKED`, resolver question IDs/prompts, the
original blocked matrix path, and the revised matrix path. Electronics job
diagnostics/display rows now carry `blockedQuestions`, `evidencePaths`, and
`requiredEvidenceCategories`; the Electronics Jobs panel includes those entries
in Evidence Gates so resolver blockers are visible instead of being hidden in a
generic diagnostic.

Task 479 fail-first evidence:

```bash
rm -rf /tmp/merlin-derived-task479 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task479 \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testBlockedComponentSelectionRevisionQuestionsProjectIntoDisplayState \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionBlockedQuestionsStopWithRecoverableEvidence
```

Red result: `TEST FAILED` at compile time because
`ElectronicsJobDisplayState` had no `blockedQuestions`, `evidencePaths`, or
`requiredEvidenceCategories`.

Task 479 green evidence:

```bash
xcodebuild build-for-testing -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task479
```

Result: `TEST BUILD SUCCEEDED`.

```bash
xcrun xctest -XCTest 'MerlinTests.ElectronicsJobStoreTests,MerlinTests.LoopContinuationTests/testBlockedComponentMatrixSchedulesRevisionInsteadOfAssigningFootprints,MerlinTests.LoopContinuationTests/testComponentSelectionRevisionBlockedQuestionsStopWithRecoverableEvidence' /tmp/merlin-derived-task479/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest
```

Result: selected tests passed, 9 tests, 0 failures.

`git diff --check` passed. The full AmpDemo GUI demo was not run.

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
- Blocked component-selection matrices now have a generic revision route:
  `kicad_revise_component_selection` reuses catalog evidence to resolve
  concrete parts or emits structured missing-evidence questions. Full workflow
  continuation must route `revise_component_selection` through that tool before
  footprints, schematic, PCB, SPICE, BOM, or fabrication can advance.
- Blocked component-selection revision questions are now surfaced in focused
  workflow stops and electronics GUI/job state. Resolver blockers must preserve
  question prompts, required evidence categories, original blocked matrix path,
  and revised matrix path so the next turn can recover from structured evidence
  instead of manual sample-project decisions.
- Footprint assignment, schematic synthesis, PCB placement, ERC, DRC, SPICE,
  BOM/vendor, and fabrication paths have focused evidence gates.
- Schematic verification now requires current KiCad schematic format,
  `merlin-electronics` generator provenance, emitted KiCad symbols for Circuit
  IR components, matching selected symbols/footprints/source/pins, emitted
  connectivity labels, and no metadata-only/composite block caricatures.
- DesignIntent board evidence now carries per-board verification plans and
  inter-board connector records. Mixed hazardous mains/primary plus isolated
  low-voltage requests must decompose into separate board domains before
  schematic, PCB, SPICE, BOM, or fabrication workflow advancement.
- Circuit IR `board_id` must reference a declared DesignIntent board before
  KiCad mutation can proceed.
- Circuit IR generation can now target a declared DesignIntent board and scopes
  components/nets to that board when component intent evidence includes
  `board_id`. Schematic symbols and generated PCB footprints carry explicit
  `BoardID` and `SafetyDomain` properties.
- ERC warnings and DRC violations block progress until parsed repair evidence
  is generated and rerun. ERC repair loops now require an explicit ERC report
  or rerun report; applying an ERC repair patch records an unverified
  `patch_applied_requires_rerun` artifact and requires `kicad_run_erc` before
  schematic verification can advance.
- DRC repair loops now require an explicit DRC report or rerun report. DRC
  repair patch application maps supported generic repair classes to concrete
  PCB/layout mutations: footprint placement offsets, clearance and trace-width
  rule changes, and KiCad-native routing segment/via insertion when the board
  carries target-net pad anchors. Routing-only repair plans without pad-level
  route geometry now block without mutating the board instead of adding a
  narrative marker. Successful mutation writes the board, emits
  `layout_mutation_evidence` with before/after SHA-256 hashes, patch IDs, and
  changed objects, records `patch_applied_requires_drc_rerun`, and requires
  `kicad_run_drc` before PCB verification can advance. PCB verification still
  blocks repaired DRC paths when required layout mutation evidence is missing.
- Vendor/BOM workflow now requires explicit normalized BOM, vendor availability,
  cached datasheet evidence, and vendor order package paths before fabrication
  can reach `FAB_READY`. Vendor availability records must include stock and
  positive unit price evidence. `kicad_prepare_vendor_order` validates BOM,
  stock/price, and cached datasheet evidence before emitting a
  `vendor_order_package` artifact; a BOM path alone is blocked.
- Fabrication output workflow now requires real output artifacts, not declared
  paths alone. The generic `jlcPCBTwoLayer` profile requires Gerber, Excellon
  drill, pick-and-place, assembly drawing, and fabrication/CAM report evidence.
  `FabricationEvidenceValidator` checks that output files/directories exist and
  are non-empty and that CAM report JSON declares `pass` or `ok`. `kicad_export_fab`
  now exports Gerbers, drills, position/PnP data, and assembly drawings, blocks
  if those outputs are missing, and emits `cam_report`, `fabrication_evidence`,
  and consolidated `verification_report` artifacts.
- Electronics GUI job state now uses one `ElectronicsJobDisplayState`
  projection for live leaderboard rows and running/blocked/fab-ready/complete
  job groups. Blocked, fab-ready, and complete jobs no longer collapse into a
  generic non-running/completed bucket. The separate provider `SlotStatusPanel`
  was not changed.
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

Task 476 focused test commands passed:

Fail-first command before implementation:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationBlocksRoutingWithoutPadGeometry
```

Result before implementation: `TEST FAILED`, 2 tests, 12 assertion failures.
The board still contained `Merlin reroute required`, no `(segment ...)` or
`(via ...)` objects were emitted, changed objects contained `routing_marker`, and
the no-geometry routing-only plan incorrectly returned `ok`.

Green command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationBlocksRoutingWithoutPadGeometry
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

Broader focused command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests
```

Result: `TEST SUCCEEDED`, 11 tests, 0 failures.

Note: the full AmpDemo GUI demo was not run.

Task 475 focused test commands passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testGUIProjectionsUseSingleDisplayStateForFabReadyJobs \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testGUIProjectionsSeparateRunningBlockedFabReadyAndCompleteStates
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsJobStoreTests \
  -only-testing:MerlinTests/ElectronicsJobPanelLiveWorkflowTests
```

Result: `TEST SUCCEEDED`, 7 tests, 0 failures.

Note: the full AmpDemo GUI demo was not run. Task 475 covered model/projection
consistency for the electronics GUI, not app screenshot execution.

Task 474 focused test commands passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabricationEvidenceRequiresGerberDrillPlacementAndReport \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabricationEvidenceRequiresExistingOutputsAndPassingCAMReport \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingFabricationDrawingAndVerificationReportBlockFabReady \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadHandlersInvokeExecutableAndProduceEvidenceArtifacts
```

Result: `TEST SUCCEEDED`, 4 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testCleanVerifierArtifactsReachFabReadyWithoutReleaseApproval \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingFabricationDrawingAndVerificationReportBlockFabReady \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testFailedDRCRunKeepsReportArtifactForHarnessRepairEvidence \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests/testKiCadHandlersInvokeExecutableAndProduceEvidenceArtifacts
```

Result: `TEST SUCCEEDED`, 12 tests, 0 failures.

Note: the full AmpDemo GUI demo was not run. A broader artifact-path runtime
test with the stale mixed-domain fixture still blocks upstream on design-intent
and schematic verification gates; Task 474 did not weaken those gates.

Task 473 focused test commands passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests/testFabReadyRequiresArtifactBackedBOMVendorDatasheetAndOrderEvidence \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingDatasheetCacheEvidenceBlocksBOMVendorFabrication \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresArtifactBackedBOMVendorEvidenceBeforeFabReady \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationRequiresRealBOMStockPriceAndDatasheetEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationEmitsPackageFromValidatedBOMStockPriceAndCachedDatasheets
```

Result: `TEST SUCCEEDED`, 5 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FabBOMReleaseTests \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testCleanVerifierArtifactsReachFabReadyWithoutReleaseApproval \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testInvalidBOMVendorEvidenceBlocksFabrication \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testMissingDatasheetCacheEvidenceBlocksBOMVendorFabrication \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresArtifactBackedBOMVendorEvidenceBeforeFabReady \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowCarriesSeparatedBoardDomainEvidenceThroughHandoff \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationRequiresRealBOMStockPriceAndDatasheetEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testVendorOrderPreparationEmitsPackageFromValidatedBOMStockPriceAndCachedDatasheets
```

Result: `TEST SUCCEEDED`, 14 tests, 0 failures.

Task 472 focused test commands passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testRepairPatchApplicationRequiresGateRerunBeforeAdvancement \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowAcceptsCleanDRCRerunAfterConcreteLayoutMutationEvidence
```

Result: `TEST SUCCEEDED`, 3 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairActionPlansSupportedDiagnosticsAndBlocksApprovalRequiredDiagnostics \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testRepairPatchApplicationRequiresGateRerunBeforeAdvancement \
  -only-testing:MerlinTests/PCBDRCFollowOnTests/testPCBVerificationBlocksRepairPlanWithoutLayoutMutationEvidence \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresLayoutMutationEvidenceBeforeDRCRerunCanVerifyPCB \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowAcceptsCleanDRCRerunAfterConcreteLayoutMutationEvidence
```

Result: `TEST SUCCEEDED`, 6 tests, 0 failures.

Task 471 focused test commands passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/PCBDRCFollowOnTests/testDRCRepairLoopRequiresExplicitRerunReport \
  -only-testing:MerlinTests/PCBDRCFollowOnTests/testPCBVerificationBlocksRepairPlanWithoutLayoutMutationEvidence \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresLayoutMutationEvidenceBeforeDRCRerunCanVerifyPCB \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence
```

Result: `TEST SUCCEEDED`, 4 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/PCBDRCFollowOnTests \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairActionPlansSupportedDiagnosticsAndBlocksApprovalRequiredDiagnostics \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testRepairPatchApplicationRequiresGateRerunBeforeAdvancement \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresLayoutMutationEvidenceBeforeDRCRerunCanVerifyPCB \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowCarriesSeparatedBoardDomainEvidenceThroughHandoff \
  -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests/testBlockingDRCViolationBlocksPCBAndHarness
```

Result: `TEST SUCCEEDED`, 16 tests, 0 failures.

Task 470 focused test commands passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ERCRepairLoopTests/testRepairLoopRequiresExplicitERCRerunReport \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowRequiresExplicitERCRerunReportBeforeSchematicVerified \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testERCRepairPatchApplicationRecordsUnverifiedRerunRequirement
```

Result: `TEST SUCCEEDED`, 3 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ERCRepairLoopTests \
  -only-testing:MerlinTests/SchematicVerifiedStatusTests \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testERCRepairActionPlansSupportedDiagnosticsAndPreservesPatchArtifact
```

Result: `TEST SUCCEEDED`, 16 tests, 0 failures.

Task 469 focused test commands passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testCircuitIRGenerationHonorsGenericBoardScopeAndSafetyDomains \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testMaterializersCarryGenericBoardAndSafetyDomainProvenance
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testApprovedClassATopologyGeneratesDiscreteCircuitIR \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testConstraintOnlyPayloadSynthesizesReusableClassATopologyEvidence \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testMaterializedCircuitIREmitsRealKiCadSymbolsAndConnectivity \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testSchematicRealismValidatorPassesMaterializedDiscreteCircuitIR \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testSchematicMaterializerContainsNoProductSpecificEmitterShortcuts
```

Result: `TEST SUCCEEDED`, 5 tests, 0 failures.

Task 468 focused test commands passed:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testGenericMultiboardDecompositionBlocksMergedMainsAndLowVoltageDomains \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testGenericMultiboardDecompositionPassesSeparatedDomainEvidence \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testCircuitIRBoardIDMustReferenceDesignIntentBoard \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowBlocksMergedHighStakesDomainsBeforeSchematicPCBOrFabAdvance \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowCarriesSeparatedBoardDomainEvidenceThroughHandoff
```

Result: `TEST SUCCEEDED`, 5 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testAmpDemoSpecFileBuildsMeaningfulDesignIntent \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testStructuredConstraintsPopulateDesignIntentInsteadOfEmptyDraft \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testConstraintOnlyPayloadSynthesizesReusableClassATopologyEvidence
```

Result: `TEST SUCCEEDED`, 3 tests, 0 failures.

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

Do not manually hand-design AmpDemo. Merlin must learn generic workflow behavior
that applies to arbitrary electronics requests, then AmpDemo can be rerun as an
evidence check.

The immediate remaining work is the next generic resolver-recovery group:

1. Add fail-first tests proving structured answers or provider evidence for
   resolver questions are ingested generically and converted into catalog
   candidate evidence, not AmpDemo-specific manual part choices.
2. Wire the next-turn recovery path so a blocked
   `kicad_revise_component_selection` question set can be answered with
   manufacturer/MPN/package/ratings/datasheet/footprint-pin evidence and rerun
   the resolver against the original/revised matrix paths.
3. Prove that, after all required component evidence is supplied, the workflow
   advances only to a complete component matrix and still refuses footprints if
   any resolver question remains unanswered.
4. Run focused tests only. Do not run the full AmpDemo GUI demo and do not
   hand-design AmpDemo parts.

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

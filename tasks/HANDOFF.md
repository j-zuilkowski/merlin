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
Current active line: electronics plugin finish checklist complete.
Electronics domain status: finished as evidence-gated workflow infrastructure.
The current GUI proof stops at `COMPONENT_SELECTION_REVISION_BLOCKED`; this is
an honest evidence gate and not a `FAB_READY` fabrication claim.
Latest completed task is Task 490.

Recent commits on `codex/stabilize-merlin-e2e`:

- Task 490 — repair release blocker workflow gates
- Task 489 — synchronize Developer Manual with current source tree
- Task 488 — finalize electronics completion contract status
- Task 487 — recover F4 GUI spec evidence path
- Task 486 — cap generated electronics artifact reads in workflow context
- Task 485 — record fresh GUI workflow context blocker
- Task 484 — prove generic realism and artifact chain gates
- Task 483 — add GUI resolver answer entry
- Task 482 — define electronics domain finish checklist
- Task 481 — carry component revision answer handoff state
- Task 480 — recover component revision from structured resolver answers
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

Task 480 wired structured resolver answers into the generic component-selection
revision path. `kicad_revise_component_selection` now accepts
`component_resolution_answers`, `component_resolution_answers_json`, and
`component_resolution_answers_path`. Those answers are converted into ordinary
catalog `ComponentCandidate` evidence with `target_refdes` provenance,
manufacturer/MPN/package/ratings/datasheet/source evidence, and optional
footprint pin-map candidates. The existing catalog validator/ranker remains the
authority: complete answers can advance the matrix to selected parts, while
partial answers keep unanswered components blocked and do not offer footprint
continuation.

Task 480 fail-first evidence:

```bash
rm -rf /tmp/merlin-derived-task480 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task480 \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBuildsCandidateEvidenceFromStructuredAnswers \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionWithPartialStructuredAnswersStillBlocksBeforeFootprints
```

Red result: `TEST FAILED`, 2 tests, 4 failures. Structured resolver answers
were ignored, leaving QOUT1 unresolved and the complete-answer revision blocked.

Task 480 green evidence:

```bash
rm -rf /tmp/merlin-derived-task480 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task480 \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBuildsCandidateEvidenceFromStructuredAnswers \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionWithPartialStructuredAnswersStillBlocksBeforeFootprints
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task480 \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionResolvesBlockedMatrixWithCatalogEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBlocksWithSpecificQuestionsWhenEvidenceIsStillMissing \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBuildsCandidateEvidenceFromStructuredAnswers \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionWithPartialStructuredAnswersStillBlocksBeforeFootprints \
  -only-testing:MerlinTests/LoopContinuationTests/testBlockedComponentMatrixSchedulesRevisionInsteadOfAssigningFootprints \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionBlockedQuestionsStopWithRecoverableEvidence
```

Result: `TEST SUCCEEDED`, 6 tests, 0 failures.

Task 481 wired the focused workflow answer-turn handoff for blocked
component-selection revision. When `kicad_revise_component_selection` blocks
with resolver questions, the engine now preserves DesignIntent path, Circuit IR
path, original blocked component matrix path, revised component matrix path, and
resolver question IDs. A next user/provider answer turn that calls
`kicad_revise_component_selection` with `component_resolution_answers` is
normalized with those paths and IDs. A completed revision matrix satisfies the
generic component-selection workflow requirement and can advance only to the
next legitimate handoff; partial answers remain blocked with the remaining
questions and no footprint continuation.

Task 481 fail-first evidence:

```bash
rm -rf /tmp/merlin-derived-task481 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task481 \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionAnswerTurnCarriesHandoffPathsAndAnswerEvidence \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionPartialAnswerTurnRemainsBlockedWithUnansweredQuestions
```

Red result: `TEST FAILED`, 2 tests, 12 failures. The answer evidence reached the
provider call, but the workflow dropped handoff paths and question IDs, then
scheduled fresh `kicad_select_components` after a complete answer instead of
advancing from the completed revision matrix.

Task 481 green evidence:

```bash
rm -rf /tmp/merlin-derived-task481 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task481 \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionAnswerTurnCarriesHandoffPathsAndAnswerEvidence \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionPartialAnswerTurnRemainsBlockedWithUnansweredQuestions
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task481 \
  -only-testing:MerlinTests/LoopContinuationTests/testBlockedComponentMatrixSchedulesRevisionInsteadOfAssigningFootprints \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionBlockedQuestionsStopWithRecoverableEvidence \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionAnswerTurnCarriesHandoffPathsAndAnswerEvidence \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionPartialAnswerTurnRemainsBlockedWithUnansweredQuestions \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBuildsCandidateEvidenceFromStructuredAnswers \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionWithPartialStructuredAnswersStillBlocksBeforeFootprints
```

Result: `TEST SUCCEEDED`, 6 tests, 0 failures.

`git diff --check` passed. The full AmpDemo GUI demo was not run.

Task 483 added the GUI resolver answer entry path. Blocked
component-selection revision diagnostics now project actionable
`resolverAnswerRequirements` into electronics job display state. The job store
can write a structured continuation message with `component_resolution_answers`,
question IDs, DesignIntent/Circuit IR/component-matrix handoff paths, and live
catalog settings for `kicad_revise_component_selection`. The focused
continuation path treats those GUI resolver-answer messages as verified
electronics evidence, clears stale blocked state for answer turns, and permits
advancement only to the completed component matrix handoff before scheduling
`kicad_assign_footprints`.

Task 483 fail-first evidence:

```bash
rm -rf /tmp/merlin-derived-task483 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task483 \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testBlockedResolverQuestionsProjectActionableAnswerRequirements \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testResolverAnswerSubmissionWritesStructuredContinuationMessage \
  -only-testing:MerlinTests/LoopContinuationTests/testGUIResolverAnswerContinuationAdvancesThroughRevisionHandoff
```

Red result: `TEST FAILED`. The new answer types/display projection were absent
at first; after partial wiring, the resolver-answer continuation was not treated
as artifact-backed GUI evidence and stale blocked continuation state prevented
revision handoff advancement.

Task 483 green evidence:

```bash
rm -rf /tmp/merlin-derived-task483 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task483 \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testBlockedResolverQuestionsProjectActionableAnswerRequirements \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testResolverAnswerSubmissionWritesStructuredContinuationMessage \
  -only-testing:MerlinTests/LoopContinuationTests/testGUIResolverAnswerContinuationAdvancesThroughRevisionHandoff
```

Result: `TEST SUCCEEDED`, 3 tests, 0 failures.

Task 484 closed generic finish criteria F2 and F3. PCB materialization now emits
manufacturer part number, source evidence, pin-pad map, and footprint pin
compatibility in generated board footprints. Focused tests cover two materially
different non-AmpDemo fixtures and assert real KiCad schematic symbols,
connectivity, PCB edge/routing artifacts, board/safety-domain propagation, and
no AmpDemo-specific emitter shortcuts. `ElectronicsArtifactChainGate` now
requires artifact-backed records for each major electronics workflow gate and
requires repair mutation plus rerun evidence for repair/rerun stages; the
end-to-end harness enforces those records when supplied.

Task 484 fail-first evidence:

```bash
xcodegen generate
rm -rf /tmp/merlin-derived-task484-red && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task484-red -only-testing:MerlinTests/ElectronicsFinishCriteriaTests
```

Red result: `TEST FAILED`, build failed because
`ElectronicsArtifactChainRecord` was not implemented.

Task 484 green evidence:

```bash
xcodegen generate
rm -rf /tmp/merlin-derived-task484 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task484 -only-testing:MerlinTests/ElectronicsFinishCriteriaTests
```

Result: `TEST SUCCEEDED`, 4 tests, 0 failures.

```bash
rm -rf /tmp/merlin-derived-task483-484 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task483-484 \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testBlockedResolverQuestionsProjectActionableAnswerRequirements \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testResolverAnswerSubmissionWritesStructuredContinuationMessage \
  -only-testing:MerlinTests/LoopContinuationTests/testGUIResolverAnswerContinuationAdvancesThroughRevisionHandoff \
  -only-testing:MerlinTests/ElectronicsFinishCriteriaTests
```

Result: `TEST SUCCEEDED`, 7 tests, 0 failures.

`git diff --check` passed. The full AmpDemo GUI demo was not run.

Task 485 ran the fresh full GUI workflow evidence pass required by F4. The run
used `/Applications/Merlin.app` opened with `--open-project
/Users/jonzuilkowski/Documents/localProject/AmpDemo --active-domain
electronics`, with `~/.merlin/inject.txt` as the GUI live-session input path.
The app generated draft and approved DesignIntent artifacts and correctly
decomposed the high-voltage/low-voltage request into `mains_power` and
`isolated_secondary` boards. It did not generate Circuit IR, component matrix,
footprints, schematic, PCB, ERC, DRC, SPICE, BOM/vendor, fabrication/CAM,
`FAB_READY`, or completion artifacts.

Task 485 proved an internal GUI/workflow continuation blocker before Circuit
IR. After `kicad_build_intent_model` and `kicad_approve_design_intent`
completed, the continuation path repeatedly reread the 22,726-byte approved
DesignIntent/spec evidence, scheduled the same continuation, exceeded
`qwen3-coder-next-local`'s 16,384-token context, forced compaction, and repeated
without advancing. This is not an acceptable F4 external blocker, so F4 remains
open until generic GUI continuation context handling is fixed and rerun.

Task 486 fixed the generic context-handling side of that blocker. The engine now
keeps full generated electronics artifact `read_file` results available to tool
events/evidence, but stores only a compact context entry for large reads of
`.merlin/electronics-artifacts/*-design_intent.json`, `*-circuit_ir.json`,
`*-component_matrix.json`, and `*-footprint_assignment.json` while the
electronics workflow lock is active. Focused tests also prove that the
post-approval continuation schedules an exact `kicad_generate_circuit_ir`
handoff rather than a broad reread continuation.

Task 487 fixed the remaining fresh-GUI evidence path blockers found during the
F4 rerun. Registered project-scoped requirements reads now recover narrowly
when the model requests a missing absolute `spec.md`, `requirements.md`, or
`requirements.txt` outside the active project but the same artifact exists at
the project root. `kicad_build_intent_model` resolves relative input artifact
paths against the electronics workspace root. Requirements inspection
verification now requires non-empty `read_file` or `search_files` evidence
naming the spec/requirements artifact; `list_directory` output alone no longer
satisfies the first workflow gate.

Task 487 then reran the full GUI workflow through `/Applications/Merlin.app`
opened with `--open-project
/Users/jonzuilkowski/Documents/localProject/AmpDemo --active-domain
electronics`. The live session rejected directory listing as requirements
evidence, read `./spec.md`, generated and approved DesignIntent, generated
Circuit IR, ran component selection, attempted component-selection revision,
and stopped truthfully at `COMPONENT_SELECTION_REVISION_BLOCKED`. It did not
advance to footprint assignment, schematic, PCB, ERC, DRC, SPICE, BOM/vendor,
fabrication/CAM, or `FAB_READY` from unresolved component decisions.

Task 487 evidence paths:

- Screenshots:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/07_clean_session_task487_after_evidence_fixes.png`
  through
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/09_component_revision_blocked_task487.png`
- Session log:
  `/Users/jonzuilkowski/Library/Application Support/Merlin/sessions/_Users_jonzuilkowski_Documents_localProject_AmpDemo/8F316606-315D-41F0-B2F4-719BF1CC1C1D.json`
- DesignIntent artifacts:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/7FAAE25B-810E-4B31-85E0-72797531FEDC-design_intent.json`
  and
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/709D779E-114D-4909-80CD-CA772F62CFC5-design_intent.json`
- Circuit IR:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/CB790BD0-9366-47AE-9980-1F950467894C-circuit_ir.json`
- Blocked and revised component matrices:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/F9548B74-EB64-4144-A971-D414C3B0FD45-component_matrix.json`
  and
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/C16986CC-CD3C-4DC8-ABB2-AB82FF877E50-component_matrix.json`

Task 488 completed F5, the final status/documentation cleanup. The plugin spec
no longer describes full PCB/fabrication workflow as outside the first
milestone or describes AmpDemo as a schematic-only milestone. It now records the
current completion contract: F1-F4 are complete, the electronics domain is
finished as evidence-gated workflow infrastructure, and the current GUI proof
stops at `COMPONENT_SELECTION_REVISION_BLOCKED` until concrete component,
catalog, datasheet, and footprint/pin evidence is supplied. This is not a claim
that AmpDemo reached `FAB_READY`.

Task 489 synchronized `Merlin/Docs/DeveloperManual.md` with the current source
tree and updated stale source comments. The manual now documents the
slot/provider-registry `AgenticEngine` model, current run-loop responsibilities,
current `Merlin/Discipline`, `Merlin/Runtime`, `Merlin/Electronics`,
`Merlin/Plugins`, and `Merlin/CAG` layout entries, current built-in tool names,
and the current electronics `KiCadToolDefinitions` / evidence-gated completion
contract. Code-map cross references were updated for discipline, runtime, and
electronics source files.

Task 489 fail-first evidence:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/DocumentationSweepTests/testDeveloperManualMatchesCurrentEngineToolAndElectronicsSurfaces -derivedDataPath /tmp/merlin-derived-task489-docs
```

Result before implementation: selected documentation sweep failed with 47
failures for missing current surfaces and stale manual surfaces.

Task 489 focused verification:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/DocumentationSweepTests/testDeveloperManualMatchesCurrentEngineToolAndElectronicsSurfaces -derivedDataPath /tmp/merlin-derived-task489-docs
```

Result after implementation: selected test passed, 1 test, 0 failures.

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/DocumentationSweepTests -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests -derivedDataPath /tmp/merlin-derived-task489-docs
```

Result after implementation: selected documentation sweeps passed, 16 tests, 0
failures.

Task 485 evidence paths:

- Screenshots:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/01_clean_session_task485.png`
  through
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/06_context_loop_blocker_task485.png`
- Approved DesignIntent:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/5FACF97B-8360-4B6B-940A-A0F759F4AAF7-design_intent.json`
- Telemetry summary:
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/reports/task485-summary.json`
  and
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/reports/task485-telemetry-interesting.jsonl`

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
- Component-selection revision now ingests structured resolver answers as
  generic catalog candidates. Answers must carry manufacturer, MPN, package,
  ratings, datasheet, and provenance evidence to satisfy the existing catalog
  validator; partial answers keep unanswered components blocked and cannot
  advance to footprints.
- Focused workflow answer turns now preserve blocked component-selection
  revision handoff state. `component_resolution_answers` are carried into the
  next `kicad_revise_component_selection` call together with DesignIntent,
  Circuit IR, original/revised matrix paths, and resolver question IDs; a
  completed revision matrix can advance only to the next generic workflow gate,
  while partial answers stay blocked.
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

## Electronics Domain Finish Criteria

This is the fixed finish line. Do not replace it with a rolling "next group"
section. Future electronics tasks must close one unchecked criterion below. New
finish criteria may be added only when a focused test, full-workflow artifact,
or GUI run proves a real blocker that is not covered here; document that blocker
in a numbered task file before adding it.

Do not manually hand-design AmpDemo. Merlin must learn generic workflow behavior
that applies to arbitrary electronics requests, then AmpDemo can be rerun as an
evidence check.

- [x] **F1: GUI resolver answer entry.** Electronics GUI/job state presents
  blocked resolver questions as actionable answer requirements, accepts
  submitted resolver answer evidence, and carries question IDs/evidence paths
  into focused continuation as structured `component_resolution_answers` for
  `kicad_revise_component_selection`. Complete GUI-originated answers may
  advance only to the completed component matrix handoff; incomplete answers
  remain blocked with unanswered questions and no footprint/library
  continuation.
- [x] **F2: Generic schematic and PCB realism proof.** Focused tests and
  artifacts prove generic, non-AmpDemo-specific schematic and PCB generation for
  at least two materially different request fixtures. Proof must include real
  KiCad schematic symbols/connectivity, selected footprint/source/pin
  provenance, board/safety-domain propagation, plausible PCB placement/routing
  artifacts, ERC/DRC gate behavior, and no product-specific emitter shortcuts or
  metadata-only/composite-block caricatures.
- [x] **F3: Full generic artifact-chain proof.** A focused runtime/harness path
  proves the full electronics workflow cannot skip or narrate any major gate:
  requirements inspection, DesignIntent approval, board decomposition, Circuit
  IR, component selection/revision, footprint assignment, schematic, PCB, ERC,
  DRC, SPICE scenario/run, BOM/vendor package, and fabrication/CAM output. Each
  gate must require artifact-backed evidence, and repair loops must require
  concrete mutation plus explicit rerun evidence before advancement.
- [x] **F4: Fresh full GUI workflow completion evidence.** After F1-F3 are
  green, run a fresh full GUI workflow from a clean project request. AmpDemo may
  be used only as an evidence check, not as hand-designed input. The run must
  reach honest workflow completion/FAB_READY through Merlin-generated artifacts
  or stop at a documented external blocker with actionable missing evidence; it
  must not advance from unresolved components, schematic/PCB placeholders,
  missing SPICE models/envelopes, placeholder BOM/vendor data, or declared-only
  fabrication paths. Task 487 completed this evidence pass: the rebuilt GUI
  workflow read the project spec, generated DesignIntent and Circuit IR,
  attempted component selection and revision, then stopped at
  `COMPONENT_SELECTION_REVISION_BLOCKED` with actionable resolver questions and
  without advancing to downstream placeholder artifacts.
- [x] **F5: Completion contract and status cleanup.** Update task files,
  `HANDOFF.md`, and any electronics status docs to mark the electronics domain
  complete only after F1-F4 have commands, artifacts, screenshots/logs where
  applicable, and commits. Remove stale "representative slice only" caveats only
  when the corresponding full-workflow evidence exists. Task 488 updated the
  plugin spec, README, handoff status, and final documentation sweep test so the
  finished status is bounded to evidence-gated workflow infrastructure and the
  current GUI proof's component-evidence blocker.

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

# AmpDemo Electronics Run Handoff - 2026-06-04

## Pause Point

Work was paused during a clean GUI AmpDemo run after Merlin truthfully stopped at the KiCad compile evidence gate.

The latest clean GUI session is:

```text
/Users/jonzuilkowski/Library/Application Support/Merlin/sessions/_Users_jonzuilkowski_Documents_localProject_AmpDemo/66027940-F937-4A91-A377-AAFAA3F6E094.json
```

The demo project is:

```text
/Users/jonzuilkowski/Documents/localProject/AmpDemo
```

## What Was Fixed Before The Pause

The following fixes were implemented in the current dirty worktree:

- `ComponentCatalog.swift`
  - Narrowed local KiCad connector matching so broad connector/header/terminal/jack matches cannot pass solely by category.
  - Added footprint ranking for required pin coverage.
  - Added compatible pin-pad mapping for mono phone jacks and speakON-style speaker connectors.
- `ElectronicsRuntimePlugin.swift`
  - Hydrates connector package evidence from mounting only for connector/jack intents and connector/jack candidates.
  - Preserves component pin evidence from `ComponentMatrix.components` during footprint assignment.
- `AgenticEngine.swift`
  - Tracks verified component matrix and footprint assignment artifacts.
  - Schedules `kicad_compile_project` with DesignIntent, Circuit IR, component matrix, footprint assignment, and output directory paths.
  - Added an output-directory helper based on `currentProjectPath`, with fallback from `.merlin` artifact paths.
- Tests were added/updated in:
  - `MerlinTests/Unit/EvidenceGatedComponentSelectionTests.swift`
  - `MerlinTests/Unit/FootprintEvidenceGateTests.swift`
  - `MerlinTests/Unit/LoopContinuationTests.swift`

## Validation Completed

Focused continuation/evidence tests passed:

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/LoopContinuationTests/testFootprintAssignmentSchedulesCompileProjectWithArtifactPaths \
  -only-testing:MerlinTests/LoopContinuationTests/testCircuitIRNextActionSchedulesComponentSelectionForVendorCatalogStep \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testLocalKiCadFootprintRankingMapsMonoPhoneJackPadsToRequiredPins \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testLocalKiCadFootprintRankingPrefersPinCompatibleSpeakerConnector \
  -only-testing:MerlinTests/FootprintEvidenceGateTests/testMatrixComponentPinEvidenceDrivesFootprintAssignments
```

Result: `TEST SUCCEEDED`, 5 tests, 0 failures.

Cross-gate tests passed:

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testPanelMountAudioJackUsesConnectorMountingAsPackageEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testLocalKiCadFootprintRankingMapsMonoPhoneJackPadsToRequiredPins \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testLocalKiCadFootprintRankingPrefersPinCompatibleSpeakerConnector \
  -only-testing:MerlinTests/FootprintEvidenceGateTests/testMatrixComponentPinEvidenceDrivesFootprintAssignments \
  -only-testing:MerlinTests/LoopContinuationTests/testFootprintAssignmentSchedulesCompileProjectWithArtifactPaths \
  -only-testing:MerlinTests/LoopContinuationTests/testCircuitIRNextActionSchedulesComponentSelectionForVendorCatalogStep \
  -only-testing:MerlinTests/ToolRouterBusDispatchTests/testBlockedElectronicsBusResponsePreservesPayloadAndArtifacts
```

Result: `TEST SUCCEEDED`, 7 tests, 0 failures.

Merlin was rebuilt, installed, and verified:

```sh
xcodebuild build -project Merlin.xcodeproj -scheme Merlin -destination 'platform=macOS'
rm -rf /Applications/Merlin.app
/usr/bin/ditto /Users/jonzuilkowski/Library/Developer/Xcode/DerivedData/Merlin-ehaeyubkoothsygklrellvqjerch/Build/Products/Debug/Merlin.app /Applications/Merlin.app
codesign --verify --deep --strict /Applications/Merlin.app
```

Result: build succeeded and installed app passed code signature verification.

## Clean Run Setup Used

AmpDemo was cleaned before the GUI run:

```sh
AMP=/Users/jonzuilkowski/Documents/localProject/AmpDemo
SESSION_DIR="$HOME/Library/Application Support/Merlin/sessions/_Users_jonzuilkowski_Documents_localProject_AmpDemo"
find "$AMP" -mindepth 1 -maxdepth 1 \! -name spec.md -exec rm -rf {} +
for d in artifacts vendor-feeds kicad gerbers drill simulation bom screenshots reports libraries; do mkdir -p "$AMP/$d"; done
rm -rf "$AMP/.merlin"
rm -rf "$SESSION_DIR"
: > "$HOME/.merlin/telemetry.jsonl"
```

After cleaning, only `spec.md` remained as a project file before the run.

llama.cpp provider health was verified:

- `http://127.0.0.1:8081/health` returned `{"status":"ok"}`.
- `qwen3-coder-next-local` was loaded.
- `qwen3-vl-local` was loaded.
- A minimal chat completion against `qwen3-coder-next-local` returned `OK`.

Provider slots in `~/.merlin/config.toml` at run time:

```text
execute = llamacpp:qwen3-coder-next-local
orchestrate = llamacpp:qwen3-coder-next-local
vision = llamacpp:qwen3-vl-local
reason = deepseek
temperature = 0.1
top_p = 0.9
```

## GUI Run Evidence

App-only screenshots were captured while the app was running:

```text
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/01_clean_session_app_only.png
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/02_request_submitted_app_only.png
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/03_live_start_app_only.png
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/04_live_tool_progress_app_only.png
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/05_component_selection_live_app_only.png
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/06_waiting_for_component_selection_app_only.png
/Users/jonzuilkowski/Documents/localProject/AmpDemo/screenshots/07_compile_handoff_live_app_only.png
```

One screenshot setup issue occurred initially because another app overlaid the Merlin window. RoyalTSX was terminated and the screenshots were recaptured app-only before continuing.

## Clean GUI Tool Sequence

The clean GUI session recorded this tool sequence:

```text
read_file
list_directory,kicad_build_intent_model
read_file,kicad_approve_design_intent
kicad_generate_circuit_ir
kicad_select_components
kicad_prepare_libraries
kicad_assign_footprints
kicad_compile_project
```

Important behavior:

- `read_file` was allowed for initial `spec.md` inspection.
- `list_directory` was rejected by the electronics gate and did not count as completion evidence.
- A read-only `read_file` attempt during DesignIntent approval was rejected and did not count as completion evidence.
- Merlin then used the required electronics tools and created verified artifacts through footprint assignment.
- The compile handoff continuation prompt was correct and included all required artifact paths.
- The model ignored the exact JSON instruction and called `kicad_compile_project` without `circuit_ir_path`, `component_matrix_path`, or `footprint_assignment_path`.
- The tool correctly blocked with `CIRCUIT_IR_REQUIRED`.
- Merlin stopped truthfully instead of claiming completion.

## Artifacts Created Before Block

Verified electronics artifacts:

```text
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/17DA844D-E6B6-47BF-8DA1-F46A3BDDE130-design_intent.json
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/0DDEFFAF-CAED-438B-A390-F67214314491-circuit_ir.json
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/BB439941-9CD4-42EA-A870-ED4A57315771-component_matrix.json
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/F2541E6C-83B8-4299-BFE3-A46BD357A6E6-library_report.json
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/85FCC05D-B7DF-496E-81B2-EE52293E0D29-footprint_assignment.json
```

There is also an earlier superseded DesignIntent from the same clean session:

```text
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/8018C0BE-43D3-4206-AD21-966B1A54E2A2-design_intent.json
```

Vendor catalog cache files were created under:

```text
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-catalog-cache/
```

KiCad library/root cache files were created under:

```text
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-kicad-catalog-cache/
/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-kicad-root-cache/
```

## Current Blocker

The current blocker is not the electronics tool gate. It is model argument drift at a focused handoff.

The engine generated this correct continuation instruction:

```json
{
  "design_intent_path": "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/17DA844D-E6B6-47BF-8DA1-F46A3BDDE130-design_intent.json",
  "circuit_ir_path": "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/0DDEFFAF-CAED-438B-A390-F67214314491-circuit_ir.json",
  "component_matrix_path": "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/BB439941-9CD4-42EA-A870-ED4A57315771-component_matrix.json",
  "footprint_assignment_path": "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/85FCC05D-B7DF-496E-81B2-EE52293E0D29-footprint_assignment.json",
  "output_directory": "/Users/jonzuilkowski/Documents/localProject/AmpDemo/kicad"
}
```

The model actually called:

```json
{
  "design_intent_path": "/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/17DA844D-E6B6-47BF-8DA1-F46A3BDDE130-design_intent.json",
  "output_directory": "/Users/jonzuilkowski/Documents/localProject/AmpDemo/kicad"
}
```

The tool result was:

```text
status: BLOCKED_TOOLING
code: CIRCUIT_IR_REQUIRED
message: Compile project requires Circuit IR evidence before generating KiCad artifacts.
```

## 2026-06-04 Current Fixes

Additional failures were reproduced and fixed after the initial clean run:

- The continuation evidence classifier treated “Query live component catalogs (Digi-Key, Mouser APIs) and local libraries to select real-world components” as a BOM step because it saw vendor names. It now classifies component-catalog selection text as `componentSelection` before BOM/vendor-order checks.
- The schematic materializer emitted labels but no physical wires. KiCad ERC then reported real pins as unconnected. The materializer now emits deterministic wires for every multi-endpoint CircuitIR net using resolved KiCad pin geometry.
- Label placement at star-wire hubs caused KiCad `label_multiple_wires` ERC violations. Connectivity labels are now placed only on safe wire endpoints; hub labels fall back to metadata-only labels.
- Electronics validation gates returned `.blocked` bus responses as tool errors, so ERC diagnostics and repair next-actions were lost. `ToolRouter` now treats blocked validation payloads as normal tool evidence while preserving failed, cancelled, timed-out, and unauthorized responses as errors.
- Explicit no-connect ERC repair patches previously wrote only metadata. They now emit real KiCad `(no_connect ...)` nodes at resolved symbol pin locations and still keep the Merlin repair metadata node.

Focused regression coverage added:

```text
MerlinTests/Unit/LoopContinuationTests/testVendorCatalogComponentSelectionStepAdvancesOnComponentMatrixEvidence
MerlinTests/Unit/CircuitIRToKiCadSchematicTests/testMaterializedCircuitIREmitsRealKiCadSymbolsAndConnectivity
MerlinTests/Unit/CircuitIRToKiCadSchematicTests/testValidCircuitIRCreatesKiCadProjectAndSchematic
MerlinTests/Unit/CircuitIRToKiCadSchematicTests/testMultiEndpointNetDoesNotPlaceConnectivityLabelOnStarJunction
MerlinTests/Unit/CircuitIRToKiCadSchematicTests/testExplicitNoConnectRepairPatchEmitsRealKiCadNoConnectNode
MerlinTests/Unit/ToolRouterBusDispatchTests/testBlockedElectronicsBusResponsePreservesPayloadAndArtifactsAsNormalToolResult
```

Validation passed:

```text
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests \
  -only-testing:MerlinTests/LoopContinuationTests/testVendorCatalogComponentSelectionStepAdvancesOnComponentMatrixEvidence \
  -only-testing:MerlinTests/LoopContinuationTests/testDesignIntentContinuationRequiresBuildIntentDespiteDownstreamOriginalTask \
  -only-testing:MerlinTests/LoopContinuationTests/testEvidenceGateRejectsReadOnlyChurnWhenBuildIntentToolIsRequired \
  -only-testing:MerlinTests/LoopContinuationTests/testFocusedCompileProjectCallHydratesMissingEvidencePathsBeforeDispatch \
  -only-testing:MerlinTests/LoopContinuationTests/testFootprintAssignmentSchedulesCompileProjectWithArtifactPaths \
  -only-testing:MerlinTests/LoopContinuationTests/testCircuitIRNextActionSchedulesComponentSelectionForVendorCatalogStep \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testLocalKiCadFootprintRankingMapsMonoPhoneJackPadsToRequiredPins \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testLocalKiCadFootprintRankingPrefersPinCompatibleSpeakerConnector \
  -only-testing:MerlinTests/FootprintEvidenceGateTests/testMatrixComponentPinEvidenceDrivesFootprintAssignments \
  -only-testing:MerlinTests/ToolRouterBusDispatchTests/testBlockedElectronicsBusResponsePreservesPayloadAndArtifactsAsNormalToolResult
```

Result: `TEST SUCCEEDED`, 21 tests, 0 failures.

## Next Required Run

After installing the fixed app:

1. Run focused tests only.
2. Rebuild/install `/Applications/Merlin.app`.
3. Clean AmpDemo and Merlin AmpDemo session state again.
4. Verify llama.cpp health and model availability.
5. Rerun the clean GUI AmpDemo request.
6. Capture app-only screenshots while it is running.
7. Stop and report at the next truthful evidence gate, or continue only if all artifact gates are satisfied.

## Later Optimization: Reason Slot Usage

Telemetry from the clean run showed the continuation turns selected the `execute` slot with `llamacpp:qwen3-coder-next-local`, but DeepSeek/reason was still called repeatedly around those turns through critic/verification paths.

This does not mean execute/orchestrate are idle: execute drove the actual electronics tool calls. It does mean reason is probably overused in the hot path.

After the current compile argument-hydration blocker is fixed, consider tightening electronics reason-slot usage:

- Prefer deterministic typed artifact gates before invoking the reason/critic slot.
- Reserve reason for initial high-risk design review, failed ERC/DRC/SPICE repair strategy, explicit analog critic steps, and final release review.
- Avoid invoking reason after every small continuation when tool result status and artifact evidence already determine the next state.

## Later Optimization: Electronics Subagents

The repo-level `AGENTS.md` documents built-in `explorer`, `worker`, and `default` subagent roles. For later electronics-plugin work, consider using those roles instead of adding hard-coded plugin orchestration:

- `explorer` can inspect KiCad libraries, datasheets, prior artifacts, and diagnostics read-only.
- `worker` can isolate proposed schematic/PCB repairs in a worktree before the parent accepts them.
- Plugin-specific agent roles, such as an analog critic or layout reviewer, should remain plugin-owned and only appear when the electronics plugin is loaded.
- Merlin's agent-role registry will need to become plugin-aware/dynamic before those roles are exposed; unloading the electronics plugin must remove electronics-specific roles and settings from the UI.

## Do Not Claim Done Until These Exist

The full demo is not complete. These were not produced before the pause:

- KiCad schematic file.
- KiCad PCB file.
- ERC report.
- DRC report.
- SPICE simulation output/measurements.
- Gerbers.
- Drill files.
- Final BOM artifact.
- Final report.

## Current Uncommitted State

The worktree is dirty and includes unrelated prior changes. Do not revert unrelated files.

Files touched in this focused AmpDemo continuation include:

```text
Merlin/Electronics/ComponentCatalog.swift
Merlin/Engine/AgenticEngine.swift
Merlin/Plugins/ElectronicsRuntimePlugin.swift
MerlinTests/Unit/EvidenceGatedComponentSelectionTests.swift
MerlinTests/Unit/FootprintEvidenceGateTests.swift
MerlinTests/Unit/LoopContinuationTests.swift
```

There are also earlier unrelated dirty files in the worktree. Inspect `git status --short` before committing.

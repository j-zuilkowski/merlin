# Task 478b - Component Selection Revision Workflow

## Objective

Wire a generic component-selection revision path into the electronics plugin and
focused GUI workflow continuation path.

## Implementation

- Added `kicad_revise_component_selection` to the KiCad tool definitions and
  electronics plugin manifest.
- Implemented runtime handling that:
  - requires readable `design_intent_path` and `component_matrix_path`;
  - accepts optional `circuit_ir_path` and local/live catalog evidence inputs;
  - reuses the same catalog-evidence selection machinery as initial component
    selection;
  - completes only when the revised component matrix is fully selected;
  - otherwise emits `COMPONENT_SELECTION_REVISION_BLOCKED` with targeted
    `ClarificationQuestion` prompts for unresolved refdes.
- Updated `kicad_select_components` blocked responses to include workflow
  handoff evidence and `revise_component_selection` as the next action.
- Updated focused electronics continuation so blocked component matrices route
  to `kicad_revise_component_selection` before any footprint assignment or
  repeat initial selection handoff.

## Verification

Focused build:

```bash
rm -rf /tmp/merlin-derived-task478 && xcodebuild build-for-testing -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task478
```

Result: `TEST BUILD SUCCEEDED`.

Focused selected tests:

```bash
mkdir -p /tmp/merlin-derived-task478/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest/Contents/Frameworks
cp /tmp/merlin-derived-task478/Build/Products/Debug/Merlin.app/Contents/MacOS/Merlin.debug.dylib /tmp/merlin-derived-task478/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest/Contents/Frameworks/Merlin.debug.dylib
cp /tmp/merlin-derived-task478/Build/Products/Debug/MerlinElectronicsPlugin.dylib /tmp/merlin-derived-task478/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest/Contents/Frameworks/MerlinElectronicsPlugin.dylib
xcrun xctest -XCTest 'MerlinTests.EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionResolvesBlockedMatrixWithCatalogEvidence,MerlinTests.EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBlocksWithSpecificQuestionsWhenEvidenceIsStillMissing,MerlinTests.LoopContinuationTests/testBlockedComponentMatrixSchedulesRevisionInsteadOfAssigningFootprints' /tmp/merlin-derived-task478/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest
```

Result: selected tests passed, 3 tests, 0 failures.

Focused registration check:

```bash
xcrun xctest -XCTest 'MerlinTests.ElectronicsRealRegistrationTests/testAllRequiredElectronicsCapabilitiesUsePluginNamespace' /tmp/merlin-derived-task478/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest
```

Result: 1 test, 0 failures.

`git diff --check` also passed.

The full AmpDemo GUI demo was not run.


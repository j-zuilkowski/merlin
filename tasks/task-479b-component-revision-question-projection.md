# Task 479b - Component Revision Question Projection

## Objective

Wire blocked component-selection revision questions and evidence paths into the
focused workflow stop summary and electronics GUI/job-state projection.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN component-selection revision questions are blocked THE electronics GUI SHALL project the resolver questions and evidence paths into job state.

## Implementation

- Extended `ElectronicsJobDiagnostic` and `ElectronicsJobDisplayState` with:
  - `blockedQuestions`;
  - `evidencePaths`;
  - `requiredEvidenceCategories`.
- Updated `ElectronicsJobStore` diagnostic parsing to preserve resolver
  question prompts, explicit evidence paths, artifact paths, and handoff paths
  from blocked diagnostic events.
- Updated `ElectronicsJobPanelView` to include resolver questions, needed
  evidence categories, and evidence paths in the Evidence Gates section.
- Updated the focused engine blocked-continuation path so
  `kicad_revise_component_selection` stops with an explicit summary containing
  `COMPONENT_SELECTION_REVISION_BLOCKED`, question IDs/prompts, original blocked
  matrix path, and revised matrix path.

## Verification

Focused build:

```bash
xcodebuild build-for-testing -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task479
```

Result: `TEST BUILD SUCCEEDED`.

Focused selected tests:

```bash
mkdir -p /tmp/merlin-derived-task479/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest/Contents/Frameworks
cp /tmp/merlin-derived-task479/Build/Products/Debug/Merlin.app/Contents/MacOS/Merlin.debug.dylib /tmp/merlin-derived-task479/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest/Contents/Frameworks/Merlin.debug.dylib
cp /tmp/merlin-derived-task479/Build/Products/Debug/MerlinElectronicsPlugin.dylib /tmp/merlin-derived-task479/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest/Contents/Frameworks/MerlinElectronicsPlugin.dylib
xcrun xctest -XCTest 'MerlinTests.ElectronicsJobStoreTests,MerlinTests.LoopContinuationTests/testBlockedComponentMatrixSchedulesRevisionInsteadOfAssigningFootprints,MerlinTests.LoopContinuationTests/testComponentSelectionRevisionBlockedQuestionsStopWithRecoverableEvidence' /tmp/merlin-derived-task479/Build/Products/Debug/Merlin.app/Contents/PlugIns/MerlinTests.xctest
```

Result: selected tests passed, 9 tests, 0 failures.

`git diff --check` passed.

The full AmpDemo GUI demo was not run.

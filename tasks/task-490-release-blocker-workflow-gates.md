# Task 490: repair release blocker workflow gates

## Goal

Fix the release-check Part 3 failures without weakening the electronics evidence
gates. The release path must keep blocking stale mixed-domain fixture evidence,
while structured, separated-board workflow evidence can reach `FAB_READY` or
`COMPLETE`.

## Fail-First Evidence

The v2.4.0 release Part 3 run failed in the first required surface,
`MerlinTests`, before screenshots, tag, push, or GitHub release work could
continue. The failing classes were:

- `AgenticEngineTests`
- `AmpLowVoltageFixtureTests`
- `DesignIntentApprovalFlowTests`
- `ElectronicsEndToEndHarnessTests`
- `ElectronicsGreenBoardTests`
- `ElectronicsJobPanelTests`
- `ElectronicsRuntimeHarnessIntegrationTests`

The failures showed stale expectations around narrative workflow advancement,
mixed-domain amp fixtures, missing plugin capabilities, UI section labels, and
runtime direct-evidence decoding.

## Completed Changes

- Honored explicit electronics stop boundaries before automatic handoff
  scheduling.
- Updated workflow-route tests to use structured evidence-path payloads instead
  of requirements-only workflow calls.
- Kept the stale low-voltage amp fixture blocked until separate board,
  verification-plan, and inter-board connector evidence exists.
- Moved positive end-to-end and runtime harness paths to generic separated-board
  DesignIntent and Circuit IR evidence.
- Allowed requirements-only `kicad_build_intent_model` calls to produce a draft
  DesignIntent artifact when they contain usable requirements text.
- Added explicit coding for `FabricationReleaseEvidence.normalizedBOMPath` so
  direct JSON workflow evidence preserves normalized BOM paths.
- Added missing checked-in plugin manifest capabilities for
  `kicad_approve_design_intent`, `kicad_generate_circuit_ir`, and
  `kicad_generate_spice_scenario`.
- Updated the electronics job panel test for `Blocked Jobs` and `Fab Ready`.

## Focused Verification

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-release-fixes -only-testing:MerlinTests/AgenticEngineTests/testActiveElectronicsReadOnlyNarrativeCannotSatisfyRequestedToolBoundary -only-testing:MerlinTests/AgenticEngineTests/testCompletedElectronicsWorkflowResultStopsWithoutNarrativeContinuation -only-testing:MerlinTests/AgenticEngineTests/testBlockedElectronicsWorkflowResultStopsWithoutReadOnlyContinuation -only-testing:MerlinTests/AmpLowVoltageFixtureTests -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testRequirementsDraftDesignIntentWithoutCreatingKiCadFiles -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testConstraintOnlyPayloadSynthesizesReusableClassATopologyEvidence -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests -only-testing:MerlinTests/ElectronicsGreenBoardTests -only-testing:MerlinTests/ElectronicsJobPanelTests
```

Result: selected tests passed, 37 tests, 0 failures.

`git diff --check` passed.

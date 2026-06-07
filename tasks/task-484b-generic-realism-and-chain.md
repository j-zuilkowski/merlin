# Task 484b - Generic Realism And Artifact Chain

## Objective

Close finish criteria F2 and F3 by wiring generic schematic/PCB realism proof
and artifact-backed full-workflow gate enforcement into focused runtime tests.

## Result

PCB materialization now emits selected component provenance in board footprints:
manufacturer part number, source evidence, pin-pad map, and footprint pin
compatibility. Focused generic tests cover two materially different non-AmpDemo
fixtures and assert KiCad schematic symbols/connectivity, PCB edge/routing
artifacts, board/safety-domain propagation, and no AmpDemo-specific emitter
shortcuts.

The new `ElectronicsArtifactChainGate` requires artifact-backed evidence for
each major electronics workflow gate: requirements inspection, DesignIntent
approval, board decomposition, Circuit IR, component selection/revision,
footprint assignment, schematic, PCB, ERC, DRC, SPICE scenario/run, BOM/vendor
package, and fabrication/CAM. Repair/rerun stages require concrete mutation and
explicit rerun evidence before downstream advancement. The end-to-end harness
now enforces those artifact-chain records when supplied.

## Verification

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

The full AmpDemo GUI demo was not run.

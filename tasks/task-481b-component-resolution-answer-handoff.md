# Task 481b - Component Resolution Answer Handoff

## Objective

Wire blocked component-selection revision handoff state through focused
workflow continuation so user/provider answers recover through
`kicad_revise_component_selection`, not through narrative claims or a fresh
sample-specific component selection.

## Implementation

- Added engine state for blocked component-selection revision handoff data:
  DesignIntent path, optional Circuit IR path, original blocked matrix path,
  revised blocked matrix path, and resolver question IDs.
- Recorded that state from `kicad_revise_component_selection` blocked payloads,
  including the clean-stop formatter and generic blocking-failure path.
- Normalized next-turn `kicad_revise_component_selection` calls that carry
  `component_resolution_answers` so they inherit the preserved handoff paths and
  question IDs.
- Treated a completed `kicad_revise_component_selection` matrix as satisfying
  the generic component-selection workflow requirement, then cleared the
  blocked handoff so the workflow can advance only to the next legitimate gate.

## Verification

Focused green command:

```bash
rm -rf /tmp/merlin-derived-task481 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task481 \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionAnswerTurnCarriesHandoffPathsAndAnswerEvidence \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionPartialAnswerTurnRemainsBlockedWithUnansweredQuestions
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

Broader focused command:

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

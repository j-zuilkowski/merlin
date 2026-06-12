# Task 481a - Component Resolution Answer Handoff Tests

## Objective

Prove that the focused GUI/workflow continuation path can carry structured
resolver answers back into blocked component-selection revision without
hand-designing sample-project parts.

## Acceptance

- Add fail-first focused workflow tests proving:
  - a next-turn complete answer is passed to `kicad_revise_component_selection`
    as `component_resolution_answers`;
  - the next revision call also carries the original blocked matrix path, the
    revised blocked matrix path, DesignIntent path, Circuit IR path, and blocked
    resolver question IDs;
  - a complete answer advances only to the complete component matrix handoff;
  - incomplete answers stay blocked with unanswered resolver questions and do
    not schedule footprints.
- Keep fixtures generic and local. Do not run the full AmpDemo GUI demo.

## Fail-First Evidence

Command:

```bash
rm -rf /tmp/merlin-derived-task481 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task481 \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionAnswerTurnCarriesHandoffPathsAndAnswerEvidence \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionPartialAnswerTurnRemainsBlockedWithUnansweredQuestions
```

Red result: `TEST FAILED`, 2 tests, 12 failures. The answer evidence reached the
provider call, but the workflow dropped `design_intent_path`, `circuit_ir_path`,
`original_component_matrix_path`, `component_matrix_path`, and
`component_resolution_question_ids`; after a complete answer it scheduled fresh
`kicad_select_components` instead of footprint handoff from the completed
revision matrix.

# Task 483a - GUI Resolver Answer Entry Tests

## Objective

Prove the electronics GUI/job-state path can turn blocked resolver questions
into structured answer requirements and can submit GUI-originated resolver
answers back into the focused component-selection revision workflow.

## Acceptance

- Add fail-first focused tests proving:
  - blocked component-selection revision diagnostics project actionable
    resolver answer requirements into electronics job display state;
  - resolver answer submission writes a structured continuation message with
    `component_resolution_answers`, question IDs, handoff artifact paths, and
    live catalog settings;
  - GUI-originated resolver answer continuation advances through
    `kicad_revise_component_selection` and only then schedules the footprint
    handoff from a completed component matrix.
- Keep fixtures generic and local. Do not run the full AmpDemo GUI demo.

## Fail-First Evidence

Command:

```bash
rm -rf /tmp/merlin-derived-task483 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task483 \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testBlockedResolverQuestionsProjectActionableAnswerRequirements \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testResolverAnswerSubmissionWritesStructuredContinuationMessage \
  -only-testing:MerlinTests/LoopContinuationTests/testGUIResolverAnswerContinuationAdvancesThroughRevisionHandoff
```

Red result: `TEST FAILED`. The new answer types/display projection were absent
at first; after partial wiring, the resolver-answer continuation was not treated
as artifact-backed GUI evidence and a stale blocked continuation state prevented
the revision handoff from advancing.

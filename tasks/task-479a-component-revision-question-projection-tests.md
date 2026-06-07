# Task 479a - Component Revision Question Projection Tests

## Objective

Prove that a blocked component-selection revision result is visible and
recoverable in the full focused workflow path instead of disappearing into a
generic blocked message or advancing to footprints.

## Acceptance

- Add an engine continuation test that starts from a blocked component matrix
  revision result and proves:
  - `COMPONENT_SELECTION_REVISION_BLOCKED` is preserved;
  - resolver questions are included with question IDs and prompts;
  - original and revised component matrix paths are surfaced;
  - no footprint continuation is scheduled.
- Add a GUI/job-state projection test that proves blocked resolver questions,
  evidence paths, and required evidence categories are available on blocked job
  display rows.
- Keep the fixture generic. Do not hand-select AmpDemo parts and do not run the
  full AmpDemo GUI demo.

## Fail-First Evidence

Command:

```bash
rm -rf /tmp/merlin-derived-task479 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task479 \
  -only-testing:MerlinTests/ElectronicsJobStoreTests/testBlockedComponentSelectionRevisionQuestionsProjectIntoDisplayState \
  -only-testing:MerlinTests/LoopContinuationTests/testComponentSelectionRevisionBlockedQuestionsStopWithRecoverableEvidence
```

Red result: `TEST FAILED` at compile time. `ElectronicsJobDisplayState` had no
`blockedQuestions`, `evidencePaths`, or `requiredEvidenceCategories` members.


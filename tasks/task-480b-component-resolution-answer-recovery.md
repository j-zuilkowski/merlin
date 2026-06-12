# Task 480b - Component Resolution Answer Recovery

## Objective

Wire structured resolver answers into generic component-selection revision so a
blocked matrix can recover only through evidence that satisfies the existing
catalog validator.

## Implementation

- Extended `kicad_revise_component_selection` schema with:
  - `component_resolution_answers`;
  - `component_resolution_answers_json`;
  - `component_resolution_answers_path`.
- Updated runtime catalog evidence gathering to ingest inline, JSON-string, or
  file-backed resolver answers and convert them into ordinary
  `ComponentCandidate` records.
- Resolver-answer candidates carry:
  - `target_refdes` provenance so answers bind to the intended component;
  - manufacturer, MPN, package, lifecycle, availability, ratings, datasheet, and
    source evidence;
  - optional footprint candidate evidence, including package compatibility and
    pin-pad maps.
- Left selection, ranking, validation, and blocked-question behavior in the
  existing generic catalog path. Missing evidence still blocks through
  `ComponentCatalogValidator`; unanswered components still emit resolver
  questions before footprints.

## Verification

Focused green command:

```bash
rm -rf /tmp/merlin-derived-task480 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task480 \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBuildsCandidateEvidenceFromStructuredAnswers \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionWithPartialStructuredAnswersStillBlocksBeforeFootprints
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

Broader focused command:

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

The full AmpDemo GUI demo was not run.

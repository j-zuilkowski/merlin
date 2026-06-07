# Task 480a - Component Resolution Answer Tests

## Objective

Prove that blocked component-selection revision can recover from structured
resolver answers as generic catalog evidence, not from AmpDemo-specific manual
part choices.

## Acceptance

- Add fail-first tests for `kicad_revise_component_selection` proving:
  - a complete structured answer with refdes, manufacturer, MPN, package,
    ratings, datasheet, provenance, and footprint pin-map evidence becomes a
    selected `ComponentCandidate`;
  - partial structured answers select only the answered component and keep any
    unanswered resolver question blocked;
  - footprint/library continuation actions are not offered while any component
    remains unresolved.
- Keep the fixtures generic and local. Do not run the full AmpDemo GUI demo.

## Fail-First Evidence

Command:

```bash
rm -rf /tmp/merlin-derived-task480 && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task480 \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBuildsCandidateEvidenceFromStructuredAnswers \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionWithPartialStructuredAnswersStillBlocksBeforeFootprints
```

Red result: `TEST FAILED`, 2 tests, 4 failures. Structured resolver answers
were ignored by the runtime catalog path, so QOUT1 remained
`requires_vendor_resolution` and the complete-answer revision stayed blocked.

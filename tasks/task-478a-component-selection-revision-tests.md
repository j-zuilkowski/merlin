# Task 478a - Component Selection Revision Tests

## Objective

Prove that the full electronics workflow cannot advance from a blocked
component matrix by rerunning narrative component selection or jumping to
footprints.

## Acceptance

- Add runtime tests for `kicad_revise_component_selection` that:
  - resolve a previously blocked matrix only when catalog evidence provides a
    concrete manufacturer part;
  - remain blocked with structured questions when manufacturer, MPN, datasheet,
    package, rating, footprint, or pin-compatibility evidence is still missing.
- Add a continuation test proving a `BLOCKED_INPUT_QUALITY` component-selection
  result with `revise_component_selection` schedules
  `kicad_revise_component_selection`, not `kicad_assign_footprints`.
- Keep tests generic. Do not encode a hand-selected AmpDemo parts list.

## Fail-First Evidence

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionResolvesBlockedMatrixWithCatalogEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testComponentSelectionRevisionBlocksWithSpecificQuestionsWhenEvidenceIsStillMissing \
  -only-testing:MerlinTests/LoopContinuationTests/testBlockedComponentMatrixSchedulesRevisionInsteadOfAssigningFootprints
```

Red result before implementation:

- `testComponentSelectionRevisionBlocksWithSpecificQuestionsWhenEvidenceIsStillMissing`
  failed because the runtime returned `failed` instead of `blocked` and emitted
  no `KiCadToolResult`.
- `testComponentSelectionRevisionResolvesBlockedMatrixWithCatalogEvidence`
  failed because the runtime returned `failed` instead of `ok` and emitted no
  component matrix artifact.
- `testBlockedComponentMatrixSchedulesRevisionInsteadOfAssigningFootprints`
  failed because no continuation inject file was produced.

Overall red result: 3 tests, 5 failures.


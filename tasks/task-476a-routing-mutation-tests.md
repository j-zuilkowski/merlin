# Task 476a - Native Routing Mutation Tests

## Objective

Add fail-first coverage proving DRC routing repair application cannot advance by
adding a narrative marker. The full workflow path must either write KiCad-native
route objects backed by board/net geometry or block without mutating the board.

## Fail-First Tests

Focused command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationBlocksRoutingWithoutPadGeometry
```

Expected red state before implementation:

- `testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence` fails because the
  routing patch writes a `Merlin reroute required` `gr_text` marker instead of
  native `(segment ...)` / `(via ...)` objects.
- `testDRCRepairPatchApplicationBlocksRoutingWithoutPadGeometry` fails because a
  routing-only patch still mutates the PCB with the marker even when no pad-level
  routing geometry exists.

Observed red result:

`TEST FAILED`, 2 tests, 12 assertion failures. The board still contained
`Merlin reroute required`, did not contain route `(segment ...)` / `(via ...)`
objects, evidence still recorded `routing_marker`, and the no-geometry routing
case returned `ok` instead of blocking.

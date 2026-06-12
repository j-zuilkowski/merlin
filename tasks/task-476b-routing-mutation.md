# Task 476b - Native Routing Mutation

## Objective

Replace the DRC routing repair marker with generic KiCad-native routing mutation
in the full `kicad_apply_drc_repair_patch` runtime path.

## Implementation

- Replaced the routing `gr_text` marker mutation with board parsing that:
  - resolves the routing patch target to a KiCad net table entry;
  - scans footprints for pads assigned to that net;
  - requires at least two pad anchors before mutating;
  - inserts native `(segment ...)` and `(via ...)` S-expressions into the PCB;
  - records `routing_segment` and `routing_via` changed objects in
    `layout_mutation_evidence`.
- Routing-only repair plans without pad-level net geometry now leave the board
  unchanged and block through the existing `regenerate_drc_repair_plan` path.

## Verification

Fail-first command before implementation:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationBlocksRoutingWithoutPadGeometry
```

Red result: `TEST FAILED`, 2 tests, 12 assertion failures.

Green command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationMutatesBoardAndEmitsEvidence \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testDRCRepairPatchApplicationBlocksRoutingWithoutPadGeometry
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

Broader focused command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests
```

Result: `TEST SUCCEEDED`, 11 tests, 0 failures.

The full AmpDemo GUI demo was not run.

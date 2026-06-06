Status: complete

# Task 443a - Runtime SPICE Repair Action Tests

Date: 2026-05-30

## Goal

Add focused tests proving the electronics runtime exposes a SPICE repair action
that uses measurements and scenario envelopes instead of narrative assumptions.

## Test Scope

1. `kicad_repair_spice_from_diagnostics` requires measurement and scenario
   artifacts.
2. Out-of-envelope measurements produce a `spice_repair_plan` artifact.
3. Unsupported measurements block and require engineering review.
4. The repair action must route to `rerun_spice`.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testSPICERepairActionPlansMeasurementRepairAndBlocksUnsupportedLog
```

Expected before Task 444b: no runtime SPICE repair action exists.

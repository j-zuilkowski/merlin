Status: complete

# Task 444b - Runtime SPICE Repair Action

Date: 2026-05-30

## Goal

Implement the plugin-owned SPICE repair action using fixed-topology simulation
repair planning.

## Implementation Scope

1. Add `kicad_repair_spice_from_diagnostics` to the electronics plugin manifest
   and KiCad tool definitions.
2. Route the runtime capability to a SPICE repair handler.
3. Parse ngspice measurement logs and `SPICESimulationScenario` envelopes.
4. Emit a `spice_repair_plan` artifact for supported measurement failures.
5. Block unsupported failures without claiming simulation verification.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testSPICERepairActionPlansMeasurementRepairAndBlocksUnsupportedLog \
  -only-testing:MerlinTests/ElectronicsRealRegistrationTests
```

Expected after Task 444b: SPICE diagnostics have an explicit repair-plan action.

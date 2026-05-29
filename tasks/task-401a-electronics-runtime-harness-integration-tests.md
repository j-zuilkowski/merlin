# Task 401a - Electronics Runtime Harness Integration Tests

Goal: add failing tests proving the runtime workflow path delegates status to
`ElectronicsEndToEndHarness`.

Add focused tests in `MerlinTests/Unit/ElectronicsRuntimeHarnessIntegrationTests.swift`.

Required assertions:

1. `workflow.requirements_to_pcb` accepts structured `design_intent_path`,
   `circuit_ir_path`, `output_directory`, and end-to-end evidence.
2. With the amp low-voltage fixture and complete verifier/fab evidence but no
   release package or approval, the runtime returns a non-complete `FAB_READY`
   harness result.
3. If SPICE evidence is missing while the DesignIntent requires SPICE, the
   runtime blocks and reports `spice_measurements` as missing.
4. `COMPLETE` is returned only when the harness evidence includes a release
   package and release approval.
5. Runtime payloads with DesignIntent/CircuitIR paths must decode as
   `ElectronicsEndToEndResult`, not legacy narrative/final-report completion.

Verify:

```bash
xcodegen generate && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests
```

Expected before task 401b: fail because `ElectronicsRuntimePlugin` does not yet
route workflow requests through the end-to-end harness.

# Task 400a - Electronics End-To-End Harness Tests

Goal: add failing tests for a generic backend electronics harness that proves
workflow status from verifier evidence rather than narration.

Add focused tests in `MerlinTests/Unit/ElectronicsEndToEndHarnessTests.swift`.

Required assertions:

1. Spec/read-only input or approved intent without Circuit IR and verifier
   evidence cannot reach `COMPLETE`.
2. The amp low-voltage fixture can progress through generic schema validation,
   resolver-backed schematic materialization, ERC, PCB evidence, SPICE evidence,
   and fabrication evidence to `FAB_READY`.
3. The same fixture cannot reach `FAB_READY` or `COMPLETE` when SPICE evidence
   is missing and the approved intent requires SPICE.
4. `COMPLETE` requires a release package and explicit release approval in
   addition to schematic, PCB, ERC, DRC, SPICE, BOM, and fabrication evidence.
5. The mains power board blocks without high-stakes signoff and never returns a
   safety-certification claim.

Verify:

```bash
xcodegen generate && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests
```

Expected before task 400b: fail because the harness API does not exist.

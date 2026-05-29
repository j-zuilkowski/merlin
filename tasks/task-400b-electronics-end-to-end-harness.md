# Task 400b - Electronics End-To-End Harness

Goal: implement the generic backend harness covered by task 400a.

Implementation requirements:

1. Add a Merlin/Electronics harness that accepts optional `DesignIntent`,
   optional `CircuitIR`, an output directory, verifier evidence, and approvals.
2. Run only generic plugin logic:
   - schema gate,
   - KiCad library/pin resolver evidence derived from Circuit IR,
   - Circuit IR schematic materialization,
   - schematic parity check,
   - ERC repair loop and `SCHEMATIC_VERIFIED`,
   - PCB verification gate,
   - SPICE scenario/model/measurement/envelope gate,
   - BOM/fabrication/release gate,
   - high-stakes safety policy.
3. Report structured statuses and missing evidence. Do not infer progress from
   text, plan steps, chat narration, or fixture names.
4. Keep `SCHEMATIC_VERIFIED`, `PCB_VERIFIED`, `FAB_READY`, and `COMPLETE`
   distinct.
5. Never certify mains/high-stakes safety. CAD verification may be reported,
   but build/use safety remains outside Merlin's authority.

Verify:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests
```

Expected after task 400b: tests pass.

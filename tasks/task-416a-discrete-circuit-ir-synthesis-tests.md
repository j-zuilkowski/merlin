# Task 416a - Discrete Circuit IR Synthesis Tests

## Goal

Add focused tests proving Circuit IR synthesis emits discrete, evidence-backed
components and valid nets instead of block-level placeholders.

## Failing Tests

Add focused tests proving:

1. `kicad_generate_circuit_ir` produces a `circuit_ir` artifact from an approved
   DesignIntent.
2. Single-ended Class-A audio topology evidence expands tone/filter blocks into
   discrete R/C/control parts.
3. Circuit IR components carry source evidence.
4. Generated nets reference real component pins.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testApprovedClassATopologyGeneratesDiscreteCircuitIR
```

Expected: tests fail before Task 416b.

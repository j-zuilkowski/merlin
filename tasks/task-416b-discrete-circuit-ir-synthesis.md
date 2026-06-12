# Task 416b - Discrete Circuit IR Synthesis

## Goal

Implement generic intent-to-CircuitIR synthesis that expands simple discrete
electronics intent patterns into real components, pins, nets, and source
evidence.

## Implementation

1. Add `kicad_generate_circuit_ir`.
2. Read approved DesignIntent artifacts.
3. Convert connectors, resistors, capacitors, bridge rectifiers, and transistor
   intents into Circuit IR components.
4. Expand `discrete_RC` and sweepable filter intents into R/C/control parts.
5. Rewrite nets through expanded components and validate endpoints.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testApprovedClassATopologyGeneratesDiscreteCircuitIR \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected: tests pass.

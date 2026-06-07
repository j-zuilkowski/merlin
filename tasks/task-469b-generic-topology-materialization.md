# Task 469b - Generic Topology Materialization

## Goal

Implement generic board-scoped Circuit IR generation and explicit schematic/PCB
board-domain provenance. This is a Merlin workflow capability, not a manual
AmpDemo design split.

## Implementation

- `kicad_generate_circuit_ir` accepts optional `board_id` / `boardId` and
  blocks unknown board requests with `CIRCUIT_IR_BOARD_UNKNOWN`.
- Circuit IR synthesis now scopes components to the requested DesignIntent board
  when component intent constraints provide `board_id`.
- Circuit IR synthesis now scopes nets to endpoints present on the selected
  board, avoiding cross-board endpoint leakage in per-board artifacts.
- Generated Circuit IR now records `board_id` and `safety_domain` constraints
  and uses the selected board's verification plan when available.
- Schematic symbols and generated PCB footprints now carry explicit `BoardID`
  and `SafetyDomain` properties derived from Circuit IR evidence.

## Focused Verification

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testCircuitIRGenerationHonorsGenericBoardScopeAndSafetyDomains \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testMaterializersCarryGenericBoardAndSafetyDomainProvenance
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testApprovedClassATopologyGeneratesDiscreteCircuitIR \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testConstraintOnlyPayloadSynthesizesReusableClassATopologyEvidence \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testMaterializedCircuitIREmitsRealKiCadSymbolsAndConnectivity \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testSchematicRealismValidatorPassesMaterializedDiscreteCircuitIR \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testSchematicMaterializerContainsNoProductSpecificEmitterShortcuts
```

Result: `TEST SUCCEEDED`, 5 tests, 0 failures.

## Remaining Scope

This does not finish ERC/DRC repair loops, vendor/BOM evidence, fabrication
packaging, GUI job-state consistency, or a full AmpDemo GUI run.

# Task 469a - Generic Topology Materialization Tests

## Goal

Add fail-first tests proving Merlin keeps structured board/domain evidence
through Circuit IR generation and schematic/PCB materialization without
AmpDemo-specific shortcuts.

## Tests Added

- `DesignIntentApprovalFlowTests.testCircuitIRGenerationHonorsGenericBoardScopeAndSafetyDomains`
  uses a generic mixed-domain controller DesignIntent and requests the
  `low_voltage_control` board. The generated Circuit IR must:
  - use the requested board ID;
  - include only components scoped to that board;
  - include only nets whose endpoints belong to that board;
  - preserve component and net safety-domain evidence.
- `CircuitIRToKiCadSchematicTests.testMaterializersCarryGenericBoardAndSafetyDomainProvenance`
  verifies schematic and PCB materializers emit explicit `BoardID` and
  `SafetyDomain` properties from generic Circuit IR evidence.

## Fail-First Evidence

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testCircuitIRGenerationHonorsGenericBoardScopeAndSafetyDomains \
  -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testMaterializersCarryGenericBoardAndSafetyDomainProvenance
```

Result: `TEST FAILED`. Circuit IR generation ignored requested `board_id`,
collapsed all components and nets into the first board, and materializers did
not emit explicit board/domain provenance properties.

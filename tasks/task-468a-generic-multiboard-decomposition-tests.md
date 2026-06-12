# Task 468a - Generic Multi-Board Decomposition Tests

## Goal

Add failing tests for Merlin-owned electronics design decomposition. The work is
not to manually split AmpDemo. Merlin must infer board/domain boundaries from
structured requirements for any electronics request.

## Requirements

1. A design request that mixes hazardous mains/transformer circuitry with
   isolated low-voltage signal circuitry must not advance as one monolithic
   board unless explicit safety-domain evidence says that is allowed.
2. The decomposition path must produce or require structured `DesignIntent`
   board entries with board IDs, titles, safety domains, isolation requirements,
   inter-board connectors, and per-board verification plans.
3. Circuit IR generation/materialization must preserve board IDs and safety
   domains without AmpDemo-specific names, roles, component shortcuts, or
   fixture-only routing.
4. AmpDemo may be used only as a regression fixture proving the generic
   decomposition recognizes separate mains/transformer and low-voltage amplifier
   domains from the request. The implementation must remain data-driven and
   reusable for unrelated designs.
5. Full workflow gates must block downstream schematic/PCB/SPICE/BOM/fab
   advancement when the required decomposition evidence is missing or when
   high-stakes domains are merged without approval.

## Expected Red State

Focused tests fail because Merlin does not yet have a generic design
decomposition gate that enforces board/domain boundaries before downstream
electronics workflow advancement.

## Fail-First Evidence

Command:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testGenericMultiboardDecompositionBlocksMergedMainsAndLowVoltageDomains \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testGenericMultiboardDecompositionPassesSeparatedDomainEvidence \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testCircuitIRBoardIDMustReferenceDesignIntentBoard \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowBlocksMergedHighStakesDomainsBeforeSchematicPCBOrFabAdvance \
  -only-testing:MerlinTests/ElectronicsEndToEndHarnessTests/testWorkflowCarriesSeparatedBoardDomainEvidenceThroughHandoff
```

Result: `TEST FAILED` before implementation. The build failed because
`InterBoardConnectorIntent` did not exist and `BoardIntent` did not accept
per-board `verificationPlan` or `interBoardConnectors` evidence.

## Tests Added

- `ElectronicsPluginSchemaTests` now proves merged mains plus isolated
  low-voltage domains are blocked with `MULTIBOARD_DECOMPOSITION_REQUIRED`,
  `INTERBOARD_CONNECTOR_REQUIRED`, and `BOARD_VERIFICATION_PLAN_REQUIRED`.
- `ElectronicsPluginSchemaTests` proves separated board/domain evidence passes
  and that Circuit IR `board_id` must reference a declared `DesignIntent` board.
- `ElectronicsEndToEndHarnessTests` proves the full workflow cannot advance
  schematic/PCB/fabrication status from a merged high-stakes domain, while the
  same workflow can carry separated board/domain evidence through the handoff.

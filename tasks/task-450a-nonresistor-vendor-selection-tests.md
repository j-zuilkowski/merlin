# Task 450a: Non-Resistor Vendor Selection Tests

## Goal

Add failing tests proving live vendor catalog evidence can drive deterministic
selection for non-resistor components without weakening the evidence gate.

## Scope

1. Verify structured catalog queries for bridge rectifiers, capacitors,
   semiconductors, connectors, and potentiometers include electrical intent
   terms rather than KiCad symbol names.
2. Verify capacitor selection uses capacitance, voltage, dielectric, mounting,
   package, datasheet, and provenance evidence.
3. Verify semiconductor selection uses polarity, voltage, current, power,
   package, datasheet, and provenance evidence.
4. Verify connector selection uses position count, current/voltage ratings,
   mounting, datasheet, and provenance evidence.
5. Verify potentiometer selection uses resistance, taper, mounting, datasheet,
   and provenance evidence.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testNonResistorQueriesUseStructuredElectricalIntent \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testCapacitorSelectionUsesValueVoltageAndDielectricEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testSemiconductorSelectionUsesPolarityAndRatingsEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testConnectorSelectionUsesPositionAndRatingEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testPotentiometerSelectionUsesResistanceAndTaperEvidence
```

Expected: tests fail before implementation and pass after task 450b.

# Task 450b: Non-Resistor Vendor Selection

## Goal

Extend evidence-gated component selection beyond resistors so capacitors,
semiconductors, bridge rectifiers, connectors, and potentiometers can be
selected when live vendor evidence is complete and uniquely best.

## Scope

1. Preserve and normalize category-specific evidence from provider descriptions
   and ratings: capacitance, voltage, current, power, polarity, position count,
   taper, mounting, and package.
2. Generate category-specific vendor search terms from structured component
   constraints.
3. Score matching category evidence strongly enough to choose a uniquely better
   candidate.
4. Reject candidates that contradict required capacitance, resistance, polarity,
   positions, mounting, package, voltage, current, or power constraints.
5. Keep the existing truth gate: no selection without manufacturer, MPN,
   package, ratings, datasheet, and provenance evidence.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testNonResistorQueriesUseStructuredElectricalIntent \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testCapacitorSelectionUsesValueVoltageAndDielectricEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testSemiconductorSelectionUsesPolarityAndRatingsEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testConnectorSelectionUsesPositionAndRatingEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testPotentiometerSelectionUsesResistanceAndTaperEvidence
```

Expected: `TEST SUCCEEDED`.

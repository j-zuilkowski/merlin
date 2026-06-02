# Task 451b: Live Vendor Adapter Evidence

## Goal

Normalize non-resistor package and rating evidence from live vendor payloads
without weakening the existing datasheet/provenance selection gate.

## Scope

1. Extract package/mounting hints from raw descriptions and category names:
   radial, axial, screw terminal, snap-in, THT/through-hole, panel mount, TO
   packages, SOT packages, and lead spacing.
2. Preserve datasheet URLs only when present in the provider payload.
3. Preserve category-specific ratings for positions, polarity, taper,
   capacitance, resistance, voltage, current, and power.
4. Keep candidates blocked when provider data still lacks required datasheet or
   package evidence.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testMouserNonResistorAdapterExtractsPackageAndDatasheetEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testDigiKeyNonResistorAdapterExtractsPackageAndDatasheetEvidence
```

Expected: `TEST SUCCEEDED`.

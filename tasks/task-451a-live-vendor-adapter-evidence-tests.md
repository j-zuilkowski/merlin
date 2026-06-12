# Task 451a: Live Vendor Adapter Evidence Tests

## Goal

Add failing tests proving Mouser and Digi-Key raw provider payloads preserve
non-resistor package and datasheet evidence when the vendor response contains it.

## Scope

1. Verify bridge rectifier descriptions preserve package, voltage, current,
   datasheet, product URL, and provenance.
2. Verify capacitor descriptions preserve radial/lead-spacing or through-hole
   package evidence, capacitance, voltage, datasheet, and provenance.
3. Verify connector descriptions preserve position count, mounting/package,
   datasheet, and provenance.
4. Verify transistor descriptions preserve package, polarity, voltage/current,
   datasheet, and provenance.
5. Verify potentiometer descriptions preserve resistance, taper, mounting,
   datasheet, and provenance.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testMouserNonResistorAdapterExtractsPackageAndDatasheetEvidence \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testDigiKeyNonResistorAdapterExtractsPackageAndDatasheetEvidence
```

Expected: tests fail before implementation and pass after task 451b.

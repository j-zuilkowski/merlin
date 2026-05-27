# Task 386a - Schematic OCR extraction tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass
- Surface inventory: tasks/SURFACE-INVENTORY.md#t-schematic-extraction--ocr---s6--m1m5
- Failure evidence: merlin-eval/results/S6-OCR-harness-2026-05-27T18-40-35Z.md

## Behavior

WHEN Merlin ingests a raster schematic through the first-party electronics runtime plugin THE ingest stage SHALL perform real schematic extraction rather than writing a placeholder artifact.

GIVEN `merlin-eval/fixtures/electronics/schematic-image/rc-filter.png`,
WHEN `kicad_ingest_schematic` runs with a vision-capable provider,
THEN the extraction report SHALL include component `R1` value `10k`,
component `C1` value `100nF`, and nets equivalent to `VIN`, `OUT`, and `GND`.

GIVEN the extraction report is passed into the S6 OCR scenario,
WHEN the agent reports recognised components and connections,
THEN the assistant response SHALL mention `R1`, `C1`, `10k`, and `100nF`.

## Red Tests

- Add focused unit tests for a production extraction component using a scripted
  vision provider. The test fixture response should include the exact RC filter
  JSON and assert the normalized `ExtractionReport` contains:
  - `R1` / `10k` / resistor
  - `C1` / `100nF` / capacitor
  - `VIN`, `OUT`, and `GND` net membership
- Add a runtime-plugin dispatch test for `kicad_ingest_schematic` with
  `source_type = raster_image`. It should fail against the current placeholder
  artifact because `extracted_components` and `extracted_nets` are absent.
- Keep low-quality image handling intact: raster inputs with an explicit DPI
  below 300 still return the existing invalid-input structured block.
- Keep the live S6 OCR assertion as the end-to-end proof:
  `CapabilityScenarioTests/testS6SchematicOCR`.

## Verification

```bash
xcodegen generate
xcodebuild test -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/SchematicOCRExtractionTests \
  -only-testing:MerlinTests/ElectronicsRealRegistrationTests
RUN_LIVE_TESTS=1 xcodebuild test -scheme MerlinTests-Live -destination 'platform=macOS' \
  -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS6SchematicOCR
```

Expected red state: the new unit/runtime tests fail because
`ElectronicsRuntimePlugin.handleSchematicIngest` currently only writes a
placeholder artifact, and the focused live S6 OCR test still fails to report
`R1`, `C1`, `10k`, and `100nF`.

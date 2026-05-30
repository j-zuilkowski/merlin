# Task 386b - Schematic OCR extraction

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass
- Surface inventory: tasks/SURFACE-INVENTORY.md#t-schematic-extraction--ocr---s6--m1m5
- Test task: tasks/task-386a-schematic-ocr-extraction-tests.md

## Behavior

WHEN a user imports a raster or PDF schematic THE electronics plugin SHALL extract components and nets into a durable report that downstream KiCad workflow tools can consume.

GIVEN the RC filter fixture image,
WHEN the live S6 OCR scenario runs with the configured LM Studio vision model,
THEN Merlin SHALL report `R1 10k`, `C1 100nF`, and the connections between
`VIN`, `OUT`, and `GND`.

## Implementation

- Introduce a production schematic OCR extraction path behind
  `kicad_ingest_schematic`.
- Use the configured vision slot/provider for raster schematic extraction. Do
  not rely on the execute model or a hard-coded provider ID.
- Request strict JSON from the vision model with this shape:
  `components`, `nets`, `needs_clarification`, and optional `warnings`.
- Normalize common value spellings before persistence:
  `10 k`, `10K`, and `10kΩ` should compare as `10k`; `100 nF`, `100nf`, and
  `0.1uF` should compare as `100nF`.
- Persist a real `ExtractionReport` artifact with
  `extracted_components`, `extracted_nets`, and confidence fields, not the
  current placeholder `{source, source_type, ambiguous_nets, unknown_components}`.
- Feed the extraction report back into the agent context in a compact,
  human-readable form so the S6 OCR response can report the recognised parts
  and netlist without re-opening the image.
- Preserve existing input-quality gates and structured-block failures for
  missing files and explicit low-DPI raster inputs.
- Keep the implementation provider-agnostic: LM Studio, Jan, and llama.cpp
  router-mode vision providers should all be usable when configured in the
  vision slot.

## Verification

```bash
xcodegen generate
xcodebuild test -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/SchematicOCRExtractionTests \
  -only-testing:MerlinTests/ElectronicsRealRegistrationTests \
  -only-testing:MerlinTests/SchematicExtractionPolicyTests
RUN_LIVE_TESTS=1 xcodebuild test -scheme MerlinTests-Live -destination 'platform=macOS' \
  -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS6SchematicOCR
```

Expected green state: focused unit/runtime tests pass, and the focused live
S6 OCR scenario passes with a report containing `R1`, `C1`, `10k`, and
`100nF`.

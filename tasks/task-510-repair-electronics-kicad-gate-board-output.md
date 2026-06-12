# Task 510 - Repair Electronics KiCad Gate Board Output

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology
- Release ledger: `docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md`
- Gate: #9, electronics/KiCad deterministic checks
- Evidence log: `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.log`

## Behavior

WHEN release gate #9 runs, the AmpDemo PCB slice SHALL generate a populated
KiCad board from real component-selection and footprint-assignment evidence
instead of skipping or accepting a blank/generated-file-only placeholder.

WHEN local KiCad footprint libraries are used, selected footprint evidence
SHALL carry the source `.kicad_mod` path and 3D model reference through
component selection, footprint assignment, and PCB materialization.

WHEN a stale KiCad catalog cache lacks source paths for extracted footprint pad
evidence, the cache SHALL be ignored so Merlin refreshes real footprint-source
and model evidence before assigning footprints.

## Evidence

- Focused AmpDemo PCB slice:
  `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination platform=macOS -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testAmpDemoEvidenceBackedPCBCompilePlacesAllFootprintsAndRunsDRC`
  passed and generated
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/pcb-slice/69F1DB01-73B1-4189-9F46-C6EFBDF875D6/isolated_secondary.kicad_pcb`
  with a zero-violation DRC report at
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/21A49DE6-A531-450E-AB15-5981B260F240-drc-report.json`.
- Focused cache contract:
  `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination platform=macOS -only-testing:MerlinTests/ComponentCatalogContractsTests`
  passed 15 tests, including old extracted KiCad cache rejection.
- Release gate #9 rerun:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.log`
  records 343 focused electronics/KiCad tests passing with 5 skips and 0
  failures. The run includes
  `EvidenceGatedComponentSelectionTests.testAmpDemoEvidenceBackedPCBCompilePlacesAllFootprintsAndRunsDRC`,
  which generated
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/pcb-slice/54F5F058-4CE3-4A2E-853E-74980AA944E8/isolated_secondary.kicad_pcb`
  and DRC report
  `/Users/jonzuilkowski/Documents/localProject/AmpDemo/.merlin/electronics-artifacts/7FB63521-6C6F-44D4-8EE3-83E02F54C269-drc-report.json`.

## Result

Release gate #9 is repaired as an actual board-output gate. The latest generated
AmpDemo board has 21 footprints, 21 3D model references, 62 pads, 90 routed
segments, 36 vias, and a KiCad DRC report with 0 violations and 0 unconnected
items.

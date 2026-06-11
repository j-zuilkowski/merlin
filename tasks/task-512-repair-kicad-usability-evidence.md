# Task 512 - Repair KiCad Usability Evidence

## Problem

The Task 511 release screenshots were not sufficient evidence of a usable
generated KiCad result. The board evidence could still read as placement-only,
the schematic view hid or clipped useful connector context, and stale GUI
capture paths could show KiCad Project Manager instead of the actual editors.

## Fail-First Evidence

- `testBoardEvidenceCheckerRejectsOverlongBusRouteEvidence` initially failed
  because route-count-only evidence with a far bus lane was accepted.
- `testSchematicWriterHidesEvidenceFieldsThatObscureUsableSymbols` initially
  failed because evidence fields such as `BoardID`, `Footprint`,
  `ManufacturerPartNumber`, and `SafetyDomain` were visible on top of schematic
  symbols.
- `testSchematicMaterializerKeepsLargeDiscreteCircuitInsideVisibleSheetArea`
  initially failed because a 21-component generated schematic placed the speaker
  connector below the visible sheet area.
- `testSchematicMaterializerShortensGeneratedInternalNetLabelsForReadability`
  initially failed because implementation-derived net labels such as
  `FILTER1_INTERNAL_CFILT1_RVFILT1` were emitted directly into the visual
  schematic.

## Repair

- Added board evidence checks for multi-endpoint nets with no copper segments
  and for route lengths that are excessive relative to endpoint span.
- Reworked generated PCB routing from far/global bus lanes into local source
  escape, source via, back-copper local lane, destination via, and destination
  escape segments.
- Kept the conservative one-row placement order but reduced the sparse canvas
  footprint by tightening board margins and removing duplicate route-corridor
  height.
- Hid machine evidence fields that obscure symbols while preserving them in the
  KiCad schematic file.
- Kept reference/value fields near each symbol and expanded schematic placement
  to six columns so connectors remain on the visible A4 sheet.
- Shortened long generated internal visual net labels while preserving hidden
  original-name `NodeMap` metadata for validation.

## Focused Green Evidence

- Focused schematic/PCB usability slice:
  `/tmp/merlin-derived-task512/Logs/Test/Test-MerlinTests-2026.06.11_16-11-37--0400.xcresult`
  passed 11 tests.
- Focused routed-board density/locality slice:
  `/tmp/merlin-derived-task512/Logs/Test/Test-MerlinTests-2026.06.11_16-16-56--0400.xcresult`
  passed 3 tests.
- Real AmpDemo PCB slice:
  `/tmp/merlin-derived-task512/Logs/Test/Test-MerlinTests-2026.06.11_16-17-13--0400.xcresult`
  passed `EvidenceGatedComponentSelectionTests.testAmpDemoEvidenceBackedPCBCompilePlacesAllFootprintsAndRunsDRC`.

## Generated Evidence

The final generated board source copied into the release evidence bundle is:

- `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/source/isolated_secondary.kicad_pcb`
- `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/source/isolated_secondary.kicad_sch`

The copied board has 21 footprints, 62 pads, 72 track segments, 36 vias, and 0
unrouted items in the KiCad PCB Editor status bar. The runtime DRC report
`source/drc.json` records 0 DRC violations, 0 unconnected items, and 0 schematic
parity issues. The copied-project KiCad CLI rerun `source/drc-rerun.json`
records 0 DRC violations and 0 unconnected items, with 59 schematic parity
warnings; this copied-bundle parity limitation remains documented and is not a
fabrication-ready claim.

Fresh Task 512 screenshots and exports live under:

- `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/schematic-editor-screenshot.png`
- `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/pcb-editor-screenshot.png`
- `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/board-3d-viewer-screenshot.png`
- `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/layers/routed-composite.png`
- `docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/board-3d-render.png`

The public README/GitHub KiCad assets under
`docs/assets/screenshots/v2.4.0/` were refreshed from these same Task 512
captures.

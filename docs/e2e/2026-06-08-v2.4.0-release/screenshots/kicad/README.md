# KiCad Screenshot Evidence - Task 512

This bundle supersedes the Task 511 KiCad screenshots. Task 512 regenerated the
source artifacts from the final green AmpDemo PCB slice, reopened those copied
files in KiCad 10.0.3, and captured fresh editor screenshots after user review
found the prior evidence unusable.

## Source

- `source/isolated_secondary.kicad_pro`
- `source/isolated_secondary.kicad_sch`
- `source/isolated_secondary.kicad_pcb`
- `source/8FDFC0B1-C9C8-4CED-9E02-9374462932BA-component_matrix.json`
- `source/94B2FA49-5634-45BD-AB71-95C35C9E8A75-footprint_assignment.json`
- `source/drc.json`
- `source/drc-rerun.json`

## Screenshots And Exports

- `schematic-editor-screenshot.png` - copied schematic opened in KiCad
  Schematic Editor; visible connectors include `JSEC`, `JIN`, and `JSPK`.
- `pcb-editor-screenshot.png` - copied board opened in KiCad PCB Editor with
  visible routed copper; the KiCad status bar shows 62 pads, 36 vias, 72 track
  segments, 18 nets, and 0 unrouted items.
- `board-3d-viewer-screenshot.png` - copied board opened in KiCad GUI 3D
  Viewer.
- `schematic.pdf` - KiCad CLI schematic PDF export.
- `schematic-svg/isolated_secondary.svg` and
  `schematic-svg/isolated_secondary.png` - KiCad CLI schematic export and PNG
  preview.
- `layers/front-copper.svg` and `layers/front-copper.png` - front copper/layer
  export.
- `layers/back-copper.svg` and `layers/back-copper.png` - back copper/layer
  export.
- `layers/routed-composite.svg` and `layers/routed-composite.png` - combined
  routed/layer export.
- `board-3d-render.png` - deterministic KiCad CLI 3D render.

## Verification

`source/drc.json` is the runtime DRC report from the final green generated
board. It records:

- 0 DRC violations
- 0 unconnected items
- 0 schematic parity issues
- KiCad 10.0.3

`source/drc-rerun.json` is the copied-project KiCad CLI rerun. It records 0 DRC
violations and 0 unconnected items, with 59 schematic parity warnings. That
copied-bundle parity limitation is preserved as evidence and this screenshot
bundle is not a `FAB_READY` claim.

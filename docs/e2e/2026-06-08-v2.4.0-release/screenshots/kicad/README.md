# Gate 10 KiCad Screenshot Evidence

Generated on 2026-06-11 from the refreshed gate #9 `isolated_secondary`
KiCad project.

## Source

The source files copied into this evidence bundle are under `source/`:

- `isolated_secondary.kicad_pro`
- `isolated_secondary.kicad_sch`
- `isolated_secondary.kicad_pcb`
- `5D02D9BD-D039-436D-BD5E-E67B48485833-component_matrix.json`
- `634012A8-2371-4450-98B4-95AE6DE4D539-footprint_assignment.json`
- `drc.json`
- `drc-rerun.json`

Old `amp_low_voltage_audio` screenshots and source files were removed before
this bundle was regenerated.

## GUI Captures

These screenshots were captured from live KiCad 10.0.3 editor windows:

- `schematic-editor-screenshot.png`
- `pcb-editor-screenshot.png`
- `board-3d-viewer-screenshot.png`

The PCB editor screenshot shows footprints, pads, routed segments, and vias.
The 3D viewer screenshot is nonblank, but the generated footprint set does not
provide rich package bodies, so the view is mostly a flat board with small
visible pad/model markers.

## Deterministic Exports

KiCad CLI exports were generated from the same copied source:

- `schematic.pdf`
- `schematic-svg/isolated_secondary.svg`
- `schematic-svg/isolated_secondary.png`
- `layers/front-copper.svg`
- `layers/front-copper.png`
- `layers/back-copper.svg`
- `layers/back-copper.png`
- `layers/routed-composite.svg`
- `layers/routed-composite.png`
- `board-3d-render.png`
- `board-3d-render-populated.png`

## DRC Boundary

The gate #9 source DRC report copied as `source/drc.json` reports 0 violations
and 0 unconnected items.

The local KiCad CLI rerun in `source/drc-rerun.json` also reports 0 DRC
violations and 0 unconnected items, but reports 59 schematic parity warnings
against the copied screenshot project. The parity warnings are mostly symbol
field differences and schematic net-name prefix differences such as `VRAW`
versus `/VRAW`.

This gate is visual release evidence that the generated files open and render
in KiCad. It is not a `FAB_READY` fabrication claim.

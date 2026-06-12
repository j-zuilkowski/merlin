Status: complete

# Task 458b - AmpDemo PCB layout implementation

Implement the generic PCB materialization, DRC, and catalog fallback changes
needed for the AmpDemo low-voltage electronics slice to produce evidence-backed
artifacts without hard-coded schematic or PCB generators.

Acceptance:
- `kicad_compile_project` materializes placed footprints from DesignIntent,
  Circuit IR, ComponentMatrix, and FootprintAssignment evidence.
- PCB materialization keeps metadata symbols out of PCB-bound component checks
  and rejects duplicate physical refdes.
- Pads are assigned to Circuit IR nets and KiCad DRC evidence is parsed without
  accepting missing board outlines, missing footprints, or blocking violations.
- The electronics plugin exposes an optional, disabled-by-default Onsemi
  manufacturer fallback provider.
- Exact manufacturer part-number constraints reject compatible but wrong
  substitutions instead of silently selecting them.
- Focused AmpDemo schematic, PCB, DRC, SPICE smoke, BOM, fabrication, provider,
  and plugin schema tests pass.

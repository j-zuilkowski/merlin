Status: complete

# Task 457a - AmpDemo schematic synthesis tests

Add focused tests for the next electronics evidence gate: selected components and
assigned footprints must compile into a real KiCad schematic, not a functional
block sketch.

Acceptance:
- The AmpDemo schematic slice requires DesignIntent, Circuit IR, ComponentMatrix,
  and FootprintAssignment artifacts.
- The generated `.kicad_sch` parses as KiCad schematic evidence.
- Every Circuit IR refdes appears as a real KiCad symbol.
- Every selected component MPN and footprint assignment appears on its symbol.
- Nets from Circuit IR appear as schematic connectivity labels.
- A KiCad ERC report artifact is produced when KiCad CLI is available.

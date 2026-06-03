Status: complete

# Task 458a - AmpDemo PCB layout tests

Add focused tests for the PCB evidence gate after schematic synthesis.

Acceptance:
- The AmpDemo PCB slice requires DesignIntent, Circuit IR, ComponentMatrix, and
  FootprintAssignment artifacts.
- `kicad_compile_project` emits a `.kicad_pcb` with a board outline.
- Every Circuit IR component appears as a placed footprint.
- Every footprint carries the assigned footprint library ID and reference.
- Pads carry Circuit IR net names through KiCad net IDs.
- A KiCad DRC report artifact is produced when KiCad CLI is available.

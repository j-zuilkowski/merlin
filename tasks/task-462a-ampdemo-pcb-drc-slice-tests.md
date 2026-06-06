Status: complete

# Task 462a - AmpDemo PCB DRC Slice Tests

Run the constrained AmpDemo PCB/DRC backend slice without advancing to SPICE,
fabrication, BOM, screenshots, or final report.

Acceptance:
- The slice consumes evidence-backed component matrix and footprint assignment
  artifacts.
- The PCB artifact exists and embeds assigned footprints, pads, board outline,
  and Circuit IR nets.
- KiCad DRC produces a report artifact.
- The DRC report is inspected by severity and type before claiming PCB status.

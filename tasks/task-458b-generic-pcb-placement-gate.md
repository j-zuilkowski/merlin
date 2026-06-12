Status: complete

# Task 458b - Generic PCB placement gate

Replace placeholder board output for evidence-backed compile paths with generic
initial PCB placement evidence.

Acceptance:
- Board generation is driven by Circuit IR components, nets, and footprint
  assignment evidence.
- No product-specific PCB generator is added.
- Compilation blocks if the board has no outline, missing footprints, missing
  references, unplaced footprints, or pads without net evidence.
- The initial board may remain unrouted; routing is a later gate.

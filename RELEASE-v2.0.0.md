# Merlin v2.0.0 — Electronics/KiCad

Merlin v2.0 introduces a full high-stakes electronics workflow centered on KiCad artifact generation, policy enforcement, and operator signoff.

## Highlights

- Added the `merlin-kicad-mcp` tooling boundary with strict capability and prompt contracts.
- Introduced KiCad schematic/project contracts for deterministic artifact handling.
- Added FreeRouting-backed routing policy with controlled net-class and placement assumptions.
- Enforced hard verification gates for ERC, DRC, parity, and connectivity checks.
- Added SPICE model policy, including explicit warnings when generic substitutes are used.
- Added fabrication, BOM, vendor, and order-approval policy boundaries to block unsafe execution.
- Added explicit high-stakes signoff boundaries so irreversible manufacturing actions require human approval.

## Scope

This release focuses on safe orchestration and policy-constrained execution for electronics build pipelines, from schematic interpretation through routing, verification, BOM/vendor workflows, and final release readiness.

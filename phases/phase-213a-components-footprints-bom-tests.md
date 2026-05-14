# Phase 213a — Components, Footprints, Libraries, and BOM Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 212b complete: extraction policy and clarification planning exist.

New surface introduced in phase 213b:
  - `FootprintAssignmentPolicy`
  - `ComponentLibraryPolicy`
  - `LibraryVerificationPolicy`
  - `NormalizedBOMBuilder`
  - `VendorSourcePolicy`

TDD coverage:
  File 1 — `ComponentsFootprintsBOMTests`: footprint source priority, unknown footprint block, generated library verification, KiCad field to BOM mapping, substitution approval requirement, vendor source list

---

## Write to: MerlinTests/Unit/ComponentsFootprintsBOMTests.swift

Cover:

1. footprint priority: existing KiCad field, exact MPN, package constraint, project default, user clarification
2. `unknown_footprints > 0` blocks PCB synthesis
3. generated symbols/footprints require pin-count/pin-name/pad-number/package-dimension checks
4. KiCad fields map to `NormalizedBOM`: RefDes, value, footprint, manufacturer, MPN, vendor SKUs, quantity, DNP, lifecycle, substitutions
5. substitutions never silently change package/electrical/lifecycle-critical fields
6. vendor source policy includes Digi-Key, Mouser, Arrow, Newark/Farnell/element14, LCSC, Parts Express

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with missing component/footprint/BOM policy symbols.

## Commit

```bash
git add MerlinTests/Unit/ComponentsFootprintsBOMTests.swift
git commit -m "Phase 213a — ComponentsFootprintsBOMTests (failing)"
```

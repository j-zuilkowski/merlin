# Task 216a — Vendor Order and Electronics Approval Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 215b complete: verification/fabrication policies exist.

New surface introduced in task 216b:
  - `VendorBOMAdapter`
  - `VendorCatalog`
  - `VendorOrderPolicy`
  - `ElectronicsApprovalRequest`
  - `ElectronicsApprovalKind`
  - `ElectronicsApprovalEvaluator`

TDD coverage:
  File 1 — `VendorOrderApprovalTests`: vendor list, native BOM export contract, pricing/order prep/order submit gates, purchase limits, approval kinds, no full payment storage

---

## Write to: MerlinTests/Unit/VendorOrderApprovalTests.swift

Cover:

1. vendor catalog includes Digi-Key, Mouser, Arrow, Newark/Farnell/element14, LCSC, Parts Express
2. every vendor has a native BOM export adapter contract
3. pricing/availability lookup can return advisory results without approving substitutions
4. order prep does not submit
5. order submission requires explicit `order_submission` approval
6. purchase limit blocks over-threshold orders
7. approval kinds include clarification, high-stakes signoff, profile change, substitution, order submission, library generation
8. order summary stores payment alias only, not full payment details

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with missing vendor/order/approval symbols.

## Commit

```bash
git add MerlinTests/Unit/VendorOrderApprovalTests.swift
git commit -m "Task 216a — VendorOrderApprovalTests (failing)"
```

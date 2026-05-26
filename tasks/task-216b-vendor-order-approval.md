# Task 216b — Vendor Order and Electronics Approval

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 216a complete: failing vendor/order/approval tests exist.

---

## Add: Merlin/Electronics/VendorOrderApproval.swift

Implement:

1. `VendorBOMAdapter`
2. `VendorCatalog`
3. `VendorOrderPolicy`
4. `VendorOrderPreparation`
5. `VendorOrderSubmissionPolicy`
6. `ElectronicsApprovalKind`
7. `ElectronicsApprovalRequest`
8. `ElectronicsApprovalEvaluator`

No real vendor network calls or order submission in this task.

Rules:

1. default flow prepares carts/orders only
2. submission requires explicit approval
3. credentials/tokens are not stored here; later connector  tasks use Keychain
4. full payment details are never persisted

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `VendorOrderApprovalTests` pass.

## Commit

```bash
git add Merlin/Electronics/VendorOrderApproval.swift
git commit -m "Task 216b — vendor BOM order and electronics approval policy"
```

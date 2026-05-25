# Phase 339a — Slot Status Panel Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 338b complete: llama.cpp is a first-class local router provider.

Recommended execution model: GPT-5.3-Codex.

The main window currently exposes provider inventory as a top-of-chat indicator.
That is misleading because Merlin routes work through four configured slots:
execute, reason, orchestrate, and vision. A configured provider in Settings must
not appear as active routing unless one or more slots are explicitly assigned.

New surface introduced in phase 339b:
  - A compact `SlotStatusPanel` in the lower-left sidebar, below sessions and
    above New Project Workspace.
  - Four persistent rows: Execute, Reason, Orchestrate, Vision.
  - Unconfigured rows remain visible, greyed out, and labelled `Not configured`.
  - Rows are driven only by explicit slot assignments, never provider enablement,
    `activeProviderID`, primary-provider fallback, or internal fallback rules.
  - The top-of-chat provider routing badge is removed.

TDD coverage:
  File 1 - `MerlinTests/Unit/SlotStatusResolverTests.swift`:
    `testNoAssignmentsReturnsFourGreyNotConfiguredRows` - all four rows are
    present in stable order and labelled `Not configured`.
    `testProviderInventoryDoesNotPopulateRows` - enabled/default/active provider
    state is ignored when slots are empty.
    `testPartialAssignmentsOnlyPopulateAssignedRows` - assigning execute only
    leaves reason, orchestrate, and vision unconfigured.
    `testReasonAssignmentDoesNotPopulateOrchestrateFallbackDisplay` - internal
    fallback does not make orchestrate look configured.
    `testExecuteAssignmentDoesNotPopulateUnassignedSlots` - execute fallback
    does not make unassigned slots look configured.
    `testVirtualProviderIDsUseRegistryDisplayName` - virtual IDs such as
    `llamacpp:qwen3-coder` render with the registry display name.
    `testRowsHaveStableAccessibilityIdentifiers` - panel and row IDs are stable
    for UI testing.

  File 2 - `MerlinTests/Unit/AccessibilityIDCoverageTests.swift`:
    Add the new slot-status accessibility identifiers to the required coverage
    list if this test centrally enumerates expected IDs.

---

## Write to: MerlinTests/Unit/SlotStatusResolverTests.swift

Test a pure resolver/model layer rather than snapshotting SwiftUI pixels. The
resolver should accept explicit slot assignments plus a display-name closure
and return four row models.

Expected row model shape:

```swift
struct SlotStatusRowModel: Equatable, Identifiable {
    enum State: Equatable { case configured, notConfigured }
    let id: ProviderSlot
    let title: String
    let value: String
    let state: State
    let accessibilityID: String
}
```

The tests must prove the resolver has no input for active provider or provider
enablement. Provider inventory belongs to Settings; slot status belongs to
explicit routing assignments.

## Edit: MerlinTests/Unit/AccessibilityIDCoverageTests.swift

Add expectations for:

- `slotStatusPanel`
- `slotStatusRowPrefix`
- any value/label identifiers introduced by the implementation

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD FAILED with errors naming missing `SlotStatusResolver`,
`SlotStatusRowModel`, `SlotStatusPanel`, and/or slot-status accessibility IDs.

## Commit
```bash
git add MerlinTests/Unit/SlotStatusResolverTests.swift \
        MerlinTests/Unit/AccessibilityIDCoverageTests.swift \
        tasks/task-339a-slot-status-panel-tests.md
git commit -m "Phase 339a — slot status panel tests (failing)"
```

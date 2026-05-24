# Phase 339b — Slot Status Panel Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 339a complete: slot status panel tests are failing for the new surface.

Recommended execution model: GPT-5.3-Codex.

Implement the slot/provider UI correction: provider inventory remains configured
in Settings, while the main workspace shows only explicit slot routing state.

---

## Write to: Merlin/Views/SlotStatusPanel.swift

Add a compact SwiftUI panel for the lower-left sidebar.

Required behavior:

- Always renders four rows in this order: Execute, Reason, Orchestrate, Vision.
- Each row is derived only from `AppSettings.slotAssignments`.
- Unassigned rows are visible, greyed out, and labelled `Not configured`.
- Assigned rows show `ProviderRegistry.displayName(for:)` for the assigned
  provider ID, including virtual IDs such as `llamacpp:qwen3-coder`.
- Do not display active provider, primary provider, provider enablement,
  provider API-key state, or fallback-derived values.
- Keep the panel compact enough for the sidebar: small title, dense rows, no
  card-inside-card layout, no instructional copy.

Recommended structure:

- `SlotStatusRowModel`
- `SlotStatusResolver`
- `SlotStatusPanel`

Make the resolver independent from SwiftUI so the tests from 339a can cover the
routing display rules without view introspection.

## Edit: Merlin/Views/SessionSidebar.swift

Mount `SlotStatusPanel` below the sessions list and above the
`New Project Workspace` button. Preserve the existing bottom button placement
and spacing. The slot panel should remain visible even when there are no
sessions.

## Edit: Merlin/Views/ChatView.swift and Merlin/Views/ProviderHUD.swift

Remove the top-of-chat provider routing indicator. If `ProviderHUD` is still
needed for unrelated context/thinking state, strip its provider selector/display
behavior. If it only exists for provider display, stop mounting it.

After this phase, selecting or enabling a provider in Settings must not create
any main-screen provider badge or slot status row by itself.

## Edit: Merlin/Support/AccessibilityID.swift

Add stable IDs for the new panel and rows:

- `slotStatusPanel`
- `slotStatusRowPrefix`

Add value/label IDs only if the SwiftUI implementation needs them for clear
tests. Keep naming consistent with existing accessibility constants.

## Edit: Immediate Slot UI Documentation

Update documentation directly coupled to the UI move:

- `README.md` - describe slot routing as the main routing state and remove any
  implication that provider inventory is selected from the top chat area.
- `FEATURES.md` - replace "switch mid-session from the toolbar" with explicit
  slot routing through Settings and the sidebar slot status panel.
- `Merlin/Docs/UserGuide.md` - remove the ProviderHUD/top-of-chat provider
  instructions; document the lower-left slot status panel, the four rows, and
  the `Not configured` state.
- `Merlin/Docs/DeveloperManual.md` - add `SlotStatusPanel`,
  `SlotStatusResolver`, explicit-slot-only display rules, and the fact that
  `ProviderHUD` no longer owns provider routing display.
- `merlin-eval/scenarios/S9-panels.md` - replace ProviderHUD assertions with
  slot status panel assertions.
- `merlin-eval/scenarios/S13-providers-connectors.md` - update provider count
  and assert provider inventory does not populate routing rows unless slots are
  assigned.
- `merlin-eval/SURFACE-CENSUS.md` and `merlin-eval/SURFACE-INVENTORY.md` -
  replace current ProviderHUD surface references with SlotStatusPanel where
  they describe current UI.
- `phases/SURFACE-INVENTORY.md` - update current surface inventory if it is
  still used as a living checklist.

Leave old phase files, release notes, and dated handoff snapshots alone unless
they are being regenerated as current aggregate docs.

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```
Expected: all unit tests pass, including the new slot-status resolver tests
from 339a.

```bash
xcodebuild -scheme MerlinTests-Live build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head
```
Expected: `** TEST BUILD SUCCEEDED **`.

## Manual UI Check

Launch Merlin and confirm:

- With no slot assignments, the sidebar shows Execute, Reason, Orchestrate, and
  Vision as grey `Not configured` rows.
- Enabling or selecting providers in Settings does not populate the rows.
- Assigning only execute populates only Execute.
- Assigning reason does not make Orchestrate appear configured.
- The old top-of-chat provider routing badge is absent.

## Commit
```bash
git add Merlin/Views/SlotStatusPanel.swift \
        Merlin/Views/SessionSidebar.swift \
        Merlin/Views/ChatView.swift \
        Merlin/Views/ProviderHUD.swift \
        Merlin/Support/AccessibilityID.swift \
        README.md \
        FEATURES.md \
        Merlin/Docs/UserGuide.md \
        Merlin/Docs/DeveloperManual.md \
        merlin-eval/scenarios/S9-panels.md \
        merlin-eval/scenarios/S13-providers-connectors.md \
        merlin-eval/SURFACE-CENSUS.md \
        merlin-eval/SURFACE-INVENTORY.md \
        phases/SURFACE-INVENTORY.md \
        MerlinTests/Unit/SlotStatusResolverTests.swift \
        MerlinTests/Unit/AccessibilityIDCoverageTests.swift \
        phases/phase-339b-slot-status-panel.md
git commit -m "Phase 339b — move routing status to sidebar slot panel"
```

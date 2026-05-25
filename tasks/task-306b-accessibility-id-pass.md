# Task 306b — Accessibility-Identifier Pass (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 306a complete: failing tests in `AccessibilityIDCoverageTests`.

Goal: every interactive control in Merlin is addressable by XCUITest. This is a broad,
mechanical pass driven by the catalogue in `tasks/SURFACE-INVENTORY.md`.

## Edit: Merlin/Support/AccessibilityID.swift
Extend the `AccessibilityID` namespace with a stable, unique constant for every
interactive control enumerated in `SURFACE-INVENTORY.md` sections A–R. Use a consistent
scheme, e.g. `settings.<pane>.<control>`, `menu.<command>`, `panel.<panel>.<control>`,
`dialog.<dialog>.<control>`, `chat.<control>`. At minimum declare the representative
constants named in task 306a.

## Edit: across Merlin/Views, Merlin/UI, Merlin/App
Apply `.accessibilityIdentifier(AccessibilityID.<name>)` to every interactive control:
- All ~90 controls in the 17 settings panes (`SettingsWindowView.swift` + per-pane views).
- The menu commands (set identifiers where SwiftUI allows; otherwise rely on menu-item
  titles, which XCUITest can match — document which approach per command).
- Every workspace panel's controls (sidebar rows, tool-log clear, terminal input/run,
  diff accept/reject, file-pane controls, preview controls, side-chat controls).
- Every dialog/sheet/popover's controls (auth popup, tool-requirement, project picker,
  memory review, calibration, first-launch, etc.).
- The chat input surfaces (attachment, voice, send/stop, mic, mention/skills pickers).

Work pane-by-pane and panel-by-panel; commit is one task but the edit is large — keep
it mechanical and do not change any behaviour, only add identifiers.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:MerlinTests/AccessibilityIDCoverageTests
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD SUCCEEDED, zero warnings, `AccessibilityIDCoverageTests` passes.

Cross-check: every interactive row in `SURFACE-INVENTORY.md` sections A–R has a
corresponding `AccessibilityID` constant. Any control that genuinely cannot take an
identifier (e.g. a system menu) is noted in the task doc.

## Executor Notes

- The surface catalogue is `tasks/SURFACE-INVENTORY.md` (in-repo). It was absent from
  the checkout during the original execution of this task, so the pass was driven from
  the actual SwiftUI control surface under `Merlin/Views`, `Merlin/UI`, and `Merlin/App`
  plus the representative constants from task 306a. A future rebuild has the catalogue
  available and should cross-check against it.
- SwiftUI `Commands` menu items in `Merlin/App/MerlinCommands.swift` are system menu
  entries; they are intentionally addressed by visible menu-item titles in XCUITest
  rather than `.accessibilityIdentifier`.

## Commit
```
git add Merlin/Support/AccessibilityID.swift Merlin/Views Merlin/UI Merlin/App \
  tasks/task-306b-accessibility-id-pass.md
git commit -m "Task 306b — Accessibility-identifier pass across the UI surface"
```

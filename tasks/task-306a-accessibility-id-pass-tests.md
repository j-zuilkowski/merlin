# Phase 306a — Accessibility-Identifier Pass Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.

The eval suite's surface scenarios (S7–S11) drive Merlin's UI via XCUITest, which finds
elements by accessibility identifier. Today only ~5 controls have an
`.accessibilityIdentifier` (`AccessibilityID.chatInput`, `.sessionList`,
`.newSessionButton`, `.settingsButton`, chat send/cancel). Every interactive control
across the 17 settings panes, the menus, the panels, and the dialogs must be addressable.

Phase 306b adds an `accessibilityIdentifier` to every interactive control, with stable
names declared as constants in `Merlin/Support/AccessibilityID.swift`.

TDD coverage: `MerlinTests/Unit/AccessibilityIDCoverageTests.swift` — asserts the
`AccessibilityID` namespace declares identifiers for a representative control in every
settings pane and every panel (the constants must exist and be unique). This pins the
naming surface; the exhaustive wiring is verified by S7–S11 at proving time.

## Write to: MerlinTests/Unit/AccessibilityIDCoverageTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 306a — failing tests for the accessibility-identifier namespace.
final class AccessibilityIDCoverageTests: XCTestCase {

    /// One representative identifier per settings pane + per panel. 306b adds these
    /// constants to AccessibilityID and wires them onto the real controls.
    func testRepresentativeIdentifiersAreDeclared() {
        let ids: [String] = [
            // settings panes
            AccessibilityID.settingsGeneralKeepAwakeToggle,
            AccessibilityID.settingsProvidersRefreshButton,
            AccessibilityID.settingsRoleSlotsPickerPrefix,
            AccessibilityID.settingsHooksAddButton,
            AccessibilityID.settingsConnectorsSaveButton,
            AccessibilityID.settingsLoRAEnableToggle,
            AccessibilityID.settingsAdvancedResetButton,
            // panels
            AccessibilityID.terminalPaneInput,
            AccessibilityID.toolLogClearButton,
            AccessibilityID.diffPaneAcceptAllButton,
            AccessibilityID.memoryBrowserSearchField,
        ]
        // Every identifier is non-empty and unique.
        XCTAssertTrue(ids.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(ids).count, ids.count, "identifiers must be unique")
    }
}
```

NOTE for executor: the exact constant names above are a starting set — 306b may rename
them, but every name referenced here must exist as an `AccessibilityID` constant. The
full identifier list is driven by `tasks/SURFACE-INVENTORY.md`.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD FAILED — the `AccessibilityID` constants do not exist.

## Commit
```
git add MerlinTests/Unit/AccessibilityIDCoverageTests.swift tasks/task-306a-accessibility-id-pass-tests.md
git commit -m "Phase 306a — Accessibility-identifier pass tests (failing)"
```

# Phase 325a — AccessibilityID Gap-Fill Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 324b complete: TaskScanner symbol-matching accuracy landed.

The W5 surface census (`merlin-eval/SURFACE-CENSUS.md` §1.2) found **12 interactive
controls with no `AccessibilityID`** — the task-306 pass missed them. XCUITest (eval
scenarios S7–S11) cannot reach a control without an identifier, so these are untestable
surface. The 12:
  - 6 `WorkspaceView` toolbar toggles — Staged Changes, File Viewer, Terminal, Preview,
    Side Chat, Memories
  - `ScreenPreviewView` expand/collapse button
  - `PreviewPane` close button
  - `ToolRequirementSheet` — Install with Homebrew, Cancel, Done
  - `AdvisoryRow` "Fix this" button (the performance-dashboard pane's only control)

New surface introduced in phase 325b:
  - `AccessibilityID.workspaceToggleDiffButton` / `…FileButton` / `…TerminalButton` /
    `…PreviewButton` / `…SideChatButton` / `…MemoriesButton` — the 6 toolbar toggles
  - `AccessibilityID.screenPreviewToggleButton` — ScreenPreviewView header button
  - `AccessibilityID.previewPaneCloseButton` — PreviewPane close button
  - `AccessibilityID.toolRequirementInstallButton` / `…CancelButton` / `…DoneButton`
  - `AccessibilityID.performanceAdvisoryApplyButtonPrefix` — AdvisoryRow "Fix this"

TDD coverage: `MerlinTests/Unit/AccessibilityIDCoverageTests.swift` — a new test asserts
all 12 constants are declared, non-empty, and unique.

**This is a compile-failure phase.** The new test references 12 `AccessibilityID`
members that do not exist until 325b. Verify with `build-for-testing` — expect
BUILD FAILED naming the missing members.

---

## Write to: MerlinTests/Unit/AccessibilityIDCoverageTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 306a — failing tests for the accessibility-identifier namespace.
/// Phase 325a extends it for the 12 controls the task-306 pass missed.
final class AccessibilityIDCoverageTests: XCTestCase {

    /// One representative identifier per settings pane + per panel.
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

    /// Phase 325 — the 12 controls the task-306 pass missed (W5 surface-census §1.2):
    /// the 6 WorkspaceView toolbar toggles, the ScreenPreview + PreviewPane buttons,
    /// the 3 ToolRequirementSheet buttons, and the performance-dashboard advisory button.
    func testPhase325IdentifiersAreDeclared() {
        let ids: [String] = [
            AccessibilityID.workspaceToggleDiffButton,
            AccessibilityID.workspaceToggleFileButton,
            AccessibilityID.workspaceToggleTerminalButton,
            AccessibilityID.workspaceTogglePreviewButton,
            AccessibilityID.workspaceToggleSideChatButton,
            AccessibilityID.workspaceToggleMemoriesButton,
            AccessibilityID.screenPreviewToggleButton,
            AccessibilityID.previewPaneCloseButton,
            AccessibilityID.toolRequirementInstallButton,
            AccessibilityID.toolRequirementCancelButton,
            AccessibilityID.toolRequirementDoneButton,
        ]
        XCTAssertTrue(ids.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(ids).count, ids.count, "identifiers must be unique")
        XCTAssertTrue(
            AccessibilityID.performanceAdvisoryApplyButtonPrefix.hasSuffix("-"),
            "a prefix identifier must end with '-' so the suffixed value reads cleanly")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD FAILED** — errors naming the 12 missing `AccessibilityID` members
(`workspaceToggleDiffButton` … `performanceAdvisoryApplyButtonPrefix`). Verified with
`build-for-testing` because the failure is at compile time.

## Commit
```
git add MerlinTests/Unit/AccessibilityIDCoverageTests.swift tasks/task-325a-accessibility-id-gap-tests.md
git commit -m "Phase 325a — AccessibilityID gap-fill tests (failing)"
```

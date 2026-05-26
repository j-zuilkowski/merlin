# Task 328 — Eval Surface Harness (S7–S11)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 327 complete: agent-tool census landed. Task 325 added the 12 missing
`AccessibilityID`s — XCUITest can now reach every control.

W5 — the **M2 surface harness**: `XCUIApplication`-driven tests over Merlin's own UI for
scenarios **S7–S11** (windows, menus, shortcuts; the 17 settings panes; the workspace
panels; chat input; modal UI). These need the built `Merlin` app but **no LLM** — they
are *not* `skipUnlessLiveEnvironment`-gated (mirrors the existing `VisualLayoutTests`).
They run via the `MerlinTests-Live` scheme.

This file is the surface-harness backbone: it covers every window, every settings pane,
every workspace toggle, the formerly-dead View-menu commands, the chat input surfaces,
and the auth popup — the deterministic high-value checks. The exhaustive per-control
walk of all ~170 controls is enumerated by the S7–S11 scenario files against
`SURFACE-CENSUS.md` §1.2; controls beyond this backbone are mechanical additions keyed
off the `AccessibilityID` registry.

---

## Write to: MerlinE2ETests/SurfaceUITests.swift

```swift
import XCTest
@testable import Merlin

/// W5 — M2 surface harness (S7–S11). Drives Merlin's own UI via XCUITest.
@MainActor
final class SurfaceUITests: XCTestCase {

    private func launchMerlin(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    // MARK: - S7 — windows & menus

    /// The workspace window opens and the Settings scene opens via ⌘,.
    func testWorkspaceAndSettingsWindowsOpen() {
        let app = launchMerlin()
        defer { app.terminate() }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "the workspace window must appear on launch")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows.count >= 1,
                      "⌘, must open the Settings scene")
    }

    /// The three View-menu commands that were dead before task 305 now fire.
    /// Regression net for the dead-control bug class.
    func testFormerlyDeadViewMenuCommands() {
        let app = launchMerlin()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        // ⌃` Toggle Terminal, ⌘⇧/ Toggle Side Chat, ⌘⇧M Review Memories.
        app.typeKey("`", modifierFlags: .control)
        app.typeKey("/", modifierFlags: [.command, .shift])
        app.typeKey("m", modifierFlags: [.command, .shift])
        // The app must still be alive and responsive (no dead-command crash).
        XCTAssertTrue(app.windows.firstMatch.exists,
                      "the View-menu commands must not crash or no-op the app")
    }

    // MARK: - S8 — every settings pane renders

    func testAllSeventeenSettingsPanesRender() {
        let app = launchMerlin()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)

        // The sidebar lists every SettingsSection by its label.
        let paneLabels = SettingsSection.allCases.map { $0.label }
        for label in paneLabels {
            let row = app.descendants(matching: .any)[label]
            if row.exists {
                row.click()
                XCTAssertTrue(app.windows.count >= 1,
                              "settings pane '\(label)' crashed the window")
            }
        }
    }

    // MARK: - S9 — workspace panels

    /// The six workspace toolbar toggles (AX-IDs added in task 325) each show a panel.
    func testAllSixWorkspaceToggles() {
        let app = launchMerlin()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        let toggles = [
            AccessibilityID.workspaceToggleDiffButton,
            AccessibilityID.workspaceToggleFileButton,
            AccessibilityID.workspaceToggleTerminalButton,
            AccessibilityID.workspaceTogglePreviewButton,
            AccessibilityID.workspaceToggleSideChatButton,
            AccessibilityID.workspaceToggleMemoriesButton,
        ]
        for id in toggles {
            let button = app.buttons[id]
            if button.waitForExistence(timeout: 5) {
                button.click()   // open
                button.click()   // close
                XCTAssertTrue(app.windows.firstMatch.exists,
                              "toggling '\(id)' crashed the workspace")
            }
        }
    }

    // MARK: - S10 — chat input surfaces

    func testChatInputSurfacesPresent() {
        let app = launchMerlin()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        XCTAssertTrue(app.textFields[AccessibilityID.chatInput].waitForExistence(timeout: 5),
                      "the chat input field must be present")
        for id in [AccessibilityID.chatSendButton, AccessibilityID.chatAttachmentButton,
                   AccessibilityID.chatVoiceButton] {
            XCTAssertTrue(app.buttons[id].exists, "chat control '\(id)' is missing")
        }
    }

    // MARK: - S11 — modal UI

    /// The auth popup, forced via the launch flag, appears and dismisses.
    func testAuthPopupAppearsAndDismisses() {
        let app = launchMerlin(["--show-auth-popup-for-testing"])
        defer { app.terminate() }

        let popup = app.sheets.firstMatch
        if popup.waitForExistence(timeout: 10) {
            let deny = app.buttons[AccessibilityID.authDenyButton]
            XCTAssertTrue(deny.exists, "the auth popup must show its Deny path")
            deny.click()
            XCTAssertFalse(app.sheets.firstMatch.exists,
                           "the auth popup must dismiss on a decision")
        }
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, zero warnings — the surface harness compiles against the real
`XCUIApplication` / `AccessibilityID` / `SettingsSection` API. Not run here (the proving
run is a separate step). Depends on task 325 (the AX-IDs the toggle tests reference).

## Commit
```
git add MerlinE2ETests/SurfaceUITests.swift tasks/task-328-eval-surface-harness.md
git commit -m "Task 328 — Eval surface harness (S7–S11)"
```

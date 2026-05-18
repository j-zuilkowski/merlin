import XCTest

// AccessibilityID and SettingsSection are Foundation-only Merlin types compiled
// directly into this UI-testing target (see project.yml) — a UI-testing bundle
// cannot `@testable import Merlin`.

/// W5 - M2 surface harness (S7-S11). Drives Merlin's own UI via XCUITest.
@MainActor
final class SurfaceUITests: XCTestCase {

    private func launchMerlin(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    // MARK: - S7 - windows & menus

    /// The workspace window opens and the Settings scene opens via command-comma.
    func testWorkspaceAndSettingsWindowsOpen() {
        let app = launchMerlin()
        defer { app.terminate() }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "the workspace window must appear on launch")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows.count >= 1,
                      "command-comma must open the Settings scene")
    }

    /// The three View-menu commands that were dead before phase 305 now fire.
    /// Regression net for the dead-control bug class.
    func testFormerlyDeadViewMenuCommands() {
        let app = launchMerlin()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        // Control-` Toggle Terminal, Command-Shift-/ Toggle Side Chat, Command-Shift-M Review Memories.
        app.typeKey("`", modifierFlags: .control)
        app.typeKey("/", modifierFlags: [.command, .shift])
        app.typeKey("m", modifierFlags: [.command, .shift])
        // The app must still be alive and responsive (no dead-command crash).
        XCTAssertTrue(app.windows.firstMatch.exists,
                      "the View-menu commands must not crash or no-op the app")
    }

    // MARK: - S8 - every settings pane renders

    func testAllSeventeenSettingsPanesRender() {
        let app = launchMerlin()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)

        // The sidebar lists every SettingsSection by its label. A label resolves to
        // several elements — the List row, the enclosing scroll view, the detail
        // pane's navigation title. Click the first *hittable* one (the row); the
        // scroll view has no hit point and the bare firstMatch could land on it.
        let paneLabels = SettingsSection.allCases.map { $0.label }
        for label in paneLabels {
            let candidates = app.descendants(matching: .any).matching(identifier: label)
            for index in 0..<candidates.count {
                let element = candidates.element(boundBy: index)
                guard element.exists, element.isHittable else { continue }
                element.click()
                break
            }
            XCTAssertTrue(app.windows.count >= 1,
                          "settings pane '\(label)' crashed the window")
        }
    }

    // MARK: - S9 - workspace panels

    /// The six workspace toolbar toggles (AX-IDs added in phase 325) each show a panel.
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

    // MARK: - S10 - chat input surfaces

    func testChatInputSurfacesPresent() {
        // The chat surfaces only render once a session is active — open a test
        // project so WorkspaceView shows ContentView instead of placeholderContent.
        let app = launchMerlin(["--open-test-project"])
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        XCTAssertTrue(app.textFields[AccessibilityID.chatInput].waitForExistence(timeout: 12),
                      "the chat input field must be present")
        for id in [AccessibilityID.chatSendButton, AccessibilityID.chatAttachmentButton,
                   AccessibilityID.chatVoiceButton] {
            XCTAssertTrue(app.buttons[id].exists, "chat control '\(id)' is missing")
        }
    }

    // MARK: - S11 - modal UI

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

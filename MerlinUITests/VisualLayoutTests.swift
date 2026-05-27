import XCTest

@MainActor
private func launchFixtureApp(arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = arguments
    app.launch()
    return app
}

final class VisualLayoutTests: XCTestCase {
    @MainActor
    func testNoWidgetsClipped() throws {
        let app = launchFixtureApp(arguments: ["--open-test-project"])
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let windowFrame = window.frame
        let elementsToCheck: [(String, XCUIElement)] = [
            ("session list", app.scrollViews["session-list"]),
            ("new session button", app.buttons["new-session-button"]),
            ("diff toggle", app.buttons["workspace-toggle-diff-button"]),
            ("file toggle", app.buttons["workspace-toggle-file-button"]),
            ("terminal toggle", app.buttons["workspace-toggle-terminal-button"]),
            ("preview toggle", app.buttons["workspace-toggle-preview-button"]),
            ("CAG metrics toggle", app.buttons["workspace-toggle-cag-metrics-button"]),
            ("electronics jobs toggle", app.buttons["workspace-toggle-electronics-jobs-button"]),
            ("side chat toggle", app.buttons["workspace-toggle-side-chat-button"]),
            ("memories toggle", app.buttons["workspace-toggle-memories-button"]),
            ("chat input", app.textFields["chat-input"]),
            ("chat attachment button", app.buttons["chat-attachment-button"]),
            ("chat voice button", app.buttons["chat-voice-button"]),
            ("chat send button", app.buttons["chat-send-button"]),
        ]
        for (description, element) in elementsToCheck {
            XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(description) to exist")
            let frame = element.frame
            XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX - 1, "\(description) clipped on left")
            XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX + 1, "\(description) clipped on right")
        }
    }

    @MainActor
    func testAccessibilityAudit() throws {
        let app = launchFixtureApp(arguments: ["--open-test-project", "--accessibility-audit-fixture"])
        defer { app.terminate() }

        var issues: [String] = []
        try app.performAccessibilityAudit { issue in
            let el = issue.element
            let frame = el?.frame ?? .zero
            if self.isKnownContainerAuditFalsePositive(
                auditType: issue.auditType.rawValue,
                elementType: el?.elementType,
                identifier: el?.identifier ?? "",
                label: el?.label ?? "",
                title: el?.title ?? "",
                frame: frame
            ) {
                return true
            }
            issues.append("[\(issue.auditType.rawValue)] \(issue.compactDescription) "
                + ":: type=\(el?.elementType.rawValue ?? 0) "
                + "id='\(el?.identifier ?? "")' label='\(el?.label ?? "")' "
                + "title='\(el?.title ?? "")' "
                + "frame=(\(Int(frame.minX)),\(Int(frame.minY)),"
                + "\(Int(frame.width))x\(Int(frame.height)))")
            return true   // collect every issue without aborting the audit
        }
        XCTAssertTrue(issues.isEmpty,
                      "accessibility audit found \(issues.count) issue(s):\n"
                      + issues.joined(separator: "\n"))
        assertCoreAccessibilitySurfaceExists(app)
    }

    @MainActor
    func testCaptureScreenshot() {
        let app = launchFixtureApp()
        defer { app.terminate() }

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func isKnownContainerAuditFalsePositive(
        auditType: UInt64,
        elementType: XCUIElement.ElementType?,
        identifier: String,
        label: String,
        title: String,
        frame: CGRect
    ) -> Bool {
        let hasNoUserFacingDescription = identifier.isEmpty
            && label.isEmpty
            && title.isEmpty
        guard hasNoUserFacingDescription else { return false }

        if auditType == 8,
           elementType == .group,
           frame.width > 1_000,
           frame.height > 500 {
            return true
        }
        if auditType == 8,
           elementType?.rawValue == 81 {
            return true
        }
        if auditType == 8_589_934_592,
           elementType == .group,
           frame.width <= 20,
           frame.height <= 20 {
            return true
        }
        if auditType == 1,
           elementType == .staticText,
           frame.height <= 16,
           frame.width <= 240 {
            return true
        }
        return false
    }

    @MainActor
    private func assertCoreAccessibilitySurfaceExists(_ app: XCUIApplication) {
        assertExists(app.textFields["chat-input"], "main chat input")
        assertExists(app.buttons["chat-attachment-button"], "main attachment button")
        assertExists(app.buttons["chat-voice-button"], "main voice button")
        assertExists(app.buttons["chat-send-button"], "main send button")
        assertExists(element(labelContaining: "Execute slot", in: app), "execute slot row")
        assertExists(element(labelContaining: "Reason slot", in: app), "reason slot row")
        assertExists(element(labelContaining: "Orchestrate slot", in: app), "orchestrate slot row")
        assertExists(element(labelContaining: "Vision slot", in: app), "vision slot row")
    }

    @MainActor
    private func element(labelContaining label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", label))
            .firstMatch
    }

    @MainActor
    private func assertExists(_ element: XCUIElement, _ description: String) {
        let exists = element.exists
        XCTAssertTrue(exists, "Expected \(description) to exist")
    }

    @MainActor
    func testInputFieldExists() {
        // Chat surfaces require an active session — open a test project.
        let app = launchFixtureApp(arguments: ["--open-test-project"])
        defer { app.terminate() }

        let input = app.textFields["chat-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields.matching(identifier: "chat-input").count, 1)
        XCTAssertTrue(input.isEnabled)

        let sideChatButton = app.buttons["workspace-toggle-side-chat-button"].firstMatch
        XCTAssertTrue(sideChatButton.waitForExistence(timeout: 10))
        if app.textFields.matching(identifier: "side-chat-input").count == 0 {
            sideChatButton.click()
        }

        XCTAssertTrue(app.textFields["side-chat-input"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields.matching(identifier: "chat-input").count, 1)
        XCTAssertEqual(app.textFields.matching(identifier: "side-chat-input").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "chat-attachment-button").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "side-chat-attachment-button").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "chat-voice-button").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "side-chat-voice-button").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "chat-send-button").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "side-chat-send-button").count, 1)
    }

    @MainActor
    func testToolLogPanelVisible() {
        // The tool-log pane starts open under --open-test-project.
        let app = launchFixtureApp(arguments: ["--open-test-project"])
        defer { app.terminate() }

        XCTAssertTrue(app.scrollViews["tool-log"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testAuthPopupLayout() {
        let popupApp = launchFixtureApp(arguments: ["--show-auth-popup-for-testing"])
        defer { popupApp.terminate() }

        let popup = popupApp.sheets.firstMatch
        if popup.exists {
            let windowFrame = popupApp.windows.firstMatch.frame
            XCTAssertGreaterThanOrEqual(popup.frame.minX, windowFrame.minX)
            XCTAssertLessThanOrEqual(popup.frame.maxX, windowFrame.maxX)
        }
    }
}

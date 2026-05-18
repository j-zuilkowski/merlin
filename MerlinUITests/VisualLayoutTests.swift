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
        let app = launchFixtureApp()
        defer { app.terminate() }

        let windowFrame = app.windows.firstMatch.frame
        for element in app.windows.firstMatch.descendants(matching: .any).allElementsBoundByIndex {
            guard element.exists, element.isHittable else { continue }
            let frame = element.frame
            let identifier = element.identifier
            XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX - 1, "\(identifier) clipped on left")
            XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX + 1, "\(identifier) clipped on right")
        }
    }

    @MainActor
    func testAccessibilityAudit() throws {
        let app = launchFixtureApp(arguments: ["--open-test-project"])
        defer { app.terminate() }

        var issues: [String] = []
        try app.performAccessibilityAudit { issue in
            let el = issue.element
            let frame = el?.frame ?? .zero
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
    func testInputFieldExists() {
        // Chat surfaces require an active session — open a test project.
        let app = launchFixtureApp(arguments: ["--open-test-project"])
        defer { app.terminate() }

        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertTrue(input.isEnabled)
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

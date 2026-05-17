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
        let app = launchFixtureApp()
        defer { app.terminate() }

        try app.performAccessibilityAudit()
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
        let app = launchFixtureApp()
        defer { app.terminate() }

        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.exists)
        XCTAssertTrue(input.isEnabled)
    }

    @MainActor
    func testToolLogPanelVisible() {
        let app = launchFixtureApp()
        defer { app.terminate() }

        XCTAssertTrue(app.scrollViews["tool-log"].exists)
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

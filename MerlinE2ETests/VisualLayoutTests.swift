import XCTest

final class VisualLayoutTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        app = XCUIApplication()
        app.launch()
    }

    func testNoWidgetsClipped() throws {
        let windowFrame = app.windows.firstMatch.frame
        for element in app.windows.firstMatch.descendants(matching: .any).allElementsBoundByIndex {
            guard element.exists, element.isHittable else { continue }
            let frame = element.frame
            XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX - 1, "\(element.identifier) clipped on left")
            XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX + 1, "\(element.identifier) clipped on right")
        }
    }

    func testAccessibilityAudit() throws {
        try app.performAccessibilityAudit()
    }

    func testCaptureScreenshot() {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testInputFieldExists() {
        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.exists)
        XCTAssertTrue(input.isEnabled)
    }

    func testToolLogPanelVisible() {
        XCTAssertTrue(app.scrollViews["tool-log"].exists)
    }

    func testAuthPopupLayout() {
        let popupApp = XCUIApplication()
        popupApp.launchArguments += ["--show-auth-popup-for-testing"]
        popupApp.launch()

        let popup = popupApp.sheets.firstMatch
        if popup.exists {
            let windowFrame = popupApp.windows.firstMatch.frame
            XCTAssertGreaterThanOrEqual(popup.frame.minX, windowFrame.minX)
            XCTAssertLessThanOrEqual(popup.frame.maxX, windowFrame.maxX)
        }
    }
}

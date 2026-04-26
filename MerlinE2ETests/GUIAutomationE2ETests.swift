import XCTest
@testable import Merlin

@MainActor
private func launchTargetApp() -> XCUIApplication {
    let app = XCUIApplication(bundleIdentifier: "com.merlin.TestTargetApp")
    app.launch()
    return app
}

final class GUIAutomationE2ETests: XCTestCase {
    @MainActor
    func testAXTreeIsRich() async throws {
        let targetApp = launchTargetApp()
        defer { targetApp.terminate() }

        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil else {
            throw XCTSkip("Live tests disabled")
        }

        let tree = await AXInspectorTool.probe(bundleID: "com.merlin.TestTargetApp")
        XCTAssertTrue(tree.isRich)
        XCTAssertGreaterThan(tree.elementCount, 5)
    }

    @MainActor
    func testAXClickPrimaryButton() async throws {
        let targetApp = launchTargetApp()
        defer { targetApp.terminate() }

        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil else {
            throw XCTSkip("Live tests disabled")
        }

        let element = await AXInspectorTool.findElement(
            bundleID: "com.merlin.TestTargetApp",
            role: "AXButton",
            label: "Primary Action",
            value: nil
        )
        XCTAssertNotNil(element)

        guard let element else { return }
        try CGEventTool.click(x: element.frame.midX, y: element.frame.midY)
        try await Task.sleep(nanoseconds: 300_000_000)

        let status = await AXInspectorTool.findElement(
            bundleID: "com.merlin.TestTargetApp",
            role: "AXStaticText",
            label: nil,
            value: "primary tapped"
        )
        XCTAssertNotNil(status, "Status label should show 'primary tapped'")
    }

    @MainActor
    func testVisionQueryIdentifiesButton() async throws {
        let targetApp = launchTargetApp()
        defer { targetApp.terminate() }

        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil else {
            throw XCTSkip("Live tests disabled")
        }

        let jpeg = try await ScreenCaptureTool.captureWindow(
            bundleID: "com.merlin.TestTargetApp",
            quality: 0.85
        )
        let provider = LMStudioProvider()
        let response = try await VisionQueryTool.query(
            imageData: jpeg,
            prompt: "Where is the 'Primary Action' button? Return JSON: {\"x\": int, \"y\": int}",
            provider: provider
        )
        let parsed = VisionQueryTool.parseResponse(response)
        XCTAssertNotNil(parsed?.x)
        XCTAssertNotNil(parsed?.y)
    }
}

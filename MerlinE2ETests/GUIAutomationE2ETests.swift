import AppKit
import XCTest
@testable import Merlin

/// Launches TestTargetApp via NSWorkspace. This target is a `bundle.unit-test`, not a
/// UI-testing bundle, so `XCUIApplication` is unavailable — these tests only need the
/// app *running* (they probe it through AXInspectorTool / CGEventTool by bundle ID).
@MainActor
private func launchTargetApp() async throws -> NSRunningApplication {
    // The xctest bundle is embedded in Merlin.app/Contents/PlugIns; TestTargetApp.app
    // sits in the build products directory several levels up. Walk up to find it.
    var dir = Bundle(for: GUIAutomationE2ETests.self).bundleURL.deletingLastPathComponent()
    var appURL: URL?
    for _ in 0..<8 {
        let candidate = dir.appendingPathComponent("TestTargetApp.app")
        if FileManager.default.fileExists(atPath: candidate.path) {
            appURL = candidate
            break
        }
        let parent = dir.deletingLastPathComponent()
        if parent == dir { break }
        dir = parent
    }
    guard let appURL else {
        throw XCTSkip("TestTargetApp.app not found in the build products directory")
    }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    config.createsNewApplicationInstance = true
    let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    // Let the app finish launching and publish its accessibility tree.
    try await Task.sleep(nanoseconds: 1_500_000_000)
    return app
}

final class GUIAutomationE2ETests: XCTestCase {
    @MainActor
    func testAXTreeIsRich() async throws {
        try skipUnlessLiveEnvironment()
        let targetApp = try await launchTargetApp()
        defer { targetApp.terminate() }

        let tree = await AXInspectorTool.probe(bundleID: "com.merlin.TestTargetApp")
        XCTAssertTrue(tree.isRich)
        XCTAssertGreaterThan(tree.elementCount, 5)
    }

    @MainActor
    func testAXClickPrimaryButton() async throws {
        try skipUnlessLiveEnvironment()
        let targetApp = try await launchTargetApp()
        defer { targetApp.terminate() }

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
        try skipUnlessLiveEnvironment()
        let targetApp = try await launchTargetApp()
        defer { targetApp.terminate() }

        let jpeg = try await ScreenCaptureTool.captureWindow(
            bundleID: "com.merlin.TestTargetApp",
            quality: 0.85
        )
        let provider = OpenAICompatibleProvider(
            id: "lmstudio",
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelID: "")
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

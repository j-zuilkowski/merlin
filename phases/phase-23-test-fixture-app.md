# Phase 23 — TestTargetApp (GUI Automation Fixture)

Context: HANDOFF.md. AXInspectorTool, CGEventTool, ScreenCaptureTool exist.

## Write to: TestTargetApp/TestTargetAppMain.swift

```swift
import SwiftUI

@main
struct TestTargetApp: App {
    var body: some Scene {
        WindowGroup("TestTargetApp") {
            ContentView()
                .frame(width: 600, height: 500)
        }
        .windowResizability(.contentSize)
    }
}
```

## Write to: TestTargetApp/ContentView.swift

Fixed, versioned UI. Never change element labels or positions without bumping a `fixtureVersion` constant — E2E tests depend on stability.

```swift
// fixtureVersion = "1.0"
// Contains exactly:
//   - Button labelled "Primary Action"       (accessibilityIdentifier: "btn-primary")
//   - Button labelled "Secondary Action"     (accessibilityIdentifier: "btn-secondary")
//   - TextField with placeholder "Enter text" (accessibilityIdentifier: "input-field")
//   - Text label showing last button pressed  (accessibilityIdentifier: "status-label")
//   - List of 5 static items: "Item 1" … "Item 5" (accessibilityIdentifier: "item-list")
//   - Toggle labelled "Enable Feature"        (accessibilityIdentifier: "feature-toggle")
//   - Sheet trigger button "Open Sheet"       (accessibilityIdentifier: "btn-sheet")
//   - Sheet contains a "Close" button         (accessibilityIdentifier: "btn-sheet-close")
//
// Tapping "Primary Action" sets status-label to "primary tapped"
// Tapping "Secondary Action" sets status-label to "secondary tapped"
// Typing in input-field and pressing Return sets status-label to input value
```

## Write to: MerlinE2ETests/GUIAutomationE2ETests.swift

```swift
import XCTest
@testable import Merlin

final class GUIAutomationE2ETests: XCTestCase {

    var targetApp: XCUIApplication!

    override func setUp() {
        targetApp = XCUIApplication(bundleIdentifier: "com.merlin.TestTargetApp")
        targetApp.launch()
    }
    override func tearDown() { targetApp.terminate() }

    // AX tree detection: TestTargetApp is AX-rich
    func testAXTreeIsRich() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil
        else { throw XCTSkip("Live tests disabled") }
        let tree = await AXInspectorTool.probe(bundleID: "com.merlin.TestTargetApp")
        XCTAssertTrue(tree.isRich)
        XCTAssertGreaterThan(tree.elementCount, 5)
    }

    // Full AX click loop: inspect → find → click → verify
    func testAXClickPrimaryButton() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil
        else { throw XCTSkip("Live tests disabled") }
        let element = await AXInspectorTool.findElement(
            bundleID: "com.merlin.TestTargetApp", role: "AXButton", label: "Primary Action", value: nil)
        XCTAssertNotNil(element)
        try CGEventTool.click(x: element!.frame.midX, y: element!.frame.midY)
        try await Task.sleep(nanoseconds: 300_000_000)
        let status = await AXInspectorTool.findElement(
            bundleID: "com.merlin.TestTargetApp", role: "AXStaticText", label: nil, value: "primary tapped")
        XCTAssertNotNil(status, "Status label should show 'primary tapped'")
    }

    // Vision fallback: screenshot + parse (requires LM Studio running)
    func testVisionQueryIdentifiesButton() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil
        else { throw XCTSkip("Live tests disabled") }
        let jpeg = try await ScreenCaptureTool.captureWindow(
            bundleID: "com.merlin.TestTargetApp", quality: 0.85)
        let provider = LMStudioProvider()
        let response = try await VisionQueryTool.query(
            imageData: jpeg,
            prompt: "Where is the 'Primary Action' button? Return JSON: {\"x\": int, \"y\": int}",
            provider: provider)
        let parsed = VisionQueryTool.parseResponse(response)
        XCTAssertNotNil(parsed?.x)
        XCTAssertNotNil(parsed?.y)
    }
}
```

## Acceptance
- [ ] TestTargetApp builds and launches showing all 8 elements
- [ ] `swift test --filter GUIAutomationE2ETests` — skips cleanly without `RUN_LIVE_TESTS`
- [ ] With `RUN_LIVE_TESTS=1` and Accessibility granted: AX tests pass
- [ ] `swift build` — zero errors

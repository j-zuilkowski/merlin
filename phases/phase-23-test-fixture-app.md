# Phase 23 — TestTargetApp (GUI Automation Fixture)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 09b complete: AXInspectorTool exists. Phase 10 complete: CGEventTool exists. Phase 09b: ScreenCaptureTool exists.

---

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

---

## Write to: TestTargetApp/ContentView.swift

Fixed, versioned UI. Never change element labels or positions without bumping the `fixtureVersion` constant — E2E tests depend on stability.

```swift
import SwiftUI

// fixtureVersion = "1.0"
// Contains exactly 8 interactive elements:
//   - Button labelled "Primary Action"       (accessibilityIdentifier: "btn-primary")
//   - Button labelled "Secondary Action"     (accessibilityIdentifier: "btn-secondary")
//   - TextField with placeholder "Enter text" (accessibilityIdentifier: "input-field")
//   - Text label showing last button pressed  (accessibilityIdentifier: "status-label")
//   - List of 5 static items: "Item 1" … "Item 5" (accessibilityIdentifier: "item-list")
//   - Toggle labelled "Enable Feature"        (accessibilityIdentifier: "feature-toggle")
//   - Button "Open Sheet"                     (accessibilityIdentifier: "btn-sheet")
//   - Sheet "Close" button                    (accessibilityIdentifier: "btn-sheet-close")
//
// Tapping "Primary Action" sets status-label to "primary tapped"
// Tapping "Secondary Action" sets status-label to "secondary tapped"
// Typing in input-field and pressing Return sets status-label to input value

struct ContentView: View {
    @State private var statusText = "ready"
    @State private var inputText = ""
    @State private var featureEnabled = false
    @State private var showSheet = false

    let fixtureVersion = "1.0"

    var body: some View {
        VStack(spacing: 16) {
            Text(statusText)
                .accessibilityIdentifier("status-label")

            HStack {
                Button("Primary Action") { statusText = "primary tapped" }
                    .accessibilityIdentifier("btn-primary")
                Button("Secondary Action") { statusText = "secondary tapped" }
                    .accessibilityIdentifier("btn-secondary")
            }

            TextField("Enter text", text: $inputText)
                .accessibilityIdentifier("input-field")
                .onSubmit { statusText = inputText }

            Toggle("Enable Feature", isOn: $featureEnabled)
                .accessibilityIdentifier("feature-toggle")

            List(1...5, id: \.self) { i in
                Text("Item \(i)")
            }
            .accessibilityIdentifier("item-list")
            .frame(height: 150)

            Button("Open Sheet") { showSheet = true }
                .accessibilityIdentifier("btn-sheet")
        }
        .padding()
        .sheet(isPresented: $showSheet) {
            VStack {
                Text("Sheet Content")
                Button("Close") { showSheet = false }
                    .accessibilityIdentifier("btn-sheet-close")
            }
            .padding()
        }
    }
}
```

---

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

---

## Verify

Build all targets:
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Verify E2E tests skip without the env var:
```bash
xcodebuild -scheme MerlinTests-Live test-without-building -destination 'platform=macOS' \
    -only-testing:MerlinE2ETests/GUIAutomationE2ETests 2>&1 | grep -E 'skipped|passed|failed'
```

Expected: `BUILD SUCCEEDED`. All 3 GUIAutomation tests skip cleanly without `RUN_LIVE_TESTS`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add TestTargetApp/TestTargetAppMain.swift TestTargetApp/ContentView.swift \
    MerlinE2ETests/GUIAutomationE2ETests.swift
git commit -m "Phase 23 — TestTargetApp fixture + GUIAutomationE2ETests"
```

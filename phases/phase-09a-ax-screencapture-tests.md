# Phase 09a — AX Inspector + Screen Capture Tests

Context: HANDOFF.md. Write failing tests only.

## Write to: MerlinTests/Integration/AXInspectorTests.swift

```swift
import XCTest
@testable import Merlin

final class AXInspectorTests: XCTestCase {

    func testProbeRunningApp() async throws {
        // Probe the Finder — always running
        let tree = await AXInspectorTool.probe(bundleID: "com.apple.finder")
        // Finder has a rich AX tree
        XCTAssertGreaterThan(tree.elementCount, 10)
        XCTAssertTrue(tree.isRich)
    }

    func testProbeUnknownAppReturnsEmpty() async throws {
        let tree = await AXInspectorTool.probe(bundleID: "com.nonexistent.app.xyz")
        XCTAssertEqual(tree.elementCount, 0)
        XCTAssertFalse(tree.isRich)
    }

    func testTreeSerializesToJSON() async throws {
        let tree = await AXInspectorTool.probe(bundleID: "com.apple.finder")
        let json = tree.toJSON()
        XCTAssertFalse(json.isEmpty)
        // Valid JSON
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: json.data(using: .utf8)!))
    }
}
```

## Write to: MerlinTests/Integration/ScreenCaptureTests.swift

```swift
final class ScreenCaptureTests: XCTestCase {

    func testCaptureMainDisplay() async throws {
        // Requires Screen Recording permission — skip gracefully if denied
        do {
            let jpeg = try await ScreenCaptureTool.captureDisplay(quality: 0.85)
            XCTAssertFalse(jpeg.isEmpty)
            XCTAssertLessThan(jpeg.count, 5_000_000) // under 5MB
        } catch ScreenCaptureError.permissionDenied {
            throw XCTSkip("Screen Recording permission not granted")
        }
    }

    func testCaptureSizeIsLogical() async throws {
        do {
            let (jpeg, size) = try await ScreenCaptureTool.captureDisplayWithSize(quality: 0.85)
            XCTAssertFalse(jpeg.isEmpty)
            // Logical resolution (not 2x retina)
            XCTAssertLessThanOrEqual(size.width, 3840)
        } catch ScreenCaptureError.permissionDenied {
            throw XCTSkip("Screen Recording permission not granted")
        }
    }
}
```

## Acceptance
- [ ] Files compile (types missing — expected)

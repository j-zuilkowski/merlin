# Phase 09a — AX Inspector + Screen Capture Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

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
import XCTest
@testable import Merlin

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

---

## Verify

Run after writing both files. Expect build errors for missing `AXInspectorTool`, `ScreenCaptureTool`, `ScreenCaptureError`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing the missing types.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Integration/AXInspectorTests.swift MerlinTests/Integration/ScreenCaptureTests.swift
git commit -m "Phase 09a — AXInspectorTests + ScreenCaptureTests (failing)"
```

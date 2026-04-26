# Phase 09b — AXInspectorTool + ScreenCaptureTool

Context: HANDOFF.md. Make phase-09a tests pass.

## Write to: Merlin/Tools/AXInspectorTool.swift

```swift
import Accessibility
import AppKit

struct AXTree {
    var elementCount: Int
    var isRich: Bool  // elementCount > 10 && hasLabels
    var elements: [AXElement]

    func toJSON() -> String  // serialize elements to JSON string
}

struct AXElement: Codable {
    var role: String
    var label: String?
    var value: String?
    var frame: CGRect
    var children: [AXElement]
}

enum AXInspectorTool {
    // Returns empty AXTree if app not running or permission denied
    static func probe(bundleID: String) async -> AXTree

    // Returns first element matching criteria
    static func findElement(bundleID: String, role: String?, label: String?, value: String?) async -> AXElement?

    // Returns current value of an element
    static func getElementValue(element: AXElement) async -> String?
}
```

Use `AXUIElementCreateApplication(pid)` with the PID from `NSRunningApplication`. Walk the AX tree recursively via `kAXChildrenAttribute`. Cap recursion depth at 8 to avoid runaway traversal.

## Write to: Merlin/Tools/ScreenCaptureTool.swift

```swift
import ScreenCaptureKit
import CoreGraphics

enum ScreenCaptureError: Error {
    case permissionDenied
    case noDisplayFound
    case encodingFailed
}

enum ScreenCaptureTool {
    // Captures main display at logical resolution
    // quality: JPEG compression 0.0–1.0
    static func captureDisplay(quality: Double) async throws -> Data

    // Returns JPEG data + logical pixel size
    static func captureDisplayWithSize(quality: Double) async throws -> (Data, CGSize)

    // Captures a specific app window by bundle ID
    static func captureWindow(bundleID: String, quality: Double) async throws -> Data
}
```

Use `SCShareableContent` to enumerate displays.

**Logical resolution (critical):** `SCDisplay.width` and `.height` return logical points,
not physical pixels. Set `SCStreamConfiguration` explicitly:
```swift
let config = SCStreamConfiguration()
config.width = display.width    // logical — do NOT multiply by scaleFactor
config.height = display.height
config.scaleFactor = 1.0        // capture at 1:1 logical pixels
config.pixelFormat = kCVPixelFormatType_32BGRA
```
This produces images sized to the logical screen dimensions (~1440×900 on a standard
5K display), not the 2x retina physical dimensions. Encode the result via
`NSBitmapImageRep` as JPEG.

## Acceptance
- [ ] `swift test --filter AXInspectorTests` — all 3 pass (Finder probe will pass if Accessibility granted)
- [ ] `swift test --filter ScreenCaptureTests` — pass or skip gracefully
- [ ] `swift build` — zero errors

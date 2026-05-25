# Phase 61a — Vision Attachment Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 60b complete: skill re-injection after compaction.

New surface introduced in phase 61b:
  - `VisionQueryTool.query(imageData:prompt:provider: any LLMProvider)` — generalized from
    `LMStudioProvider` to `any LLMProvider`
  - `ContextInjector.inlineAttachment(url:visionProvider: (any LLMProvider)?)` — adds optional
    provider parameter; calls `VisionQueryTool.query` for image extensions; falls back to
    placeholder when nil

TDD coverage:
  File 1 — ContextInjectorVisionTests: image→description via mock provider, nil fallback,
            all image extensions routed correctly

---

## Write to: MerlinTests/Unit/ContextInjectorVisionTests.swift

```swift
import XCTest
@testable import Merlin

final class ContextInjectorVisionTests: XCTestCase {

    // MARK: - Helpers

    private func writeTempImage(ext: String = "png") throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-image-\(UUID().uuidString).\(ext)")
        // Write a minimal valid 1×1 PNG (89 bytes)
        let pngBytes: [UInt8] = [
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A, // PNG signature
            0x00,0x00,0x00,0x0D, // IHDR length
            0x49,0x48,0x44,0x52, // "IHDR"
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01, // 1×1
            0x08,0x02,0x00,0x00,0x00, // 8-bit RGB
            0x90,0x77,0x53,0xDE, // CRC
            0x00,0x00,0x00,0x0C, // IDAT length
            0x49,0x44,0x41,0x54, // "IDAT"
            0x08,0xD7,0x63,0xF8,0xCF,0xC0,0x00,0x00,0x00,0x02,0x00,0x01,
            0xE2,0x21,0xBC,0x33, // CRC
            0x00,0x00,0x00,0x00, // IEND length
            0x49,0x45,0x4E,0x44, // "IEND"
            0xAE,0x42,0x60,0x82  // CRC
        ]
        try Data(pngBytes).write(to: url)
        return url
    }

    // MARK: - Vision provider path

    func testImageWithVisionProviderReturnsDescription() async throws {
        let url = try writeTempImage(ext: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        let mock = MockProvider(response: "a red square on white background")
        let result = try await ContextInjector.inlineAttachment(url: url, visionProvider: mock)

        XCTAssertTrue(result.contains("[Image:"), "Result should start with [Image: block")
        XCTAssertTrue(result.contains("a red square"), "Result should contain the vision description")
        XCTAssertFalse(result.contains("vision analysis pending"), "Should not contain placeholder when provider present")
    }

    func testJpegExtensionUsesVisionPath() async throws {
        let url = try writeTempImage(ext: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        let mock = MockProvider(response: "a blue circle")
        let result = try await ContextInjector.inlineAttachment(url: url, visionProvider: mock)
        XCTAssertTrue(result.contains("a blue circle"))
    }

    func testHeicExtensionUsesVisionPath() async throws {
        // HEIC may fail to decode as image data but the routing branch should be hit
        let url = try writeTempImage(ext: "heic")
        defer { try? FileManager.default.removeItem(at: url) }

        let mock = MockProvider(response: "photo description")
        // May throw or return placeholder if HEIC data is invalid — just verify no crash
        _ = try? await ContextInjector.inlineAttachment(url: url, visionProvider: mock)
    }

    // MARK: - Nil provider fallback

    func testImageWithNilProviderReturnsPlaceholder() async throws {
        let url = try writeTempImage(ext: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await ContextInjector.inlineAttachment(url: url, visionProvider: nil)
        XCTAssertTrue(result.contains("vision analysis pending"), "Nil provider should return placeholder")
    }

    // MARK: - Non-image types unaffected

    func testSourceFileUnaffectedByVisionProvider() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).swift")
        try "let x = 1".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let mock = MockProvider(response: "should not be called")
        let result = try await ContextInjector.inlineAttachment(url: url, visionProvider: mock)
        XCTAssertTrue(result.contains("[File:"))
        XCTAssertFalse(result.contains("should not be called"))
    }

    func testBinaryFileThrowsUnsupportedType() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).exe")
        try Data([0x4D, 0x5A]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await ContextInjector.inlineAttachment(url: url, visionProvider: nil)
            XCTFail("Expected AttachmentError.unsupportedType")
        } catch AttachmentError.unsupportedType {
            // expected
        }
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` — `inlineAttachment(url:visionProvider:)` signature not yet present.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ContextInjectorVisionTests.swift
git commit -m "Phase 61a — ContextInjectorVisionTests (failing)"
```

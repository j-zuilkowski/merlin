import XCTest
@testable import Merlin

final class ContextInjectorVisionTests: XCTestCase {

    // MARK: - Helpers

    private func writeTempImage(ext: String = "png") throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-image-\(UUID().uuidString).\(ext)")
        // Write a minimal valid 1×1 PNG (89 bytes)
        let pngBytes: [UInt8] = [
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,
            0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x02,0x00,0x00,0x00,
            0x90,0x77,0x53,0xDE,
            0x00,0x00,0x00,0x0C,
            0x49,0x44,0x41,0x54,
            0x08,0xD7,0x63,0xF8,0xCF,0xC0,0x00,0x00,0x00,0x02,0x00,0x01,
            0xE2,0x21,0xBC,0x33,
            0x00,0x00,0x00,0x00,
            0x49,0x45,0x4E,0x44,
            0xAE,0x42,0x60,0x82
        ]
        try Data(pngBytes).write(to: url)
        return url
    }

    // MARK: - Vision provider path

    func testImageWithVisionProviderReturnsDescription() async throws {
        let url = try writeTempImage(ext: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        let mock = MockProvider()
        mock.stubbedResponse = "a red square on white background"
        let result = try await ContextInjector.inlineAttachment(url: url, visionProvider: mock)

        XCTAssertTrue(result.contains("[Image:"))
        XCTAssertTrue(result.contains("a red square"))
        XCTAssertFalse(result.contains("vision analysis pending"))
    }

    func testJpegExtensionUsesVisionPath() async throws {
        let url = try writeTempImage(ext: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        let mock = MockProvider()
        mock.stubbedResponse = "a blue circle"
        let result = try await ContextInjector.inlineAttachment(url: url, visionProvider: mock)
        XCTAssertTrue(result.contains("a blue circle"))
    }

    func testHeicExtensionUsesVisionPath() async throws {
        let url = try writeTempImage(ext: "heic")
        defer { try? FileManager.default.removeItem(at: url) }

        let mock = MockProvider()
        mock.stubbedResponse = "photo description"

        _ = try? await ContextInjector.inlineAttachment(url: url, visionProvider: mock)
    }

    // MARK: - Nil provider fallback

    func testImageWithNilProviderReturnsPlaceholder() async throws {
        let url = try writeTempImage(ext: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await ContextInjector.inlineAttachment(url: url, visionProvider: nil)
        XCTAssertTrue(result.contains("vision analysis pending"))
    }

    // MARK: - Non-image types unaffected

    func testSourceFileUnaffectedByVisionProvider() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-\(UUID().uuidString).swift")
        try "let x = 1".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let mock = MockProvider()
        mock.stubbedResponse = "should not be called"
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

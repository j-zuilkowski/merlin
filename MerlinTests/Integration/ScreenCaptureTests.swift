import XCTest
@testable import Merlin

final class ScreenCaptureTests: XCTestCase {

    func testCaptureMainDisplay() async throws {
        do {
            let jpeg = try await ScreenCaptureTool.captureDisplay(quality: 0.85)
            XCTAssertFalse(jpeg.isEmpty)
            XCTAssertLessThan(jpeg.count, 5_000_000)
        } catch ScreenCaptureError.permissionDenied {
            throw XCTSkip("Screen Recording permission not granted")
        }
    }

    func testCaptureSizeIsLogical() async throws {
        do {
            let (jpeg, size) = try await ScreenCaptureTool.captureDisplayWithSize(quality: 0.85)
            XCTAssertFalse(jpeg.isEmpty)
            XCTAssertLessThanOrEqual(size.width, 3840)
        } catch ScreenCaptureError.permissionDenied {
            throw XCTSkip("Screen Recording permission not granted")
        }
    }
}

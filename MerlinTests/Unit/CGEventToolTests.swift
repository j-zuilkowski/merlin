import XCTest
@testable import Merlin

final class CGEventToolTests: XCTestCase {
    func testKeyComboParser() throws {
        XCTAssertNoThrow(try CGEventTool.pressKey("cmd+s"))
        XCTAssertNoThrow(try CGEventTool.pressKey("return"))
        XCTAssertNoThrow(try CGEventTool.pressKey("escape"))
        XCTAssertThrowsError(try CGEventTool.pressKey(""))
    }

    func testVisionResponseParser() {
        let raw = #"{"x": 320, "y": 180, "confidence": 0.92, "action": "click"}"#
        let response = VisionQueryTool.parseResponse(raw)
        XCTAssertEqual(response?.x, 320)
        XCTAssertEqual(response?.confidence, 0.92)
    }
}

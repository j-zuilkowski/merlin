import Foundation
import XCTest
@testable import Merlin

final class AXInspectorTests: XCTestCase {

    func testProbeRunningApp() async throws {
        let tree = await AXInspectorTool.probe(bundleID: "com.apple.finder")
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
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(json.utf8)))
    }
}

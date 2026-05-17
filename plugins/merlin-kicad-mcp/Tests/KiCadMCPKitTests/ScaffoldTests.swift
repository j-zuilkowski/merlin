import XCTest
@testable import KiCadMCPKit

final class ScaffoldTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertEqual(KiCadMCPKit.protocolName, "merlin-kicad-mcp")
    }
}

import XCTest
@testable import Merlin

final class ToolDiscoveryTests: XCTestCase {

    func testScanFindsCommonTools() async {
        let tools = await ToolDiscovery.scan()
        let names = tools.map { $0.name }
        XCTAssertTrue(names.contains("git"))
        XCTAssertTrue(names.contains("swift"))
    }

    func testNoDuplicateNames() async {
        let tools = await ToolDiscovery.scan()
        let names = tools.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count)
    }
}

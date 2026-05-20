import XCTest
@testable import Merlin

final class ToolDiscoveryTests: XCTestCase {

    // `summarize: false` skips the per-tool `--help` probe. The probe spawns
    // a 2 s-timeout subprocess for every executable on `$PATH`; on a CI
    // runner that means hundreds of subprocesses and roughly 5–15 minutes
    // per call, which wedged the unit suite. These tests verify the
    // discovery contract (common tools present, names deduplicated), not
    // the summary side-effect, so the probe is unnecessary.

    func testScanFindsCommonTools() async {
        let tools = await ToolDiscovery.scan(summarize: false)
        let names = tools.map { $0.name }
        XCTAssertTrue(names.contains("git"))
        XCTAssertTrue(names.contains("swift"))
    }

    func testNoDuplicateNames() async {
        let tools = await ToolDiscovery.scan(summarize: false)
        let names = tools.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count)
    }
}

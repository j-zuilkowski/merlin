import XCTest
@testable import Merlin

final class AppVersionTests: XCTestCase {

    func testBundleVersionMatchesV210ReleaseTarget() {
        let info = Bundle.main.infoDictionary
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, "2.1.0")
        XCTAssertEqual(info?["CFBundleVersion"] as? String, "16")
    }
}

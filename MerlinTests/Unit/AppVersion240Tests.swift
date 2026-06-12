import XCTest
@testable import Merlin

final class AppVersion240Tests: XCTestCase {

    func testMarketingVersionIs240() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "2.4.0",
                       "MARKETING_VERSION must be 2.4.0 for the v2.4.0 release")
    }

    func testBuildNumberIs26() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertEqual(build, "26",
                       "CURRENT_PROJECT_VERSION must be 26 for the v2.4.0 release")
    }
}

import XCTest
@testable import Merlin

final class AppVersion222Tests: XCTestCase {

    func testMarketingVersionIs222() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "2.2.2",
                       "MARKETING_VERSION must be 2.2.2 for the v2.2.2 release")
    }

    func testBuildNumberIs19() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertEqual(build, "19",
                       "CURRENT_PROJECT_VERSION must be 19 for the v2.2.2 release")
    }
}

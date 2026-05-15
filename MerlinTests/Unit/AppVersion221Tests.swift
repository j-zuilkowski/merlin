import XCTest
@testable import Merlin

final class AppVersion221Tests: XCTestCase {

    func testMarketingVersionIs221() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "2.2.1",
                       "MARKETING_VERSION must be 2.2.1 for the v2.2.1 release")
    }

    func testBuildNumberIs18() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertEqual(build, "18",
                       "CURRENT_PROJECT_VERSION must be 18 for the v2.2.1 release")
    }
}

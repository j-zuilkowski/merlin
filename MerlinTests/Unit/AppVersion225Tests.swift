import XCTest
@testable import Merlin

final class AppVersion225Tests: XCTestCase {

    func testMarketingVersionIs225() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "2.2.5",
                       "MARKETING_VERSION must be 2.2.5 for the v2.2.5 release")
    }

    func testBuildNumberIs24() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertEqual(build, "24",
                       "CURRENT_PROJECT_VERSION must be 24 for the v2.2.5 release")
    }
}

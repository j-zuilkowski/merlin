import XCTest
@testable import Merlin

final class AppVersion230Tests: XCTestCase {

    func testMarketingVersionIs230() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "2.3.0",
                       "MARKETING_VERSION must be 2.3.0 for the v2.3.0 release")
    }

    func testBuildNumberIs25() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertEqual(build, "25",
                       "CURRENT_PROJECT_VERSION must be 25 for the v2.3.0 release")
    }
}

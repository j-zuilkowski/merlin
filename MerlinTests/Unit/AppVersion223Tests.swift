import XCTest
@testable import Merlin

final class AppVersion223Tests: XCTestCase {

    func testMarketingVersionIs223() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "2.2.3",
                       "MARKETING_VERSION must be 2.2.3 for the v2.2.3 release")
    }

    func testBuildNumberIs20() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertEqual(build, "20",
                       "CURRENT_PROJECT_VERSION must be 20 for the v2.2.3 release")
    }
}

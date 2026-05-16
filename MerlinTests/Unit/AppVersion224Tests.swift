import XCTest
@testable import Merlin

final class AppVersion224Tests: XCTestCase {

    func testMarketingVersionIs224() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "2.2.4",
                       "MARKETING_VERSION must be 2.2.4 for the v2.2.4 release")
    }

    func testBuildNumberIs22() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertEqual(build, "22",
                       "CURRENT_PROJECT_VERSION must be 22 for the v2.2.4 SideChatPane crash-fix build")
    }
}

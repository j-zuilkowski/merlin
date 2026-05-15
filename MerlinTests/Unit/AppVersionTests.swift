import XCTest

final class AppVersionTests: XCTestCase {

    func testMarketingVersion() throws {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertEqual(version, "2.2.1",
                       "MARKETING_VERSION must be 2.2.1. Run phase 273b to bump project.yml.")
    }

    func testBuildNumber() throws {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        XCTAssertEqual(build, "18",
                       "CURRENT_PROJECT_VERSION must be 18. Run phase 273b to bump project.yml.")
    }
}

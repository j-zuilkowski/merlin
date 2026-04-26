import XCTest
@testable import Merlin

final class AppControlTests: XCTestCase {

    func testListRunningContainsFinder() {
        let apps = AppControlTools.listRunning()
        XCTAssertTrue(apps.contains { $0.bundleID == "com.apple.finder" })
    }

    func testFocusFinderDoesNotThrow() {
        XCTAssertNoThrow(try AppControlTools.focus(bundleID: "com.apple.finder"))
    }
}

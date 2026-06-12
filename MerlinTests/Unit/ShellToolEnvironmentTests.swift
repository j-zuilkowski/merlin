import XCTest
@testable import Merlin

final class ShellToolEnvironmentTests: XCTestCase {
    func testDefaultEnvironmentAddsCommonDeveloperToolPaths() {
        let env = ShellTool.defaultEnvironment(processEnvironment: [
            "PATH": "/usr/bin:/bin"
        ])

        let path = env["PATH"] ?? ""
        XCTAssertTrue(path.contains("/opt/homebrew/bin"), path)
        XCTAssertTrue(path.contains("/usr/local/bin"), path)
        XCTAssertTrue(path.contains("/usr/bin"), path)
    }
}

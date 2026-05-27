import XCTest
@testable import Merlin

final class UIRunnerBootstrapPolicyTests: XCTestCase {
    func testRejectsTmpDerivedDataWithSigningDisabledBeforeLaunch() {
        let policy = UIRunnerBootstrapPolicy(
            derivedDataPath: "/tmp/merlin-e2e-derived",
            codeSigningAllowed: false,
            codeSignIdentity: "")

        let result = policy.preflight()

        XCTAssertFalse(result.isAllowed)
        XCTAssertEqual(
            result.failure,
            .unsupportedConfiguration("/tmp DerivedData with code signing disabled cannot reliably bootstrap MerlinUITests"))
    }

    func testSupportedFocusedAndFullCommandsSharePolicy() {
        let policy = UIRunnerBootstrapPolicy.supported

        XCTAssertTrue(policy.preflight().isAllowed)
        XCTAssertEqual(
            policy.xcodebuildArguments(),
            ["-scheme", "MerlinUITests", "-destination", "platform=macOS", "test"])
        XCTAssertEqual(
            policy.xcodebuildArguments(forOnlyTesting: "MerlinUITests/VisualLayoutTests"),
            ["-scheme", "MerlinUITests", "-destination", "platform=macOS",
             "-only-testing:MerlinUITests/VisualLayoutTests", "test"])
    }

    func testEarlyUnexpectedExitIsRunnerBootstrapFailure() {
        let output = """
        Early unexpected exit, operation never finished bootstrapping
        MerlinUITests-Runner crashed with signal kill before establishing connection
        """

        XCTAssertEqual(
            UIRunnerBootstrapPolicy.classifyXCTestOutput(output),
            .runnerBootstrap("XCTest runner exited before establishing the automation connection"))
    }
}

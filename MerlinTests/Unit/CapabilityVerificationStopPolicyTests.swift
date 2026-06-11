import XCTest
@testable import Merlin

final class CapabilityVerificationStopPolicyTests: XCTestCase {
    func testStopsOnlyOnGreenVerificationToolEvidence() {
        let policy = CapabilityVerificationStopPolicy()
        let greenXcodebuild = """
        Test Suite 'All tests' passed
        ** TEST SUCCEEDED **
        """

        XCTAssertTrue(policy.shouldStop(toolName: "run_shell", result: greenXcodebuild))
        XCTAssertTrue(policy.shouldStop(toolName: "xcode_test", result: greenXcodebuild))
        XCTAssertFalse(policy.shouldStop(toolName: "list_directory", result: greenXcodebuild))
        XCTAssertFalse(policy.shouldStop(toolName: "run_shell", result: "** TEST FAILED **"))
    }

    func testStopsAfterSuccessfulSwiftSourceRepairCandidate() {
        let policy = CapabilityVerificationStopPolicy()
        let sourceWrite = #"{"path":"/tmp/fixture/Sources/TaskBoard/TaskStore.swift","content":"..."}"#
        let xcodegenFixtureWrite = #"{"path":"/tmp/fixture/TaskBoard/TaskStore.swift","content":"..."}"#
        let rustSourceWrite = #"{"path":"/tmp/fixture/ledger/src/lib.rs","content":"..."}"#
        let projectWrite = #"{"path":"/tmp/fixture/project.yml","content":"..."}"#
        let testWrite = #"{"path":"/tmp/fixture/TaskBoardTests/TaskStoreTests.swift","content":"..."}"#

        XCTAssertTrue(policy.shouldStopAfterSourceEdit(
            toolName: "write_file",
            arguments: sourceWrite,
            isError: false))
        XCTAssertTrue(policy.shouldStopAfterSourceEdit(
            toolName: "write_file",
            arguments: xcodegenFixtureWrite,
            isError: false))
        XCTAssertTrue(policy.shouldStopAfterSourceEdit(
            toolName: "write_file",
            arguments: rustSourceWrite,
            isError: false))
        XCTAssertFalse(policy.shouldStopAfterSourceEdit(
            toolName: "write_file",
            arguments: projectWrite,
            isError: false))
        XCTAssertFalse(policy.shouldStopAfterSourceEdit(
            toolName: "write_file",
            arguments: testWrite,
            isError: false))
        XCTAssertFalse(policy.shouldStopAfterSourceEdit(
            toolName: "write_file",
            arguments: sourceWrite,
            isError: true))
        XCTAssertFalse(policy.shouldStopAfterSourceEdit(
            toolName: "run_shell",
            arguments: sourceWrite,
            isError: false))
    }
}

import XCTest
@testable import Merlin

final class CapabilityConvergenceTests: XCTestCase {
    func testS1FailingTaskStoreTestsRemainRepairable() {
        let output = """
        Test Case '-[TaskBoardTests.TaskStoreTests testDeleteRemovesTheTaskAtThatIndex]' failed
        Test Case '-[TaskBoardTests.TaskStoreTests testSummaryCountsDoneOnly]' failed
        ** TEST FAILED **
        """

        let status = CapabilityConvergenceClassifier().classify(
            verificationOutput: output,
            assistantText: "I fixed the app and it is done.")

        guard case .repairableFailure(let summary) = status else {
            return XCTFail("Expected repairable failure, got \(status)")
        }
        XCTAssertTrue(summary.contains("testDeleteRemovesTheTaskAtThatIndex"))
        XCTAssertTrue(summary.contains("testSummaryCountsDoneOnly"))
    }

    func testS2OverflowBeatsFalseCargoMissingClaim() {
        let output = """
        running 18 tests
        tests::total_does_not_overflow_on_a_large_ledger --- FAILED
        thread 'tests::total_does_not_overflow_on_a_large_ledger' panicked at src/lib.rs:41:17:
        attempt to add with overflow
        test result: FAILED. 17 passed; 1 failed
        """

        let status = CapabilityConvergenceClassifier().classify(
            verificationOutput: output,
            assistantText: "cargo is not available in the system PATH.")

        guard case .repairableFailure(let summary) = status else {
            return XCTFail("Expected cargo output to stay repairable, got \(status)")
        }
        XCTAssertTrue(summary.contains("total_does_not_overflow_on_a_large_ledger"))
        XCTAssertTrue(summary.localizedCaseInsensitiveContains("overflow"))
    }

    func testActualMissingCargoIsPrerequisiteFailure() {
        let output = "zsh:1: command not found: cargo"

        let status = CapabilityConvergenceClassifier().classify(
            verificationOutput: output,
            assistantText: "cargo is not available in the system PATH.")

        guard case .missingPrerequisite(let summary) = status else {
            return XCTFail("Expected missing cargo prerequisite, got \(status)")
        }
        XCTAssertTrue(summary.localizedCaseInsensitiveContains("cargo"))
    }

    func testRepeatedNoProgressEscalatesBeforeTimeout() {
        let status = CapabilityConvergenceClassifier().classify(
            verificationOutput: "** TEST FAILED **",
            assistantText: "I will inspect the project.",
            repeatedNoProgressTurns: 2,
            maxNoProgressTurns: 2,
            hasFileChanges: false,
            verificationImproved: false)

        guard case .noProgressEscalation(let summary) = status else {
            return XCTFail("Expected no-progress escalation, got \(status)")
        }
        XCTAssertTrue(summary.localizedCaseInsensitiveContains("no progress"))
    }
}

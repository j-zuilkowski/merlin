import Foundation
import XCTest
@testable import Merlin

/// Phase 303a - failing smoke test for the eval harness.
final class EvalHarnessSmokeTests: XCTestCase {

    @MainActor
    func testHarnessRunsATrivialScenario() async throws {
        try skipUnlessLiveEnvironment()

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-smoke-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let run = try await EvalHarness.runScenario(
            fixturePath: tmp.path,
            prompt: "Reply with exactly the single word: READY",
            timeout: 300)

        // Surface the captured run in the failure message — this test fails only
        // when an earlier test pollutes process-global state, and a bare assertion
        // gives nothing to diagnose it with.
        let diag = " [errors=\(run.errors) | systemNotes=\(run.systemNotes) "
            + "| toolCalls=\(run.toolCalls.map(\.name)) | events=\(run.allEvents.count) "
            + "| assistantText=\"\(run.assistantText.prefix(200))\"]"
        XCTAssertFalse(run.assistantText.isEmpty,
                       "the harness must capture the assistant's response\(diag)")
        XCTAssertTrue(run.errors.isEmpty,
                      "a trivial scenario must not produce engine errors\(diag)")
    }

    /// HARNESS-5 regression: a scenario whose event stream stalls (here the agent runs
    /// one long blocking shell command, emitting no events) must still be bounded by
    /// `runScenario`'s `timeout`. The old in-loop deadline check could not fire on a
    /// stalled stream, so a hung scenario blocked the whole suite indefinitely.
    @MainActor
    func testStalledScenarioIsWallClockBounded() async throws {
        try skipUnlessLiveEnvironment()

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-stall-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let start = Date()
        do {
            _ = try await EvalHarness.runScenario(
                fixturePath: tmp.path,
                prompt: "Run this exact shell command and wait for it to finish: sleep 600",
                timeout: 45)
            XCTFail("a stalled scenario was expected to time out")
        } catch let error as EvalHarness.HarnessError {
            XCTAssertEqual(String(describing: error), "timedOut",
                           "a stalled scenario must yield HarnessError.timedOut")
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 180,
                          "runScenario must wall-clock-bound a stalled scenario near "
                          + "its timeout, not run to the shell command's completion")
    }
}

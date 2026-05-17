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

        XCTAssertFalse(run.assistantText.isEmpty,
                       "the harness must capture the assistant's response")
        XCTAssertTrue(run.errors.isEmpty,
                      "a trivial scenario must not produce engine errors")
    }

    /// M-3 reproduction: a scenario that times out tears the LiveSession down while a
    /// turn is still live. On a project with no `.merlin/` directory this surfaced an
    /// NSError 260 that escaped `runScenario` (which only ever throws `HarnessError`).
    @MainActor
    func testTimeoutTeardownDoesNotLeakForeignError() async throws {
        try skipUnlessLiveEnvironment()

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-teardown-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Copy the real swift-gui-buggy fixture so the scenario does genuine Xcode
        // work (build/launch/GUI) — that is the S1 condition under which NSError 260
        // surfaced. The copy keeps the shared fixture pristine.
        let src = EvalPaths.fixture("swift-gui-buggy")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: src),
                          "swift-gui-buggy fixture missing")
        let work = tmp.appendingPathComponent("swift-gui-buggy", isDirectory: true)
        try FileManager.default.copyItem(atPath: src, toPath: work.path)

        do {
            _ = try await EvalHarness.runScenario(
                fixturePath: work.path, prompt: EvalPrompts.s1, timeout: 120)
            // Completing before the deadline is fine — the point is no foreign error.
        } catch let error as EvalHarness.HarnessError {
            XCTAssertEqual(String(describing: error), "timedOut",
                           "timeout teardown must yield HarnessError.timedOut")
        }
    }
}

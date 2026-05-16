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
}

import XCTest
@testable import Merlin

@MainActor
final class RetryCounterDeletionTests: XCTestCase {

    func testDeletedRetryCountersAndRecursiveSelfCallAreGoneFromAgenticEngine() throws {
        let source = try readAgenticEngineSource()

        XCTAssertFalse(
            source.contains("contextLengthRetryCount"),
            "contextLengthRetryCount must be removed from AgenticEngine.swift"
        )
        XCTAssertFalse(
            source.contains("maxContextOverrunRecoveryAttempts"),
            "maxContextOverrunRecoveryAttempts must be removed from AgenticEngine.swift"
        )
        XCTAssertFalse(
            source.contains("try await runLoop("),
            "Recursive runLoop self-call must be removed from AgenticEngine.swift"
        )
    }

    private func readAgenticEngineSource() throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent() // Unit
            .deletingLastPathComponent() // MerlinTests
            .deletingLastPathComponent() // repo root
        let sourceURL = repoRoot.appendingPathComponent("Merlin/Engine/AgenticEngine.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

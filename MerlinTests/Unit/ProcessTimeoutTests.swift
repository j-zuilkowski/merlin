import XCTest
@testable import Merlin

final class ProcessTimeoutTests: XCTestCase {

    func testAPIDocGeneratorTimesOutInsteadOfHanging() async throws {
        // A rust adapter routes generation through runProcess; a 1 s timeout against a
        // 10 s sleep must resolve with a failure quickly, not hang the test.
        var adapter = ProjectAdapter.makeStub(language: "rust")
        adapter = ProjectAdapter(
            language: adapter.language,
            versioningFile: adapter.versioningFile,
            versioningField: adapter.versioningField,
            buildCommand: adapter.buildCommand,
            testCommand: adapter.testCommand,
            buildSuccessMarker: adapter.buildSuccessMarker,
            buildFailureMarker: adapter.buildFailureMarker,
            releaseCommand: adapter.releaseCommand,
            apiDocGenerator: "rustdoc",
            docTargetGrade: adapter.docTargetGrade,
            whyCommentTriggers: adapter.whyCommentTriggers,
            manualCoveragePatterns: adapter.manualCoveragePatterns
        )

        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        // 1 s process timeout. The generator is told to run a 10 s sleep.
        let generator = APIDocGenerator(timeoutSeconds: 1)

        let start = Date()
        do {
            _ = try await generator.runForTesting(
                executable: "/bin/sleep",
                args: ["10"],
                workingDirectory: projectRoot.path)
            XCTFail("Expected a timeout failure")
        } catch APIDocGenerator.GeneratorError.generationFailed(let message) {
            XCTAssertTrue(message.lowercased().contains("timed out"),
                "Failure message should mention the timeout: \(message)")
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 6.0,
            "A 1 s timeout must resolve well before the 10 s sleep completes")
    }
}

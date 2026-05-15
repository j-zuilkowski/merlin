import XCTest
@testable import Merlin

final class ProseGateTests: XCTestCase {

    private func makeAdapter(grade: Double = 9.0) -> ProjectAdapter {
        ProjectAdapter(
            language: "swift", versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild", testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED", buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create", apiDocGenerator: "docc",
            docTargetGrade: ["user_manual": grade, "architecture": 11.0],
            whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    func testEmptyListPasses() async {
        let gate = ProseGate(checkerFactory: { _, _ in
            ProseReadabilityChecker(dryRun: true, forcedGrade: 7.0)
        })
        let result = await gate.check(changedDocFiles: [], adapter: makeAdapter())
        if case .block(let findings) = result {
            XCTFail("Expected pass for empty list, got block: \(findings)")
        }
    }

    func testAllUnderTargetPasses() async throws {
        let docFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-manual-\(UUID()).md").path
        try "# Manual\n\nShort doc.".write(
            toFile: docFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: docFile) }

        let gate = ProseGate(checkerFactory: { _, _ in
            ProseReadabilityChecker(dryRun: true, forcedGrade: 7.0)
        })
        let result = await gate.check(changedDocFiles: [docFile], adapter: makeAdapter())
        if case .block(let findings) = result {
            XCTFail("Expected pass but got block with \(findings.count) findings")
        }
    }

    func testOverTargetBlocks() async throws {
        let docFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-manual-hard-\(UUID()).md").path
        try "# Manual\n\nHard text.".write(
            toFile: docFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: docFile) }

        let gate = ProseGate(checkerFactory: { _, _ in
            ProseReadabilityChecker(dryRun: true, forcedGrade: 14.0)
        })
        let result = await gate.check(changedDocFiles: [docFile], adapter: makeAdapter())
        if case .pass = result {
            XCTFail("Expected block when grade exceeds target")
        }
    }

    func testProseGateResultIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        requiresSendable(ProseGateResult.pass)
        requiresSendable(ProseGateResult.block(findings: []))
    }
}

import XCTest
@testable import Merlin

final class ProseProductionPathTests: XCTestCase {

    private var projectRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
    }

    private func writeFile(_ relativePath: String, _ contents: String) throws {
        let url = projectRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Vale style file shape

    func testReadabilityStyleUsesReadabilityRule() async throws {
        let styleDir = projectRoot.appendingPathComponent("styles")
        try FileManager.default.createDirectory(
            at: styleDir, withIntermediateDirectories: true)

        let writer = ValeStyleWriter()
        try await writer.writeStyles(to: styleDir.path)

        let readabilityURL = styleDir
            .appendingPathComponent("Merlin")
            .appendingPathComponent("readability.yml")
        let yaml = try String(contentsOf: readabilityURL, encoding: .utf8)

        XCTAssertTrue(yaml.contains("extends: readability"),
                       "readability.yml must use Vale's real readability rule")
        XCTAssertFalse(yaml.contains("extends: existence"),
                        "readability.yml must not use the existence (token-matching) rule")
    }

    // MARK: - DisciplineEngine runs the prose checker

    func testEngineEmitsProseReadabilityFinding() async throws {
        try writeFile("docs/guide.md", """
        # Guide

        This document contains prose that the readability checker will grade.
        """)

        // forcedGrade 15.0 is well above any target -> must produce a fail finding.
        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(
                dryRun: true, forcedGrade: 15.0),
            storePath: projectRoot.appendingPathComponent(".merlin/pending.json").path
        )

        let report = await engine.scan(projectPath: projectRoot.path)
        let proseFindings = report.findings.filter {
            $0.category == .proseReadabilityFail
        }

        XCTAssertFalse(proseFindings.isEmpty,
                       "scan() must run the prose checker and emit a proseReadabilityFail " +
                       "finding for a doc that exceeds its target grade")
        XCTAssertEqual(proseFindings.first?.severity, .nudge)
    }
}

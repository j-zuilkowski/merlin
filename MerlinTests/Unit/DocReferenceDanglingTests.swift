import XCTest
@testable import Merlin

final class DocReferenceDanglingTests: XCTestCase {

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

    // MARK: - Fixture helpers

    private func writeFile(_ relativePath: String, _ contents: String) throws {
        let url = projectRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - danglingReferences

    func testDanglingReferenceDetected() async throws {
        try writeFile("Sources/Real.swift", """
        struct RealType {
            func realMethod() {}
        }
        """)
        try writeFile("docs/guide.md", """
        # Guide

        The `RealType` value drives behaviour. See also `NonExistentType` for details.
        """)

        let graph = DocReferenceGraph()
        let dangling = await graph.danglingReferences(projectPath: projectRoot.path)

        XCTAssertTrue(dangling.contains { $0.codeSymbol == "NonExistentType" },
                      "A backtick-quoted identifier with no matching declaration must be reported")
    }

    func testRealReferenceNotReportedAsDangling() async throws {
        try writeFile("Sources/Real.swift", """
        struct RealType {}
        """)
        try writeFile("docs/guide.md", """
        # Guide

        The `RealType` type is documented here.
        """)

        let graph = DocReferenceGraph()
        let dangling = await graph.danglingReferences(projectPath: projectRoot.path)

        XCTAssertFalse(dangling.contains { $0.codeSymbol == "RealType" },
                       "A reference to a symbol that exists in source must NOT be dangling")
    }

    func testEngineEmitsOneFindingPerDanglingReference() async throws {
        try writeFile("Sources/Real.swift", """
        struct RealType {}
        """)
        // One real mention, one dangling mention.
        try writeFile("docs/guide.md", """
        # Guide

        `RealType` is real. `GhostType` is not.
        """)

        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            phaseScanner: PhaseScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true, forcedGrade: 5.0),
            storePath: projectRoot.appendingPathComponent(".merlin/pending.json").path
        )

        let report = await engine.scan(projectPath: projectRoot.path)
        let staleFindings = report.findings.filter { $0.category == .docStaleReference }

        XCTAssertEqual(staleFindings.count, 1,
                       "Exactly one docStaleReference finding — for the dangling symbol only, " +
                       "not for every reference in the project")
        XCTAssertEqual(staleFindings.first?.summary, "GhostType")
    }
}

import XCTest
@testable import Merlin

/// Task 267 originally; rewritten by task 321b. After task 319 the only
/// dangling-reference check is the fenced-block enum-case check, so these fixtures
/// declare enum `case`s inside fenced code blocks rather than prose backticks.
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

    private func writeFile(_ relativePath: String, _ contents: String) throws {
        let url = projectRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - danglingReferences

    func testDanglingReferenceDetected() async throws {
        try writeFile("Sources/Real.swift", """
        enum RealChannel {
            case realLiveCase
        }
        """)
        try writeFile("docs/guide.md", """
        # Guide

        ```swift
        enum RealChannel {
            case ghostMissingCase
        }
        ```
        """)

        let graph = DocReferenceGraph()
        let dangling = await graph.danglingReferences(projectPath: projectRoot.path)

        XCTAssertTrue(dangling.contains { $0.codeSymbol == "ghostMissingCase" },
                      "A fenced enum case with no matching declaration must be reported")
    }

    func testRealReferenceNotReportedAsDangling() async throws {
        try writeFile("Sources/Real.swift", """
        enum RealChannel {
            case realLiveCase
        }
        """)
        try writeFile("docs/guide.md", """
        # Guide

        ```swift
        enum RealChannel {
            case realLiveCase
        }
        ```
        """)

        let graph = DocReferenceGraph()
        let dangling = await graph.danglingReferences(projectPath: projectRoot.path)

        XCTAssertFalse(dangling.contains { $0.codeSymbol == "realLiveCase" },
                       "A fenced enum case that exists in source must NOT be dangling")
    }

    func testEngineEmitsOneFindingPerDanglingReference() async throws {
        try writeFile("Sources/Real.swift", """
        enum RealChannel {
            case realLiveCase
        }
        """)
        // One real case, one dangling case — inside one fenced code block.
        try writeFile("docs/guide.md", """
        # Guide

        ```swift
        enum RealChannel {
            case realLiveCase
            case ghostMissingCase
        }
        ```
        """)

        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true, forcedGrade: 5.0),
            storePath: projectRoot.appendingPathComponent(".merlin/pending.json").path
        )

        let report = await engine.scan(projectPath: projectRoot.path)
        let staleFindings = report.findings.filter { $0.category == .docStaleReference }

        XCTAssertEqual(staleFindings.count, 1,
                       "Exactly one docStaleReference finding — for the dangling fenced " +
                       "case only, not for the real case alongside it")
        XCTAssertEqual(staleFindings.first?.summary, "ghostMissingCase")
    }
}

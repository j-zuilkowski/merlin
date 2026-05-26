import XCTest
@testable import Merlin

final class SDDTraceabilityScannerTests: XCTestCase {
    private var project: URL!

    private var repoRoot: URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != current.deletingLastPathComponent().path {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("project.yml").path
            ) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    override func setUpWithError() throws {
        project = FileManager.default.temporaryDirectory
            .appendingPathComponent("sdd-trace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("tasks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        # Vision

        ## Active

        ### Spec-Driven Development alignment

        SDD is active.
        """.write(to: project.appendingPathComponent("vision.md"), atomically: true, encoding: .utf8)
        try """
        # Spec

        ## Spec-Driven Development Methodology

        - Vision reference: vision.md#spec-driven-development-alignment
        - Spec scope: all sections
        """.write(to: project.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: project)
        project = nil
    }

    func testCleanTaskWithBehaviorAndTraceabilityProducesNoFindings() async throws {
        try writeTask("""
        # Task 999a - Example

        ## Traceability

        - Vision reference: vision.md#spec-driven-development-alignment
        - Spec reference: spec.md#spec-driven-development-methodology

        ## Behavior

        WHEN task 999a is executed THE system SHALL verify the example behavior.
        """)

        let findings = await SDDTraceabilityScanner().scan(projectPath: project.path)
        XCTAssertTrue(findings.isEmpty, findings.map(\.issue).joined(separator: ", "))
    }

    func testMissingBehaviorAndTraceabilityAreFindings() async throws {
        try writeTask("""
        # Task 999a - Example

        Context only.
        """)

        let issues = await SDDTraceabilityScanner().scan(projectPath: project.path).map(\.issue)
        XCTAssertTrue(issues.contains("missingBehavior"))
        XCTAssertTrue(issues.contains("missingTraceability"))
    }

    func testBehaviorMustUseEARSStatement() async throws {
        try writeTask("""
        # Task 999a - Example

        ## Traceability

        - Vision reference: vision.md#spec-driven-development-alignment
        - Spec reference: spec.md#spec-driven-development-methodology

        ## Behavior

        This task has prose but no testable EARS SHALL statement.
        """)

        let issues = await SDDTraceabilityScanner().scan(projectPath: project.path).map(\.issue)
        XCTAssertTrue(issues.contains("missingEARSStatement"))
    }

    func testDanglingTraceabilityReferenceIsFinding() async throws {
        try writeTask("""
        # Task 999a - Example

        ## Traceability

        - Vision reference: missing-vision.md#idea
        - Spec reference: spec.md#spec-driven-development-methodology

        ## Behavior

        WHEN task 999a is executed THE system SHALL verify the example behavior.
        """)

        let issues = await SDDTraceabilityScanner().scan(projectPath: project.path).map(\.issue)
        XCTAssertTrue(issues.contains("danglingVisionreference"))
    }

    func testDisciplineEngineSurfacesTraceabilityFindings() async throws {
        try writeTask("""
        # Task 999a - Example

        Context only.
        """)
        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: project.appendingPathComponent(".merlin/pending.json").path
        )

        let report = await engine.scan(projectPath: project.path)
        XCTAssertTrue(report.findings.contains { $0.category == .sddTraceability })
    }

    func testCurrentRepositoryTasksAreBackfilled() async throws {
        let findings = await SDDTraceabilityScanner().scan(projectPath: repoRoot.path)
        XCTAssertTrue(findings.isEmpty, findings.prefix(20).map {
            "\($0.file): \($0.issue)"
        }.joined(separator: "\n"))
    }

    private func writeTask(_ text: String) throws {
        try text.write(
            to: project.appendingPathComponent("tasks/task-999a-example-tests.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}

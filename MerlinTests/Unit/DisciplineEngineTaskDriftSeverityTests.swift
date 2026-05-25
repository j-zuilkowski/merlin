import XCTest
@testable import Merlin

/// Task 323a, rewritten by task 324b. DisciplineEngine must surface taskDrift
/// findings as `.nudge` (never `.block`). After task 324 `TaskScanner` reports a
/// declared symbol as `red` only when it is genuinely absent from source; a present
/// symbol is `green` and is not surfaced as drift.
final class DisciplineEngineTaskDriftSeverityTests: XCTestCase {

    func testTaskDriftFindingsAreNudgeNeverBlock() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-sev-\(UUID())")
        try FileManager.default.createDirectory(
            at: proj.appendingPathComponent("tasks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: proj.appendingPathComponent("Src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        // A task doc declaring one absent symbol (red drift) and one present symbol.
        let doc = """
        # Task 701b — Drift Task

        ## Context
        Test task file.

        New surface introduced in task 701b:
          - `func ghostMethod()` — absent surface
          - `Worker.presentMethod()` — present surface

        ---
        """
        try doc.write(
            to: proj.appendingPathComponent("tasks/task-701b-drift.md"),
            atomically: true, encoding: .utf8)
        try """
        import Foundation
        struct Worker {
            public func presentMethod() { }
        }
        """.write(
            to: proj.appendingPathComponent("Src/Code.swift"),
            atomically: true, encoding: .utf8)

        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true, forcedGrade: 5.0),
            storePath: proj.appendingPathComponent(".merlin/pending.json").path
        )

        let report = await engine.scan(projectPath: proj.path)
        let drift = report.findings.filter { $0.category == .taskDrift }

        XCTAssertFalse(drift.isEmpty,
                       "the absent declared symbol must surface as drift")
        XCTAssertTrue(drift.allSatisfy { $0.severity == .nudge },
                      "taskDrift findings must be nudge severity — never block")
        XCTAssertTrue(drift.contains { $0.summary.contains("ghostMethod") },
                      "the absent symbol (red drift) is surfaced as a nudge")
        XCTAssertFalse(drift.contains { $0.summary.contains("presentMethod") },
                       "a symbol present in source is green and not surfaced as drift")
    }
}
